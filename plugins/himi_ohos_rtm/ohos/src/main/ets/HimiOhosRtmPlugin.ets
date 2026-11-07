/**
 * 鸿蒙 RTM 插件入口：MethodChannel + EventChannel → RtmManager。
 *
 * 协议与 `himi_windows_rtm` 对齐（同名方法 / 同结构返回），差异仅在实现
 * 手段——鸿蒙 SDK 全 Promise，可直接 await 后回传，无需 requestId 关联。
 */
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  EventChannel,
  EventSink,
} from '@ohos/flutter_ohos';
import hilog from '@ohos.hilog';
import { RtmManager } from './RtmManager';

const DOMAIN: number = 0x0001;
const TAG: string = 'HimiOhosRtmPlugin';

export default class HimiOhosRtmPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  private manager: RtmManager = new RtmManager();

  getUniqueClassName(): string {
    return 'HimiOhosRtmPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'himi_ohos_rtm');
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(
      binding.getBinaryMessenger(), 'himi_ohos_rtm/events');
    this.eventChannel.setStreamHandler({
      onListen: (args: Object, sink: EventSink): void => {
        this.eventSink = sink;
        this._attachSink();
      },
      onCancel: (args: Object): void => {
        // 635：只清 eventSink，不主动清 manager.sink——
        // Dart 侧重新 listen 时 onListen 会立刻重挂，避免中间窗口丢事件。
        this.eventSink = null;
      },
    });
    hilog.info(DOMAIN, TAG, '插件已注册');
  }

  /// 635：把事件出口挂到 manager。
  ///
  /// 必须由 `onListen` **和** `initialize` 都调用：
  /// - `onListen`：Dart 侧首次/重新订阅 EventChannel 时挂载；
  /// - `initialize`：`RtmManager.initialize()` 内部会先调 `release()`
  ///   重建 client，重建后需要确保出口仍在（防御性兜底）。
  private _attachSink(): void {
    this.manager.setEventSink((event: Map<string, Object>): void => {
      if (this.eventSink !== null) {
        this.eventSink.success(event);
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.manager.release();
    // 635：引擎真正销毁时才清空事件出口。
    this.manager.setEventSink(null);
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = null;
    this.eventSink = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handle(call, result).catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, '%{public}s 失败: %{public}s', call.method, String(e));
      result.error('rtm_error', String(e), null);
    });
  }

  /** Dart 侧传 Map<String,String> → ArkTS Map（跨平台编解码后可能是普通对象）。 */
  private toStrMap(raw: Object): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    if (raw instanceof Map) {
      const m = raw as Map<string, string>;
      const keys: string[] = Array.from(m.keys());
      for (const k of keys) {
        out.set(k, `${m.get(k) ?? ''}`);
      }
      return out;
    }
    const obj = raw as Record<string, Object>;
    const ks: string[] = Object.keys(obj);
    for (const k of ks) {
      out.set(k, `${obj[k]}`);
    }
    return out;
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case 'initialize': {
        const appId: string = (call.argument('appId') as string) ?? '';
        const userId: string = (call.argument('userId') as string) ?? '';
        this.manager.initialize(appId, userId);
        // 635：`initialize` 内部若已有实例会先 `release()` 重建 client，
        // 这里确保事件出口仍然挂上（防止 sink 被意外清空后无人恢复）。
        this._attachSink();
        result.success(true);
        return;
      }
      case 'login': {
        const token: string = (call.argument('token') as string) ?? '';
        await this.manager.login(token);
        result.success(true);
        return;
      }
      case 'logout':
        await this.manager.logout();
        result.success(null);
        return;
      case 'subscribe': {
        const channel: string = (call.argument('channel') as string) ?? '';
        await this.manager.subscribe(channel);
        result.success(true);
        return;
      }
      case 'unsubscribe': {
        const channel: string = (call.argument('channel') as string) ?? '';
        await this.manager.unsubscribe(channel);
        result.success(null);
        return;
      }
      case 'publish': {
        const channel: string = (call.argument('channel') as string) ?? '';
        const message: string = (call.argument('message') as string) ?? '';
        await this.manager.publish(channel, message);
        result.success(true);
        return;
      }
      case 'getOnlineUsers': {
        const channel: string = (call.argument('channel') as string) ?? '';
        const data = await this.manager.getOnlineUsers(channel);
        // Dart 侧 `_invoke` 约定：Map 结果要自带 `ok`，否则会被当成失败
        // （`r['ok'] != true`）。这里统一包成 {ok, value}。
        const out: Map<string, Object> = new Map<string, Object>();
        out.set('ok', true);
        out.set('value', data);
        result.success(out);
        return;
      }
      case 'setChannelMetadata': {
        const channel: string = (call.argument('channel') as string) ?? '';
        const raw: Object | null = call.argument('metadata');
        const metadata: Map<string, string> = raw !== null
          ? this.toStrMap(raw)
          : new Map<string, string>();
        const rev = await this.manager.setChannelMetadata(channel, metadata);
        const out: Map<string, Object> = new Map<string, Object>();
        out.set('ok', true);
        out.set('value', rev);
        result.success(out);
        return;
      }
      case 'getChannelMetadata': {
        const channel: string = (call.argument('channel') as string) ?? '';
        const data = await this.manager.getChannelMetadata(channel);
        // 同 getOnlineUsers：必须带 `ok`，否则 Dart 侧一律当失败。
        const out: Map<string, Object> = new Map<string, Object>();
        out.set('ok', true);
        out.set('metadata', data.get('metadata') ?? new Map<string, string>());
        out.set('updatedAt', data.get('updatedAt') ?? '');
        result.success(out);
        return;
      }
      case 'release':
        this.manager.release();
        result.success(null);
        return;
      default:
        result.notImplemented();
        return;
    }
  }
}
