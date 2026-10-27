/**
 * HIMI HarmonyOS MPV 播放插件。
 *
 * 基于 @mpv-ohos/mpv-arkts 的底层 MpvLib。驱动顺序与 mpv-arkts 自带的
 * Player.ets（ydplayer 同款、真机验证可播）完全一致：
 *
 *   create → requestLogMessages → setOptionString×N → initialize
 *   → observeProperty → 此后才允许 attachSurface / loadFile
 *
 * 二进制契约（libmpv_wrapper.so 内的 [napi:*] 错误串）：除 create 外的
 * 所有方法在未完成前置步骤时都会被拒（"mpv is not initialized"）。
 * **尤其 attachSurface 不能在 initialize 之前调用**——v1.2.72 及更早
 * 正是死在这里：先 attach 后 initialize 被拒 → initialize 永不执行 →
 * pollState 恒空 → 无时长、无限转圈。
 *
 * 渲染走 PlatformView（XComponent）：mpv 的 ohosvk vo 需要真正的
 * OHNativeWindow（Flutter 纹理的 producer surfaceId 不满足要求）。
 * surface 到达后 attachSurface（运行期可反复 attach/detach）；
 * 媒体加载不依赖 surface，surface 迟迟不到由 watchdog 兜底直载。
 */

import {
  EventChannel,
  EventSink,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StandardMethodCodec,
} from '@ohos/flutter_ohos';
import { TextureRegistry, SurfaceTextureEntry } from '@ohos/flutter_ohos';
// `MpvNode` 没有从 mpv.har 的 Index.ets 导出，无法直接 import；
// commandWithReturn 的返回值按 ESObject 处理（运行时是 Map/标量/数组）。
import { MpvLib, MpvFormat, EventObserver, LogObserver } from '@mpv-ohos/mpv-arkts';
import { hilog } from '@kit.PerformanceAnalysisKit';
import display from '@ohos.display';
import { HimiMpvPlatformView, HimiMpvPlatformViewFactory, MPV_VIEW_TYPE } from './HimiMpvPlatformView';
import { MpvSurfaceCallbacks } from './HimiMpvSurface';

const TAG = 'HimiMpv';
const DOMAIN = 0x0001;
const METHOD_CHANNEL = 'himi_mpv';
const EVENT_CHANNEL = 'himi_mpv/events';

/** 初始纹理尺寸；拿到 video-params 后按真实分辨率重建。 */
const DEFAULT_WIDTH = 1920;
const DEFAULT_HEIGHT = 1080;

/**
 * 事件负载。ArkTS 不允许无类型对象字面量（arkts-no-untyped-obj-literals），
 * 故三种负载各自声明 interface，用联合类型传给 EventSink。
 */
interface MpvPropertyPayload {
  type: string;
  name: string;
  value: number | boolean | string | null;
}

interface MpvEventPayload {
  type: string;
  id: number;
  name: string;
}

interface MpvLogPayload {
  type: string;
  level: string;
  prefix: string;
  message: string;
}

type MpvPayload = MpvPropertyPayload | MpvEventPayload | MpvLogPayload;

/** `pollState` 的返回值（纯数据，不依赖事件回调）。 */
interface MpvPollPayload {
  durationMs: number;
  positionMs: number;
  bufferedMs: number;
  paused: boolean;
  eofReached: boolean;
  videoParams: string | null;
  trackList: string | null;
  /** mpv 是否空闲（无文件）——区分「没加载」与「加载了没动」。 */
  idleActive: boolean;
  /** 播放列表条数（0 = loadfile 从未成功执行）。 */
  playlistCount: number;
  /** 因缓冲暂停（网络/demuxer 停滞）。 */
  pausedForCache: boolean;
  /** 缓冲进度（0-100，-1 表示不可用）。 */
  cachePercent: number;
  /** 实际生效的硬件解码器（hwdec-current；''=无视频/未启用，'no'=软解）。 */
  hwdecCurrent: string | null;
  gpuContext: string | null;
  currentVo: string | null;
  mediaTitle: string | null;
  /** 掩码后的播放地址（去 query、取尾部）——加载失败回 idle 后由
   *  open 时缓存的 lastUrlMasked 兜底（v1.2.77）。
   */
  pathMasked: string | null;
}

/**
 * surface 回调的具名实现。
 *
 * ArkTS 禁止把对象字面量直接赋给接口类型（arkts-no-untyped-obj-literals），
 * 所以用 class 实现 [MpvSurfaceCallbacks]。
 */
class PluginSurfaceCallbacks implements MpvSurfaceCallbacks {
  private readonly plugin: HimiMpvOhosPlugin;

  constructor(plugin: HimiMpvOhosPlugin) {
    this.plugin = plugin;
  }

  onSurfaceCreated(surfaceId: string): void {
    this.plugin.handleSurfaceCreated(surfaceId);
  }

  onSurfaceChanged(surfaceId: string, width: number, height: number): void {
    this.plugin.handleSurfaceChanged(surfaceId, width, height);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    this.plugin.handleSurfaceDestroyed(surfaceId);
  }
}

class MpvSession implements EventObserver, LogObserver {
  lib: MpvLib = new MpvLib();
  /// 纹理渲染模式：插件自注册的 Flutter 纹理 id（>0）。
  /// mpv 直接渲染进该纹理的生产者 surface（标准 video_player 架构）。
  textureId: number = 0;
  textureEntry: SurfaceTextureEntry | null = null;
  width: number = DEFAULT_WIDTH;
  height: number = DEFAULT_HEIGHT;
  initialized: boolean = false;
  /// mpv 的输出窗口已绑定（纹理模式的生成者 surface，或 XComponent surface）。
  surfaceAttached: boolean = false;
  /// 当前渲染档位（standard/performance/extreme）。
  hwdecMode: string = 'performance';

  onPropertyChanged(property: string, value?: number | boolean | string): void {
    const payload: MpvPropertyPayload = {
      type: 'property',
      name: property,
      value: value === undefined ? null : value,
    };
    HimiMpvOhosPlugin.emit(payload);
  }

  onEvent(id: number, name: string): void {
    const payload: MpvEventPayload = { type: 'event', id: id, name: name };
    HimiMpvOhosPlugin.emit(payload);
  }

  onLogMessage(prefix: string, level: string, msg: string): void {
    if (level === 'error' || level === 'fatal') {
      hilog.error(DOMAIN, TAG, '%{public}s', msg);
    }
    const payload: MpvLogPayload = {
      type: 'log',
      level: level,
      prefix: prefix,
      message: msg,
    };
    HimiMpvOhosPlugin.emit(payload);
  }
}

export default class HimiMpvOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private binding: FlutterPluginBinding | null = null;
  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private static eventSink: EventSink | null = null;
  private session: MpvSession | null = null;

  /// XComponent 已创建但 mpv 尚未 initialize 时，先把 surfaceId 存下来。
  private pendingSurfaceId: string | null = null;

  /// surface 未就绪时缓存的待播 URL（就绪后自动加载）。
  private pendingUrl: string | null = null;
  private pendingOptions: Map<string, string> | null = null;
  private pendingPause: boolean = true;

  getUniqueClassName(): string {
    return 'HimiMpvOhosPlugin';
  }

  static emit(payload: MpvPayload): void {
    const sink = HimiMpvOhosPlugin.eventSink;
    if (sink !== null) {
      sink.success(payload);
    }
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binding = binding;
    this.methodChannel = new MethodChannel(
      binding.getBinaryMessenger(),
      METHOD_CHANNEL,
      StandardMethodCodec.INSTANCE,
    );
    this.methodChannel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(
      binding.getBinaryMessenger(),
      EVENT_CHANNEL,
      StandardMethodCodec.INSTANCE,
    );
    this.eventChannel.setStreamHandler({
      onListen: (_args: ESObject, sink: EventSink): void => {
        HimiMpvOhosPlugin.eventSink = sink;
      },
      onCancel: (_args: ESObject): void => {
        HimiMpvOhosPlugin.eventSink = null;
      },
    });

    // 注册 MPV 平台视图工厂：Dart 侧用 PlatformViewLink(viewType:
    // 'himi_mpv_surface') 挂载，ArkTS 侧返回 XComponent。
    // mpv 的 ohosvk vo 需要真实的 OHNativeWindow，只能用 XComponent 提供，
    // 不能用 Flutter 纹理（见 HimiMpvSurface 顶部说明）。
    const registry = binding.getPlatformViewRegistry();
    if (registry !== null && registry !== undefined) {
      // 回调在 Plugin 构造时就准备好，交给工厂；工厂创建视图时立即绑定，
      // 不依赖「视图晚到再注入」的时序。
      const callbacks = new PluginSurfaceCallbacks(this);
      const factory = new HimiMpvPlatformViewFactory(callbacks);
      const ok = registry.registerViewFactory(MPV_VIEW_TYPE, factory);
      hilog.info(DOMAIN, TAG, 'registerViewFactory(%{public}s) = %{public}s',
        MPV_VIEW_TYPE, `${ok}`);
    } else {
      hilog.error(DOMAIN, TAG, 'PlatformViewRegistry 不可用，无法注册 MPV 平台视图');
    }
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.destroySession();
    const methodChannel = this.methodChannel;
    if (methodChannel !== null) {
      methodChannel.setMethodCallHandler(null);
    }
    const eventChannel = this.eventChannel;
    if (eventChannel !== null) {
      eventChannel.setStreamHandler(null);
    }
    this.methodChannel = null;
    this.eventChannel = null;
    HimiMpvOhosPlugin.eventSink = null;
    this.binding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    // ArkTS 禁止 `??`：显式判空后再取用。
    let args: Map<string, ESObject> = new Map<string, ESObject>();
    if (call.args != null && call.args instanceof Map) {
      args = call.args as Map<string, ESObject>;
    }
    try {
      switch (call.method) {
        case 'queryHdrCapabilities': {
          const formats: string[] = [];
          try {
            const d = display.getDefaultDisplaySync();
            const hdrFormats: number[] = d.hdrFormats ?? [];
            if (hdrFormats.includes(2)) formats.push('hdr10');
            if (hdrFormats.includes(1)) formats.push('hlg');
            if (hdrFormats.includes(3)) formats.push('dolbyVision');
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'queryHdrCapabilities failed: %{public}s', String(e));
          }
          result.success({ 'formats': formats });
          return;
        }
        case 'create':
          this.createSession(args, result);
          return;
        case 'dispose':
          this.destroySession();
          result.success(null);
          return;
        case 'open':
          this.open(args, result);
          return;
        case 'play':
          this.requireLib().setProperty('pause', false);
          result.success(null);
          return;
        case 'pause':
          this.requireLib().setProperty('pause', true);
          result.success(null);
          return;
        case 'seek':
          this.seek(args, result);
          return;
        case 'stop':
          this.requireLib().command(['stop']);
          result.success(null);
          return;
        case 'setVolume':
          this.requireLib().setProperty('volume', this.number(args, 'volume', 1.0) * 100.0);
          result.success(null);
          return;
        case 'setSpeed':
          this.requireLib().setProperty('speed', this.number(args, 'speed', 1.0));
          result.success(null);
          return;
        case 'setAudioTrack':
          this.requireLib().setProperty('aid', this.number(args, 'id', 0));
          result.success(null);
          return;
        case 'setSubtitleTrack':
          this.requireLib().setProperty('sid', this.number(args, 'id', 0));
          result.success(null);
          return;
        case 'addSubtitle':
          this.addSubtitle(args, result);
          return;
        case 'setProperty':
          this.setProperty(args, result);
          return;
        case 'getProperty':
          result.success(this.getProperty(args));
          return;
        case 'resizeTexture':
          this.resizeTexture(args, result);
          return;
        case 'screenshot':
          this.screenshot(result);
          return;
        case 'getTracks':
          result.success(this.getPropertyByName('track-list'));
          return;
        case 'getVideoParams':
          result.success(this.getPropertyByName('video-params'));
          return;
        case 'getAudioParams':
          result.success(this.getPropertyByName('audio-params'));
          return;
        case 'pollState':
          this.pollState(result);
          return;
        case 'setHwdecMode':
          // 渲染档位实时切换（播放中也可生效：都是运行期属性）。
          {
            const modeValue: ESObject = args.get('mode');
            const mode: string = typeof modeValue === 'string'
              ? modeValue as string
              : 'performance';
            this.applyHwdecModePreset(this.requireSession(), mode);
            result.success(null);
            return;
          }
        case 'kick':
          // 踢一脚开始播放：loadFile 后条目不会自动开播（尤其 stop 之后），
          // 必须显式设置 playlist-pos 才会开始加载（参考 Player.ets 的
          // open()：loadFile 后 setProperty('playlist-pos', index)）。
          this.requireLib().setProperty('playlist-pos', 0);
          result.success(null);
          return;
        case 'isReady':
          result.success(this.session !== null && this.session.initialized
            && this.session.surfaceAttached);
          return;
        default:
          result.notImplemented();
          return;
      }
    } catch (error) {
      // ArkTS 的 catch 变量类型是 Object，需显式收窄后才能取 message。
      let errMsg: string = '';
      if (error instanceof Error) {
        errMsg = (error as Error).message;
      } else {
        errMsg = String(error);
      }
      hilog.error(DOMAIN, TAG, 'method %{public}s failed: %{public}s', call.method, errMsg);
      result.error('HIMI_MPV_ERROR', errMsg, null);
    }
  }

  // ── 会话生命周期 ─────────────────────────────────────────────

  private createSession(args: Map<string, ESObject>, result: MethodResult): void {
    this.destroySession();
    if (this.binding === null) {
      result.error('NO_BINDING', 'plugin is not attached to engine', null);
      return;
    }

    const width = Math.max(1, Math.trunc(this.number(args, 'width', DEFAULT_WIDTH)));
    const height = Math.max(1, Math.trunc(this.number(args, 'height', DEFAULT_HEIGHT)));
    const nativeSurface = args.get('nativeSurface') === true;
    const hdr = args.get('hdr') === true;
    const hlg = args.get('hlg') === true;

    const session = new MpvSession();
    session.width = width;
    session.height = height;
    // 平台视图模式下没有 Flutter 纹理 id，返回一个稳定标识供上层记录。
    session.textureId = nativeSurface ? 0 : -1;

    // 顺序与 mpv-arkts Player.ets 完全一致（真机验证可播，不可调换）：
    //   1) JSBind 回调最先注册：initialize() 启动 mpv 事件线程，事件派发走
    //      TaskRunner::PostTask("main")，该函数不判空——initTaskRunner
    //      晚了会在第一个事件上空指针崩溃，之后属性/事件/日志全丢。
    //   2) create → requestLogMessages → setOptionString（只要求已 create）
    //      → initialize。attachSurface / loadFile / setProperty / getProperty
    //      必须等 initialize 完成（wrapper 报 "mpv is not initialized"）。
    //   3) initialize 后 observeProperty，属性才有初始推送。
    session.lib.addEventObserver(session);
    session.lib.addLogObserver(session);
    session.lib.registerEventCallback();
    session.lib.registerLogCallback();

    try {
      session.lib.create();
      // warn 级：流打不开/解码失败/vo 异常在 mpv 里多为 error/warn，
      // 只订 error 会漏掉关键线索（v1.2.75）。
      session.lib.requestLogMessages('warn');
      this.applyOptions(session);
      if (hdr) {
        session.lib.setOptionString('target-colorspace-hint', 'yes');
        session.lib.setOptionString('target-prim', 'bt.2020');
        session.lib.setOptionString('target-trc', hlg ? 'hlg' : 'pq');
        session.lib.setOptionString('hdr-compute-peak', 'auto');
        session.lib.setOptionString('tone-mapping', 'clip');
        hilog.info(DOMAIN, TAG, 'HDR 输出: %{public}s', hlg ? 'HLG' : 'HDR10');
      }
      // 硬解渲染档位（standard/performance/extreme，v1.2.82）：
      // 由 Dart 侧从设置传入，未传时用 performance 默认。
      const modeValue: ESObject = args.get('hwdecMode');
      this.applyHwdecModePreset(
        session,
        typeof modeValue === 'string' ? modeValue as string : 'performance',
      );
      session.lib.initialize();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'mpv create/initialize 失败: %{public}s', String(e));
      result.error('MPV_INIT_FAILED', String(e), null);
      return;
    }

    // 自检：初始化成功后 mpv-version 必定可读。
    let version: string = '';
    try {
      version = session.lib.getPropertyString('mpv-version');
    } catch (_) {
    }
    if (version.length === 0) {
      hilog.error(DOMAIN, TAG, 'mpv_initialize 失败（mpv-version 不可读）');
      try {
        session.lib.destroy();
      } catch (_) {
      }
      result.error('MPV_INIT_FAILED', 'mpv-version unreadable', null);
      return;
    }
    hilog.info(DOMAIN, TAG, 'mpv_initialize ok: %{public}s', version);
    session.initialized = true;
    this.observeProperties(session.lib);

    // 渲染模式：
    // - SDR 纹理：注册 Flutter 纹理，把生产者 surfaceId 交给 mpv；
    // - HDR/SDR 直出：nativeSurface=true，由 XComponent 平台视图提供真实
    //   OHNativeWindow（RENDER_TYPE_DISPLAY），Flutter 仅做透明控件层。
    let textureSurfaceId: string | null = null;
    if (!nativeSurface) {
      try {
        const registry: TextureRegistry | null = this.binding.getTextureRegistry();
      if (registry !== null) {
        const texId: number = registry.getTextureId();
        const entry: SurfaceTextureEntry = registry.registerTexture(texId);
        session.textureId = texId;
        session.textureEntry = entry;
        textureSurfaceId = entry.getSurfaceId().toString();
        hilog.info(DOMAIN, TAG, 'Flutter 纹理注册成功: id=%{public}d surface=%{public}s',
          texId, textureSurfaceId);
      }
      } catch (e) {
        hilog.error(DOMAIN, TAG, '纹理注册失败（回退平台视图模式）: %{public}s', String(e));
      }
    }

    if (textureSurfaceId !== null) {
      try {
        session.lib.attachSurface(textureSurfaceId);
        session.surfaceAttached = true;
        hilog.info(DOMAIN, TAG, 'mpv 已绑定 Flutter 纹理生产者 surface');
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'attachSurface(纹理) 失败: %{public}s', String(e));
      }
    }

    this.session = session;

    // XComponent 的 surface 若先于 create 到达且纹理模式未生效（回退路径），
    // 这里补 attach。
    this.tryBindSurface();

    // 返回纹理 id：>0 = 纹理渲染模式（Dart 挂 Texture）；0 = 回退平台视图。
    result.success(session.textureId);
  }

  // ── 平台视图 surface 生命周期 ────────────────────────────────

  handleSurfaceCreated(surfaceId: string): void {
    hilog.info(DOMAIN, TAG, 'surface created: %{public}s', surfaceId);
    // surface 属于 XComponent，不属于某次 mpv 会话：即便 create 还没来也
    // 先记下，createSession 完成后由 tryBindSurface 消费。
    this.pendingSurfaceId = surfaceId;
    this.tryBindSurface();
  }

  handleSurfaceChanged(surfaceId: string, width: number, height: number): void {
    const session = this.session;
    if (session === null || !session.initialized) return;
    session.width = width;
    session.height = height;
    try {
      // mpv 用它计算输出缩放；不设也能播，但设了更贴合窗口。
      session.lib.setProperty('ohos-surface-size', `${width}x${height}`);
    } catch (_) {
    }
    hilog.info(DOMAIN, TAG, 'surface changed: %{public}dx%{public}d', width, height);
  }

  handleSurfaceDestroyed(surfaceId: string): void {
    hilog.info(DOMAIN, TAG, 'surface destroyed: %{public}s', surfaceId);
    const session = this.session;
    if (session !== null && session.initialized) {
      try {
        session.lib.detachSurface();
      } catch (_) {
      }
      session.surfaceAttached = false;
    }
    this.pendingSurfaceId = null;
  }

  /// mpv 已 initialize 且 XComponent 已就绪时，把 surface 交给 mpv。
  ///
  /// 两者到达顺序不确定（平台视图由 Flutter 侧创建，create 由 Dart 主动调），
  /// 所以这里做「谁后到谁触发绑定」的幂等处理。
  private tryBindSurface(): void {
    const session = this.session;
    const surfaceId = this.pendingSurfaceId;
    if (session === null || !session.initialized || surfaceId === null) {
      return;
    }
    // 幂等：已 attach 过就跳过，避免重复写 wid。
    if (session.surfaceAttached) {
      return;
    }
    try {
      session.lib.attachSurface(surfaceId);
      hilog.info(DOMAIN, TAG, 'attachSurface ok: %{public}s', surfaceId);
      session.surfaceAttached = true;
      // surface 就绪后立即加载之前缓存的 URL（若有）。
      this.loadPendingUrl(false);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'attachSurface 失败: %{public}s', String(e));
    }
  }

  private destroySession(): void {
    this.cancelPendingWatchdog();
    const session = this.session;
    if (session === null) {
      return;
    }
    this.session = null;
    this.pendingUrl = null;
    this.pendingOptions = null;
    try {
      if (session.initialized) {
        // 顺序必须与创建相反：先 detachSurface + destroy（destroy 内部会
        // 置 request_thread_exit 并 join 事件线程，确保不再有 PostTask），
        // 再解绑回调。若先解绑，仍在运行的事件线程会 PostTask 到已解绑的
        // "main" runner 上——PostTask 无判空，直接空指针。
        if (session.surfaceAttached) {
          try {
            session.lib.detachSurface();
          } catch (_) {
          }
        }
        session.lib.destroy();
        session.lib.removeEventObserver(session);
        session.lib.removeLogObserver(session);
        session.lib.removeEventCallbacks();
        session.lib.removeLogCallback();
      }
    } catch (_) {
    }
    // 纹理注销：释放 Flutter 纹理与生产者 surface。
    if (session.textureEntry !== null && this.binding !== null) {
      try {
        this.binding.getTextureRegistry().unregisterTexture(session.textureId);
      } catch (_) {
      }
      session.textureEntry = null;
    }
  }

  private applyOptions(session: MpvSession): void {
    const lib = session.lib;
    lib.setOptionString('config', 'no');
    lib.setOptionString('idle', 'yes');
    lib.setOptionString('keep-open', 'yes');
    lib.setOptionString('input-ime', 'no');
    lib.setOptionString('input-builtin-bindings', 'no');
    lib.setOptionString('osc', 'no');
    lib.setOptionString('osd-level', '0');

    // HarmonyOS Vulkan 输出：OHCodec 10bit 零拷贝互操作只在 ohosvk 下可用。
    lib.setOptionString('vo', 'gpu-next');
    lib.setOptionString('gpu-api', 'vulkan');
    lib.setOptionString('gpu-context', 'ohosvk');
    // hwdec 用 mpv 标准探测值 auto；Dart 侧 prepare 会按用户解码档位覆盖。
    lib.setOptionString('hwdec', 'auto');
    // v1.2.85 扩容：补 AV1/VP9/prores/mjpeg 等（解复用层支持即解码），
    // 硬件不支持时 mpv 自动回退软解。
    lib.setOptionString('hwdec-codecs',
      'h264,hevc,mpeg2video,mpeg4,h263,vvc,av1,vp9,vp8');
    lib.setOptionString('hwdec-software-fallback', 'yes');

    // ── HDR/SDR 色彩（v1.2.95 重构）────────────────────────
    // 用户原始基线：SDR 色彩亮度本来就正确，只有 HDR 暗。
    // **创建期不再写任何 target-*/tone-mapping 色彩选项**——SDR 路径
    // 保持与原版逐字节一致（零色彩配置）；HDR 所需的完整管线
    //（colormatrix 输入标签 + target-*/tone-mapping 输出锁定）由
    // Dart 侧在 prepare 时按内容类型动态写入（见 adapter）。
    // 仅保留 hint=no（SDR→SDR 无影响；HDR 防止协商 PQ 直出）。
    lib.setOptionString('target-colorspace-hint', 'no');
    lib.setOptionString('video-sync', 'display-resample');
    // 插值/同步策略/缓冲/丢帧由「硬解渲染档位」统一驱动（v1.2.82，
    // 见 applyHwdecModePreset），此处不再写死。
    lib.setOptionString('correct-downscaling', 'no');
    lib.setOptionString('sigmoid-upscaling', 'no');
    lib.setOptionString('dither-depth', 'no');
    lib.setOptionString('deinterlace', 'no');
    lib.setOptionString('demuxer-max-bytes', '1024MiB');
    lib.setOptionString('demuxer-max-back-bytes', '512MiB');
    lib.setOptionString('network-timeout', '30');
    // 缓冲行为组（v1.2.85，移植 ydbox PlayerPage 实测参数）：
    // - cache=yes + readahead 10s：提前读流，起播后很快进入稳态；
    // - cache-pause=yes：缓冲耗尽自动暂停等数据（防卡成幻灯片）；
    // - hysteresis=0：数据一到位立即恢复，暂停窗口最短。
    // v1.2.94 撤销 cache-pause-initial=no 实验（v1.2.92 引入、未经真机
    // 验证即随包发布——慢网下边缓冲边播会立刻进缓冲-恢复抖动，配合
    // 起播等待实验一起构成全片源回归的嫌疑面）。回到 mpv 默认。
    lib.setOptionString('cache', 'yes');
    lib.setOptionString('demuxer-readahead-secs', '10');
    lib.setOptionString('cache-pause', 'yes');
    lib.setOptionString('demuxer-hysteresis-secs', '0');
    // HLS 起播加速：提前拉取播放列表，省一次往返（v1.2.81）。
    lib.setOptionString('prefetch-playlist', 'yes');
    // 关闭 yt-dlp 回退：Emby 直链/HLS 用不上；URL 打不开时 mpv 会回退
    // 调 yt-dlp（真机上没有该程序），报 "youtube-d failed" 警告并掩盖
    // 真正的第一现场错误（v1.2.76 真机诊断实测）。
    lib.setOptionString('ytdl', 'no');
    // 家庭 Emby 常见自签名 https：mpv 默认校验证书会直接失败，
    // Android/iOS 播放器普遍不校验——对齐该行为。
    lib.setOptionString('tls-verify', 'no');
    // 记录这些选项，配合 watch-later 恢复播放进度/轨道选择。
    lib.setOptionString('watch-later-options', 'start,vid,aid,sid');

    lib.setOptionString('volume', '100');
    lib.setOptionString('alang', 'chi,zh,eng');
    lib.setOptionString('slang', 'chi,zh,eng');

    lib.setOptionString('sub-scale-with-window', 'no');
    lib.setOptionString('sub-use-margins', 'no');
    // 'no' 会让同目录外挂字幕完全不加载；Emby 的外挂字幕走 sub-add，
    // 但本地文件/STRM 场景需要 fuzzy 才能自动带出同名字幕。
    lib.setOptionString('sub-auto', 'fuzzy');
    lib.setOptionString('subs-fallback', 'yes');
    lib.setOptionString('osd-font', 'HarmonyOS Sans');
    lib.setOptionString('sub-font-size', '38');
    lib.setOptionString('sub-color', '#ffffffff');
    lib.setOptionString('sub-outline-size', '2');
    lib.setOptionString('sub-outline-color', '#ff000000');
    lib.setOptionString('sub-bold', 'yes');

    // 初始化后回读关键选项，确认真的生效（写入失败时 mpv 会静默忽略）。
    hilog.info(DOMAIN, TAG, 'options applied');
  }

  /// 硬解渲染档位（设置页：标准/高性能/极速，v1.2.82）。
  ///
  /// 档位定义借鉴 ydbox（ohmosydplayer PlayerPage.applyHwdecMode）并按
  /// 本机实测微调缓冲档：
  /// - standard    完整画质：时间插值补帧 + display-resample + 大缓冲
  ///               （1024/512MiB）。GPU 负载最高（24fps 片源在 120Hz 屏
  ///               逐帧混合中间帧），画面最顺滑。
  /// - performance 高性能（默认）：关插值、audio 同步、中缓冲（256/128MiB）、
  ///               framedrop=vo。功耗与画质的平衡点（v1.2.81 降温配置）。
  /// - extreme     极速：再压缓冲（128/64MiB）+ framedrop=decoder+vo，
  ///               低端机高码率场景保不卡。
  applyHwdecModePreset(session: MpvSession, mode: string): void {
    const lib = session.lib;
    try {
      if (mode === 'standard') {
        lib.setOptionString('interpolation', 'yes');
        lib.setOptionString('video-sync', 'display-resample');
        lib.setOptionString('demuxer-max-bytes', '1024MiB');
        lib.setOptionString('demuxer-max-back-bytes', '512MiB');
        lib.setOptionString('framedrop', 'vo');
      } else if (mode === 'extreme') {
        lib.setOptionString('interpolation', 'no');
        lib.setOptionString('video-sync', 'audio');
        lib.setOptionString('demuxer-max-bytes', '128MiB');
        lib.setOptionString('demuxer-max-back-bytes', '64MiB');
        lib.setOptionString('framedrop', 'decoder+vo');
      } else {
        // performance（默认）
        lib.setOptionString('interpolation', 'no');
        lib.setOptionString('video-sync', 'audio');
        lib.setOptionString('demuxer-max-bytes', '256MiB');
        lib.setOptionString('demuxer-max-back-bytes', '128MiB');
        lib.setOptionString('framedrop', 'vo');
      }
      session.hwdecMode = mode;
      hilog.info(DOMAIN, TAG, '渲染档位: %{public}s', mode);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '渲染档位设置失败: %{public}s', String(e));
    }
  }

  private observeProperties(lib: MpvLib): void {
    // ArkTS 不允许把 number 用 `as` 强转成枚举，故 Map 值类型直接用 MpvFormat。
    const props: Map<string, MpvFormat> = new Map<string, MpvFormat>([
      ['time-pos/full', MpvFormat.MPV_FORMAT_DOUBLE],
      ['duration/full', MpvFormat.MPV_FORMAT_DOUBLE],
      ['pause', MpvFormat.MPV_FORMAT_FLAG],
      ['volume', MpvFormat.MPV_FORMAT_DOUBLE],
      ['speed', MpvFormat.MPV_FORMAT_DOUBLE],
      ['eof-reached', MpvFormat.MPV_FORMAT_FLAG],
      ['paused-for-cache', MpvFormat.MPV_FORMAT_FLAG],
      ['cache-buffering-state', MpvFormat.MPV_FORMAT_DOUBLE],
      ['demuxer-cache-time', MpvFormat.MPV_FORMAT_DOUBLE],
      ['video-bitrate', MpvFormat.MPV_FORMAT_DOUBLE],
      ['audio-bitrate', MpvFormat.MPV_FORMAT_DOUBLE],
      ['track-list', MpvFormat.MPV_FORMAT_NODE],
      ['video-params', MpvFormat.MPV_FORMAT_NODE],
      ['audio-params', MpvFormat.MPV_FORMAT_NODE],
      ['media-title', MpvFormat.MPV_FORMAT_STRING],
      ['seekable', MpvFormat.MPV_FORMAT_FLAG],
    ]);
    props.forEach((format: MpvFormat, name: string): void => {
      lib.observeProperty(name, format);
    });
  }

  // ── 播放控制 ─────────────────────────────────────────────────

  /// 最近一次 open 尝试的掩码地址（插件级：会话销毁后仍保留，
  /// 供加载失败回 idle 后的诊断展示）。
  private lastUrlMasked: string | null = null;

  /// 去掉 query（含 api_key）并截尾——诊断够用且不泄露 token。
  private maskUrl(url: string): string {
    const noQuery = url.split('?')[0];
    return noQuery.length > 72 ? noQuery.substring(noQuery.length - 72) : noQuery;
  }

  private open(args: Map<string, ESObject>, result: MethodResult): void {
    const session = this.requireSession();
    const urlValue: ESObject = args.get('url');
    if (typeof urlValue !== 'string' || (urlValue as string).length === 0) {
      result.error('INVALID_ARGUMENT', 'url is required', null);
      return;
    }
    const url: string = urlValue as string;
    const options: Map<string, string> = new Map<string, string>();

    const headers: ESObject = args.get('headers');
    if (headers instanceof Map && (headers as Map<string, ESObject>).size > 0) {
      const fields: string[] = [];
      (headers as Map<string, ESObject>).forEach((value: ESObject, key: string): void => {
        let headerValue: string = '';
        if (typeof value === 'string') {
          headerValue = value as string;
        } else if (value !== null && value !== undefined) {
          headerValue = String(value);
        }
        const line = `${key}: ${headerValue}`;
        // mpv 的 http-header-fields 要求 `%<字节长度>%<header>` 逐条以逗号分隔。
        fields.push(`%${line.length}%${line}`);
      });
      options.set('http-header-fields', fields.join(','));
      // 双保险：同一批 header 也写成全局属性——即使 wrapper 的 loadfile
      // options 字符串拼装有问题（未经验证的黑盒），网络请求仍带鉴权头
      //（v1.2.77：URL 打开失败排查的一部分）。
      try {
        session.lib.setProperty('http-header-fields', fields.join(','));
      } catch (_) {
      }
    }

    const startMs = this.number(args, 'startMs', 0);
    if (startMs > 0) {
      options.set('start', (startMs / 1000.0).toFixed(3));
    }

    const pauseValue: ESObject = args.get('pause');
    const pause: boolean = pauseValue === true;

    // surface 未 attach 时先缓存，等 XComponent 就绪后加载（参考实现同款：
    // 「MPV surface ready, loading pending URL」）。正常情况下 surface 与
    // create 同帧到达，几乎立即触发。若平台视图链路异常导致 surface 一直
    // 不来，由 watchdog（8s）兜底直载——宁可让 mpv 报错（错误经事件流
    // 反馈到界面诊断），也不能永远停在「转圈、无时长」。
    if (!session.surfaceAttached) {
      this.pendingUrl = url;
      this.pendingOptions = options;
      this.pendingPause = pause;
      hilog.info(DOMAIN, TAG, 'surface 未就绪，缓存待播 URL（len=%{public}d）', url.length);
      this.schedulePendingWatchdog();
      result.success(null);
      return;
    }

    hilog.info(DOMAIN, TAG, 'open: url len=%{public}d headers=%{public}d start=%{public}d',
      url.length, options.size, startMs);
    this.loadUrl(session, url, options, pause);
    result.success(null);
  }

  /// 参考序列加载（open 直载与 loadPendingUrl 共用）。
  ///
  /// 与 mpv-arkts Player.ets 的 open() 完全一致（缺一不可）：
  ///   stop → playlist-clear → playlist-play-index none → pause=true
  ///   → loadFile → **playlist-pos=0** → 按需解除暂停
  ///
  /// 最后的 playlist-pos=0 是关键一踢：`stop` 之后追加的播放条目**不会
  /// 自动开播**，必须显式指派 playlist-pos 才开始加载——v1.2.75 真机
  /// 诊断「空闲=是 播放列表=1」正是缺这一脚（条目躺在列表里永远不加载）。
  private loadUrl(
    session: MpvSession,
    url: string,
    options: Map<string, string>,
    pause: boolean,
  ): void {
    // 记录本次尝试的地址（掩码）：失败回 idle 后 path 属性读不到，
    // 诊断仍需展示「最后尝试的 URL」（v1.2.77）。
    this.lastUrlMasked = this.maskUrl(url);
    session.lib.command(['stop']);
    session.lib.command(['playlist-clear']);
    session.lib.command(['playlist-play-index', 'none']);
    session.lib.setProperty('pause', true);
    session.lib.loadFile(url, options);
    session.lib.setProperty('playlist-pos', 0);
    session.lib.setProperty('pause', pause);
  }

  /// surface 就绪（或 watchdog 兜底）后加载之前缓存的 URL。
  ///
  /// [force] 为 true 时无视 surface 状态直接加载（watchdog 路径）。
  private loadPendingUrl(force: boolean): void {
    const session = this.session;
    const url = this.pendingUrl;
    if (session === null || !session.initialized || url === null) {
      return;
    }
    if (!force && !session.surfaceAttached) {
      return;
    }
    const options: Map<string, string> = this.pendingOptions !== null
      ? this.pendingOptions
      : new Map<string, string>();
    const pause: boolean = this.pendingPause;
    this.pendingUrl = null;
    this.pendingOptions = null;
    this.cancelPendingWatchdog();
    hilog.info(DOMAIN, TAG, '加载待播 URL（len=%{public}d surface=%{public}s force=%{public}s）',
      url.length, `${session.surfaceAttached}`, `${force}`);
    try {
      this.loadUrl(session, url, options, pause);
    } catch (e) {
      hilog.error(DOMAIN, TAG, '加载待播 URL 失败: %{public}s', String(e));
    }
  }

  /// 待播 URL 的兜底定时器句柄（-1 表示未挂）。
  private pendingWatchdog: number = -1;

  /// surface 8 秒仍未就绪时强制加载缓存 URL。
  ///
  /// 正常路径 surface 与 create 同帧到达，watchdog 在 loadPendingUrl 里被
  /// 取消，永不触发；只有平台视图链路断裂（视图未挂载/零尺寸/回调丢失）
  /// 时才会走到这里——此时直载让 mpv 至少把时长/轨道解析出来（错误也会
  /// 经事件流送达界面），把「无限转圈」变成可诊断的确定状态。
  private schedulePendingWatchdog(): void {
    this.cancelPendingWatchdog();
    this.pendingWatchdog = setTimeout((): void => {
      this.pendingWatchdog = -1;
      const session = this.session;
      if (session === null || this.pendingUrl === null) {
        return;
      }
      if (!session.surfaceAttached) {
        hilog.error(DOMAIN, TAG, 'surface 8s 未就绪，watchdog 强制加载待播 URL');
      }
      this.loadPendingUrl(true);
    }, 8000);
  }

  private cancelPendingWatchdog(): void {
    if (this.pendingWatchdog >= 0) {
      clearTimeout(this.pendingWatchdog);
      this.pendingWatchdog = -1;
    }
  }

  private seek(args: Map<string, ESObject>, result: MethodResult): void {
    const positionMs = this.number(args, 'positionMs', 0);
    const lib = this.requireLib();
    lib.command(['seek', (positionMs / 1000.0).toFixed(3), 'absolute']);
    result.success(null);
  }

  private addSubtitle(args: Map<string, ESObject>, result: MethodResult): void {
    const urlValue: ESObject = args.get('url');
    if (typeof urlValue !== 'string' || (urlValue as string).length === 0) {
      result.error('INVALID_ARGUMENT', 'url is required', null);
      return;
    }
    const url: string = urlValue as string;
    // ArkTS 禁止 `??`，逐个取默认值。
    let title: string = 'external';
    const titleValue: ESObject = args.get('title');
    if (typeof titleValue === 'string') {
      title = titleValue as string;
    }
    let lang: string = 'auto';
    const langValue: ESObject = args.get('lang');
    if (typeof langValue === 'string') {
      lang = langValue as string;
    }
    this.requireLib().command(['sub-add', url, 'select', title, lang]);
    result.success(null);
  }

  private setProperty(args: Map<string, ESObject>, result: MethodResult): void {
    const nameValue: ESObject = args.get('name');
    if (typeof nameValue !== 'string') {
      result.error('INVALID_ARGUMENT', 'name is required', null);
      return;
    }
    const name: string = nameValue as string;
    const value: ESObject = args.get('value');
    const lib = this.requireLib();
    if (typeof value === 'number') {
      lib.setProperty(name, value as number);
    } else if (typeof value === 'boolean') {
      lib.setProperty(name, value as boolean);
    } else if (typeof value === 'string') {
      lib.setProperty(name, value as string);
    }
    result.success(null);
  }

  private getProperty(args: Map<string, ESObject>): string | null {
    const nameValue: ESObject = args.get('name');
    if (typeof nameValue !== 'string') {
      return null;
    }
    return this.getPropertyByName(nameValue as string);
  }

  private getPropertyByName(name: string): string | null {
    const session = this.session;
    if (session === null || !session.initialized) {
      return null;
    }
    try {
      return session.lib.getPropertyString(name);
    } catch (_) {
      return null;
    }
  }

  /**
   * 主动轮询播放状态（不依赖 JSBind 事件回调）。
   *
   * 鸿蒙上 mpv 的属性/事件回调经 `libmpv.JSBind.bindFunction` 绑定到 ArkTS，
   * 该机制在部分场景（回调注册时机、线程切换）可能不生效；一旦不生效，
   * Dart 侧永远收不到 `duration`/`video-params`，播放页会无限转圈。
   *
   * 这里提供一条纯同步的兜底通道：直接读 mpv 属性并一次性返回，
   * Dart 侧按固定间隔调用即可，与事件流完全解耦。
   */
  private pollState(result: MethodResult): void {
    const session = this.session;
    if (session === null || !session.initialized) {
      result.success(null);
      return;
    }
    const lib = session.lib;
    let duration = 0.0;
    let position = 0.0;
    let cacheTime = 0.0;
    let paused = true;
    let eof = false;
    let videoParams: string | null = null;
    let trackList: string | null = null;
    let idleActive = true;
    let playlistCount = 0;
    let pausedForCache = false;
    let cachePercent = -1.0;
    let hwdecCurrent: string | null = null;
    let gpuContext: string | null = null;
    let currentVo: string | null = null;
    let mediaTitle: string | null = null;
    let pathMasked: string | null = null;
    try {
      duration = lib.getProperty('duration/full');
    } catch (_) {
    }
    try {
      position = lib.getProperty('time-pos/full');
    } catch (_) {
    }
    try {
      cacheTime = lib.getProperty('demuxer-cache-time');
    } catch (_) {
    }
    try {
      paused = lib.getPropertyBool('pause');
    } catch (_) {
    }
    try {
      eof = lib.getPropertyBool('eof-reached');
    } catch (_) {
    }
    // 不可用的属性在 wrapper 里可能返回空串而非 null——统一按 null 处理，
    // 否则 Dart 侧「视频参数=有」是误报（v1.2.75 诊断修正）。
    try {
      const v = lib.getPropertyString('video-params');
      if (v !== null && v.length > 0) {
        videoParams = v;
      }
    } catch (_) {
    }
    try {
      const t = lib.getPropertyString('track-list');
      if (t !== null && t.length > 0) {
        trackList = t;
      }
    } catch (_) {
    }
    try {
      idleActive = lib.getPropertyBool('idle-active');
    } catch (_) {
    }
    try {
      playlistCount = lib.getProperty('playlist-count');
    } catch (_) {
    }
    try {
      pausedForCache = lib.getPropertyBool('paused-for-cache');
    } catch (_) {
    }
    try {
      cachePercent = lib.getProperty('cache-buffering-state');
    } catch (_) {
    }
    // 实际生效的硬解器（hwdec-current）：验证硬解是否真的启用——
    // 请求值与实际值可能不一致（构建不识别该值/编码不支持回退）。
    try {
      const h = lib.getPropertyString('hwdec-current');
      if (h !== null && h.length > 0) {
        hwdecCurrent = h;
      }
    } catch (_) {
    }
    try {
      const g = lib.getPropertyString('gpu-context');
      if (g !== null && g.length > 0) {
        gpuContext = g;
      }
    } catch (_) {
    }
    try {
      const v = lib.getPropertyString('current-vo');
      if (v !== null && v.length > 0) {
        currentVo = v;
      }
    } catch (_) {
    }
    try {
      const t = lib.getPropertyString('media-title');
      if (t !== null && t.length > 0) {
        mediaTitle = t;
      }
    } catch (_) {
    }
    try {
      const p = lib.getPropertyString('path');
      if (p !== null && p.length > 0) {
        // 掩码：去掉 query（内含 api_key），只留尾部路径段，
        // 足以分辨「转码 m3u8 / 直接流 / 本地文件」且不泄露 token。
        const noQuery = p.split('?')[0];
        pathMasked = noQuery.length > 72
          ? noQuery.substring(noQuery.length - 72)
          : noQuery;
      }
    } catch (_) {
    }
    const payload: MpvPollPayload = {
      durationMs: Math.round(duration * 1000.0),
      positionMs: Math.round(position * 1000.0),
      bufferedMs: Math.round(cacheTime * 1000.0),
      paused: paused,
      eofReached: eof,
      videoParams: videoParams,
      trackList: trackList,
      idleActive: idleActive,
      playlistCount: playlistCount,
      pausedForCache: pausedForCache,
      cachePercent: cachePercent,
      hwdecCurrent: hwdecCurrent,
      gpuContext: gpuContext,
      currentVo: currentVo,
      mediaTitle: mediaTitle,
      pathMasked: pathMasked !== null ? pathMasked : this.lastUrlMasked,
    };
    result.success(payload);
  }

  private resizeTexture(args: Map<string, ESObject>, result: MethodResult): void {
    const session = this.requireSession();
    const width = Math.max(1, Math.trunc(this.number(args, 'width', session.width)));
    const height = Math.max(1, Math.trunc(this.number(args, 'height', session.height)));
    session.width = width;
    session.height = height;
    if (session.initialized) {
      try {
        session.lib.setProperty('ohos-surface-size', `${width}x${height}`);
      } catch (_) {
      }
    }
    // 纹理模式：同步 Flutter 纹理缓冲尺寸，让 mpv 的 EGL 窗口与
    // 纹理缓冲一致（避免比例错位/无谓缩放）。
    if (session.textureId > 0 && this.binding !== null) {
      try {
        const registry: TextureRegistry = this.binding.getTextureRegistry();
        registry.setTextureBufferSize(session.textureId, width, height);
        registry.notifyTextureResizing(session.textureId, width, height);
      } catch (_) {
      }
    }
    result.success(null);
  }

  private screenshot(result: MethodResult): void {
    const session = this.requireSession();
    // commandWithReturn 返回 MpvNode 递归联合类型；ArkTS 禁止 Map 下标访问，
    // 先收窄成 Map 再 get。失败时原生返回空对象，故需判空。
    const raw: ESObject = session.lib.commandWithReturn(['screenshot-raw', 'video', 'bgra']);
    if (!(raw instanceof Map)) {
      result.success(null);
      return;
    }
    const data: ESObject = (raw as Map<string, ESObject>).get('data');
    if (data === undefined || data === null) {
      result.success(null);
      return;
    }
    result.success(data);
  }

  // ── 工具 ─────────────────────────────────────────────────────

  private requireSession(): MpvSession {
    const session = this.session;
    if (session === null) {
      throw new Error('mpv session is not created');
    }
    return session;
  }

  private requireLib(): MpvLib {
    const session = this.requireSession();
    if (!session.initialized) {
      throw new Error('mpv session is not initialized');
    }
    return session.lib;
  }

  private number(args: Map<string, ESObject>, name: string, fallback: number): number {
    const value: ESObject = args.get(name);
    if (typeof value === 'number') {
      return value as number;
    }
    return fallback;
  }
}
