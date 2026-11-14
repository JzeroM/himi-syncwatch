import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'surface_rebind_policy.dart';

export 'himi_mpv_android_surface_view.dart';
export 'surface_rebind_policy.dart';

/// Android MPV 会话：SurfaceView 由原生插件提供，libmpv 由 media_kit 驱动。
///
/// 与鸿蒙共用 [MpvSession] 契约；渲染目标通过 `wid` 指向 SurfaceView 的
/// Java Surface 全局引用，Flutter 只保留透明覆盖层。
class HimiMpvAndroidSession implements MpvSession {
  HimiMpvAndroidSession._({
    required this.width,
    required this.height,
    required this.hwdecMode,
    required this.nativeSurface,
    required this.nativeUi,
    required this.hdr,
    required this.hlg,
    this.dv = false,
    required String vo,
  }) : _voOverride = vo;

  static const MethodChannel _methods = MethodChannel('himi_mpv_android');
  static const EventChannel _surfaceEvents =
      EventChannel('himi_mpv_android/surface');

  final int width;
  final int height;
  final String hwdecMode;
  final bool nativeSurface;

  /// 是否启用全屏原生播放器 UI（Dialog + SurfaceView）。
  final bool nativeUi;
  final bool hdr;
  final bool hlg;

  /// 697：杜比视界内容。
  ///
  /// DV 动态元数据需要 `bt.2390` + `hybrid` 色调映射（`clip` 会丢高光）。
  /// 仅在 `gpu-next` + Vulkan 后端下 libplacebo 才能处理 DV 元数据。
  final bool dv;

  final StreamController<Map<Object?, Object?>> _events =
      StreamController<Map<Object?, Object?>>.broadcast();
  static const SurfaceRebindPolicy _policy = SurfaceRebindPolicy();
  StreamSubscription<dynamic>? _surfaceSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<PlayerLog>? _logSub;

  Player? _player;
  VideoController? _controller;
  VoidCallback? _textureIdListener;
  int _surfaceHandle = 0;
  int _textureId = 0;
  bool _disposed = false;

  /// 655：**已移除 surface→texture 自动回退**。
  ///
  /// 640 曾在这里实现「检测到 EGL 失败就自动切纹理并持久化」。删除原因：
  ///
  /// 1. **判据太宽，正常设备会误判**。`could not create` / `failed to create`
  ///    没有限定在 `[vo/gpu*]` 前缀下，mpv 的 info 日志里任何一行命中就
  ///    触发（音频设备、字幕字体、某个解码 profile 都会打这两个短语）；
  ///    `vo-configured` 连续 5s 非 yes 同样会误伤慢源（网络转码、4K HEVC
  ///    初始化、片头黑场）。
  /// 2. **误判被持久化后无法自愈**。`_onSurfaceRenderFailed()` 调
  ///    `notifier.update(mpvVideoOutput: texture)`，而 `settings_provider`
  ///    把任何 `mpvVideoOutput != null` 的写入都标成 `userSet = true`——
  ///    这与 640 注释里「userSet 保持 false」的意图相反。`userSet = true`
  ///    是最高优先级，`effectiveVideoOutput` 会完全跳过平台默认值，于是
  ///    **一次误判 = 该设备永久锁定纹理，重启也不恢复**。
  ///
  /// 现在改为**纯手动**：视频路径只由设置页决定（`mpvVideoOutput` +
  /// `userSet`）。渲染失败不再自动改写设置，只在日志里留诊断信息，
  /// 由用户自行在「设置 → 播放内核 → MPV 视频输出」切换。
  ///
  /// 真机（Mali-450 / H96 Max RK3528）仍可正常使用——只是需要用户手动
  /// 选一次「纹理」，而不是程序替用户做永久决定。

  /// surface 实测宽/高（像素）。由 `surfaceChanged` 事件喂入，用于给 mpv
  /// 设 `android-surface-size`。
  ///
  /// 【竖屏画布根因】mpv 的 android 后端只认这个选项决定合成画布大小。
  /// 不设时它用**初始** surface 尺寸（横屏 2400×1080）恒定合成，旋转到
  /// 竖屏后 ANativeWindow 变成 1080×2400，帧被拉伸成 864×2400 + 左右黑边
  /// （真机截图实测 862/108 与数学推导吻合）。鸿蒙侧有 `ohos-surface-size`
  /// 所以没这个问题。
  int _surfaceWidth = 0;
  int _surfaceHeight = 0;
  /// 已应用到 mpv 的 surface 尺寸（避免同尺寸重复 setProperty）。
  int _appliedSurfaceWidth = 0;
  int _appliedSurfaceHeight = 0;

  /// 踢纹理循环的代际计数：每轮 `_kickTextureSurface` 启动时 `++` 取快照，
  /// detach/dispose 时再 `++` 让旧循环的快照失效立即退出。用计数而非布尔，
  /// 避免「同会话重启踢循环把上一轮孤儿循环重新激活」（真机日志曾见孤儿
  /// 循环空跑到 #160）。见 [_kickTextureSurface]。
  int _kickGeneration = 0;
  /// 原生播放器 UI 是否接管中（adapter 在 open 前/关闭后同步）。
  /// 决定 surface 事件来源过滤：接管中只认 `src=native`。
  bool _nativeUiActive = false;
  int _positionMs = 0;
  int _durationMs = 0;
  int _bufferedMs = 0;
  bool _paused = true;
  bool _eof = false;

  String? _pendingUrl;
  Map<String, String> _pendingHeaders = const {};
  int _pendingStartMs = 0;
  bool _pendingPause = false;
  double? _pendingVolume;
  double? _pendingSpeed;
  final Map<String, String> _pendingProperties = <String, String>{};

  /// 最近一次成功发起播放的地址（Surface 重建后据此恢复，见 [_detachPlayer]）。
  String? _lastUrl;
  Map<String, String> _lastHeaders = const {};

  static Future<HimiMpvAndroidSession> create({
    int width = 1920,
    int height = 1080,
    String hwdecMode = 'performance',
    bool nativeSurface = true,
    bool nativeUi = false,
    bool hdr = false,
    bool hlg = false,
    /// 697：杜比视界内容（决定 tone-mapping 策略）。
    bool dv = false,
    /// 655：渲染器由设置决定（'gpu-next' / 'gpu'）；纹理路径恒为 'gpu'。
    String vo = 'gpu-next',
  }) async {
    final session = HimiMpvAndroidSession._(
      width: width,
      height: height,
      hwdecMode: hwdecMode,
      nativeSurface: nativeSurface,
      nativeUi: nativeUi,
      hdr: hdr,
      hlg: hlg,
      dv: dv,
      vo: vo,
    );
    await session._start();
    return session;
  }

  /// 697：设备 Vulkan 是否可用（`_start` 时由 [isVulkanAvailable] 探测）。
  ///
  /// 决定 `gpu-api` / `gpu-context` 是否带上 Vulkan 优先项。
  static bool _vulkanOk = false;

  /// 697：Vulkan 渲染已被判定失败 → 本次 app 运行内一律走 opengl。
  ///
  /// 由适配器的「软解仍无画面」看门狗置位（Vulkan 上下文能初始化但渲染
  /// 不出帧的情况不触发 mpv 自己的上下文回退）。置位后新会话直接只用
  /// opengl，避免每次起播都黑 3 秒再回退。
  static bool _forceOpenGl = false;

  /// 标记 Vulkan 渲染不可用（幂等）。
  static void disableVulkanRendering() => _forceOpenGl = true;

  /// 697：当前是否打算走 Vulkan 渲染。
  ///
  /// 适配器据此把 `hwdec` 切成 copy-back（`mediacodec-copy`）——Vulkan
  /// 没有 MediaCodec 的直通互操作，HW+（直写 Surface）会「有声音没画面」。
  static bool get vulkanRenderingPreferred => _vulkanOk && !_forceOpenGl;

  /// 697：检测 Vulkan 是否可用（libplacebo DV 处理需要 compute shader）。
  ///
  /// 结果缓存在 [_vulkanAvailable]，只需检测一次。
  static bool? _vulkanAvailable;

  static Future<bool> isVulkanAvailable() async {
    if (_vulkanAvailable != null) return _vulkanAvailable!;
    try {
      final result = await _methods.invokeMethod<bool>('isVulkanAvailable');
      _vulkanAvailable = result ?? false;
    } catch (_) {
      _vulkanAvailable = false;
    }
    return _vulkanAvailable!;
  }

  static Future<MpvHdrCapabilities> queryHdrCapabilities() async {
    try {
      final raw = await _methods.invokeMapMethod<String, Object?>(
        'queryHdrCapabilities',
      );
      final formats = (raw?['formats'] as List<Object?>?) ?? const [];
      return MpvHdrCapabilities(
        hdr10: formats.contains('hdr10'),
        hlg: formats.contains('hlg'),
        displayHdr: formats.isNotEmpty,
      );
    } catch (e) {
      return MpvHdrCapabilities(error: '$e');
    }
  }

  /// 655：**已删除 GLES 版本探测**，`vo` 改为由设置决定（手动选择）。
  ///
  /// 旧的 `_probeGlSupport()` 用 `queryGlEsVersion` 查驱动声明的版本号，
  /// 再按 `major > 3 || (major == 3 && minor >= 1)` 决定 `gpu-next`/`gpu`。
  /// 删除原因：
  ///
  /// 1. **版本号不能预测可用性**。`vo=gpu-next` 能否跑起来取决于驱动实现
  ///    质量、扩展集、带宽等版本号无法反映的因素。640 提交说明自己也承认
  ///    「驱动可能虚报版本」——Mali-450 报告 GLES 3.1/3.2，但 mpv 自建
  ///    上下文仍然失败。
  /// 2. **探测路径与实际渲染路径不同**。探测用 1×1 pbuffer（EGL 配置里
  ///    最宽松的一种），mpv 实际用 ANativeWindow + 可能的 10bit 配置。
  ///    pbuffer 成功不代表真实路径成功。
  /// 3. **`eglTerminate` 有破坏进程 EGL 状态的风险**。探测用的
  ///    `EGL_DEFAULT_DISPLAY` 是进程级共享的（Flutter 引擎可能正在用），
  ///    在上面 terminate 不安全。
  ///
  /// 现在：`vo` 由 `AppSettings.mpvRenderer` 决定，经
  /// `MpvSessionPlatform.create(vo:)` 传入本类构造函数。
  final String _voOverride;

  /// 测试注入点：读取本会话实际使用的 `vo`。
  @visibleForTesting
  String get debugVo => _voOverride;

  @override
  int get textureId => _textureId;

  @override
  bool get usesNativeSurface => nativeSurface;

  /// HDR 实际状态本平台暂未单独上报，由适配器按输出策略推断。
  @override
  bool? get hdrOutputActive => null;

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  /// 诊断日志出口（adapter 注入 LogService；未注入时走 debugPrint）。
  static void Function(String message)? debugLog;

  static void _log(String message) {
    final sink = debugLog;
    if (sink != null) {
      sink(message);
    } else {
      debugPrint('[HimiMpvAndroid] $message');
    }
  }

  @override
  void setNativeUiActive(bool active) {
    if (_nativeUiActive == active) return;
    _nativeUiActive = active;
    _log('nativeUiActive=$active（surface 来源过滤切换）');
  }

  /// 主动重同步 surface：事件通道可能丢事件（宿主销毁不发回调 / 事件早于
  /// 监听），按 `getCurrentSurface` 轮询兜底。
  @override
  Future<void> refreshSurface() async {
    if (_disposed || !nativeSurface) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      if (_disposed) return;
      try {
        final current = await _methods.invokeMapMethod<String, dynamic>(
          'getCurrentSurface',
        );
        final handle = current?['handle'];
        final src = current?['src'] as String?;
        if (handle is int && handle > 0) {
          if (!_policy.accept(
              nativeUiActive: _nativeUiActive, eventSrc: src)) {
            // 当前来源还没有 surface（原生宿主窗口尚未完成创建）。
            _log('refreshSurface #$attempt: 跳过 src=$src '
                'handle=$handle（nativeUiActive=$_nativeUiActive）');
          } else if (handle != _surfaceHandle) {
            _log('refreshSurface #$attempt: 重同步 handle=$handle '
                '（原 $_surfaceHandle, src=$src）');
            _surfaceHandle = handle;
            unawaited(_player == null
                ? _ensurePlayer()
                : _rebindToSurface());
            return;
          } else {
            _log('refreshSurface #$attempt: 已同步 handle=$handle');
            if (_player == null) {
              unawaited(_ensurePlayer());
            }
            return;
          }
        }
      } catch (e) {
        _log('refreshSurface #$attempt 失败: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _log('refreshSurface 超时：原生宿主未报出当前来源的 surface');
  }

  Future<void> _start() async {
    // 697：Vulkan 可用性检测（DV 的 libplacebo compute 需要它）。
    //
    // 【真机回归：黑屏有声 → 已定位】mpv 的 Vulkan Android 上下文名是
    // **`androidvk`**，而 GL 的才叫 `android`。此前 `gpu-api=vulkan` +
    // `gpu-context=android` 拿 GL 上下文配 Vulkan API → 必然报
    // 「Failed initializing any suitable GPU context!」→ vo 起不来。
    _vulkanOk = await isVulkanAvailable();
    // 655：不再探测 GLES 版本（见 _voOverride 注释）。`vo` 由设置决定。
    if (!nativeSurface) {
      await _ensurePlayer();
      return;
    }
    _surfaceSub = _surfaceEvents.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      final type = raw['type'];
      final handle = raw['handle'];
      final handleInt = handle is int ? handle : 0;
      final src = raw['src'] as String?;
      // 来源过滤：原生 UI 接管中只认 native，未接管只认 platform。
      // 垂死平台视图的 surfaceChanged 会把绑定抢回即将销毁的 handle，
      // 过滤掉就不会再搁浅（v1.5.4 安卓黑屏根因）。
      if (!_policy.accept(nativeUiActive: _nativeUiActive, eventSrc: src)) {
        _log('忽略过期来源事件: $type src=$src handle=$handleInt '
            '（nativeUiActive=$_nativeUiActive）');
        return;
      }
      if (type == 'surface') {
        final action = _policy.plan(
          currentHandle: _surfaceHandle,
          newHandle: handleInt,
          playerAlive: _player != null,
        );
        _log('surface 事件: src=$src handle=$handleInt current=$_surfaceHandle '
            'playerAlive=${_player != null} → ${action.name}');
        // 同一 surface 的尺寸变化（旋转/折叠展开）也要同步给 mpv：mpv 的
        // android 后端只认 android-surface-size，不更新就一直用初始尺寸
        // 合成 → 竖屏被拉伸。放在这里统一处理（不同 handle 的首帧同样走）。
        _noteSurfaceSize(raw);
        switch (action) {
          case SurfaceAction.ensurePlayer:
            _surfaceHandle = handleInt;
            unawaited(_ensurePlayer());
          case SurfaceAction.rebind:
            // surface 变化（原生 UI Dialog 抢占 / 旋转重建）：旧播放器绑在
            // 已销毁的 surface 上，必须重建到新 handle（计划书 §6.3）。
            _surfaceHandle = handleInt;
            unawaited(_rebindToSurface());
          case SurfaceAction.none:
          case SurfaceAction.detach:
            break;
        }
        // 重建/新建路径会在 _ensurePlayer 里带入尺寸；此处只补「同 handle
        // 仅尺寸变化」的增量更新（rebind 会重建，无需重复 set）。
        if (action == SurfaceAction.none && _player != null) {
          unawaited(_syncAndroidSurfaceSize());
        }
      } else if (type == 'surfaceDestroyed') {
        final action = _policy.onDestroyed(
          currentHandle: _surfaceHandle,
          destroyedHandle: handleInt,
          playerAlive: _player != null,
        );
        _log('surfaceDestroyed: src=$src handle=$handleInt '
            'current=$_surfaceHandle → ${action.name}');
        // 只处理当前绑定 surface 的销毁：原生 UI（Dialog）与 Flutter 平台
        // 视图各有自己的 SurfaceView，旧宿主销毁不能拆掉新 surface 的绑定
        // （否则表现为「解码正常但黑屏」）。
        if (action == SurfaceAction.detach) {
          _surfaceHandle = 0;
          unawaited(_detachPlayer());
        }
      }
    });
    try {
      final current = await _methods.invokeMapMethod<String, dynamic>(
        'getCurrentSurface',
      );
      final handle = current?['handle'];
      if (handle is int && handle > 0) {
        _surfaceHandle = handle;
        if (current != null) _noteSurfaceSize(current);
        _log('初始 surface: handle=$handle src=${current?['src']} '
            'size=${_surfaceWidth}x$_surfaceHeight');
        await _ensurePlayer();
      }
    } catch (_) {}
  }

  /// 记录 surface 事件带来的实测尺寸（无效值忽略，保留上一次）。
  void _noteSurfaceSize(Map<dynamic, dynamic> raw) {
    final w = raw['width'];
    final h = raw['height'];
    final wi = w is int ? w : (w is num ? w.toInt() : 0);
    final hi = h is int ? h : (h is num ? h.toInt() : 0);
    if (wi <= 0 || hi <= 0) return;
    _surfaceWidth = wi;
    _surfaceHeight = hi;
  }

  /// 把当前 surface 尺寸同步给 mpv（`android-surface-size`）。
  ///
  /// mpv 的 android 后端用该选项决定**合成画布**大小；不随 surface 更新
  /// 就一直按初始尺寸合成，旋转后被 ANativeWindow 拉伸（竖屏画布根因）。
  /// 等价 media_kit `AndroidVideoController.widListener` 的处理，但**不需要
  /// 重建 vo**：`android-surface-size` 是运行期可改属性，mpv 内部会重建
  /// 窗口并重设 vo 输出尺寸（mpv 官方 android 示例即在 onSizeChanged 里
  /// 直接 setProperty）。
  Future<void> _syncAndroidSurfaceSize() async {
    if (!nativeSurface || _disposed) return;
    final w = _surfaceWidth;
    final h = _surfaceHeight;
    if (w <= 0 || h <= 0) return;
    if (w == _appliedSurfaceWidth && h == _appliedSurfaceHeight) return;
    _appliedSurfaceWidth = w;
    _appliedSurfaceHeight = h;
    _log('同步 android-surface-size: ${w}x$h');
    try {
      await (_player?.platform as dynamic)
          ?.setProperty
          ?.call('android-surface-size', '${w}x$h');
    } catch (e) {
      _log('同步 android-surface-size 失败: $e');
    }
  }

  Future<void> _detachPlayer() async {
    if (_disposed) return;
    _kickGeneration++; // 作废孤儿踢循环（换绑/重建时旧 controller 已无意义）
    final player = _player;
    _log('detachPlayer: handle=$_surfaceHandle');
    _player = null;
    // 重建后必须重新应用尺寸：置零让下次 _syncAndroidSurfaceSize 视为未应用。
    _appliedSurfaceWidth = 0;
    _appliedSurfaceHeight = 0;
    // Surface 重建（旋转 / 原生 UI 宿主重建）：记住当前播放点，等新
    // surface 到达后由 _ensurePlayer 用同一地址 + 当前位置重建，避免黑屏
    // 或从头播（计划书 §6.3「Surface handle 顺序与重建」）。
    final lastUrl = _lastUrl;
    if (lastUrl != null && lastUrl.isNotEmpty) {
      _pendingUrl = lastUrl;
      _pendingHeaders = _lastHeaders;
      _pendingStartMs = _positionMs > 0 ? _positionMs : _pendingStartMs;
      _pendingPause = _paused || _eof;
    }
    try {
      await player?.dispose();
    } catch (_) {}
  }

  /// 换绑到新 surface：销毁绑在旧 surface 上的播放器，用同一地址 + 当前
  /// 播放点在新 handle 上重建（见 [_detachPlayer] 的恢复逻辑）。
  Future<void> _rebindToSurface() async {
    if (_disposed) return;
    await _detachPlayer();
    if (_disposed || _surfaceHandle == 0) return;
    await _ensurePlayer();
  }

  /// media_kit_video 原生 channel（与 AndroidVideoController 同一通道）。
  static const MethodChannel _videoOutChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  /// 轮询踢纹理注册：调 `VideoOutputManager.SetSurfaceSize` 强制 native
  /// `onSurfaceAvailable()` → `VideoOutput.Resize` → `controller.id/wid`。
  /// 打破「vo=null 不产 video-params → 不 SetSurfaceSize → Resize 不触发 →
  /// wid 上不来 → vo 永远 null」的死锁。
  ///
  /// 轮询（而非踢一次）：`VideoController.create()`（含 native
  /// `VideoOutputManager.Create`）是 async 且未 await，首次踢时 native 的
  /// VideoOutput 可能还没建 → SetSurfaceSize 查不到 handle → no-op。每
  /// 300ms 重踢一次，直到 id 出现或 [controller] 注销（由 20s 超时兜底）。
  Future<void> _kickTextureSurface(
    Player player,
    VideoController controller,
  ) async {
    // 代际快照：detach/dispose 会 _kickGeneration++，让本代循环立即退出。
    // 用计数而非布尔，避免「同一会话重启踢循环时把孤儿循环重新激活」——
    // 新循环递增计数后只认自己的代际，旧循环的快照已过期。
    final gen = ++_kickGeneration;
    final handle = await player.handle;
    var attempt = 0;
    while (gen == _kickGeneration &&
        !_disposed &&
        (controller.id.value == null || controller.id.value! <= 0)) {
      attempt++;
      try {
        await _videoOutChannel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
          'handle': '$handle',
          'width': '$width',
          'height': '$height',
        });
        if (attempt <= 3 || attempt % 10 == 0) {
          _log('踢纹理注册 #$attempt: SetSurfaceSize handle=$handle '
              '${width}x$height（id=${controller.id.value}）');
        }
      } catch (e) {
        _log('踢纹理注册 #$attempt 失败: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (controller.id.value != null && controller.id.value! > 0) {
      _log('纹理注册成功（踢 #$attempt 次后 id=${controller.id.value}）');
    }
  }

  Future<void> _ensurePlayer() async {
    if (_disposed || _player != null) return;
    // 655：视频路径完全由设置决定（`nativeSurface`），不再有自动回退。
    final effectiveSurface = nativeSurface;
    if (effectiveSurface && _surfaceHandle == 0) return;
    _log('创建播放器: wid=$_surfaceHandle hwdec=$hwdecMode '
        'surface=$effectiveSurface');
    // 655：渲染器由设置决定（`_voOverride`），不再按 GLES 版本探测。
    // 纹理路径必须 gpu（见下方 PlayerConfiguration 注释）。
    final useGpuNext = effectiveSurface && _voOverride == 'gpu-next';
    // 655：弱 GPU 的音画同步补偿改为跟随手动选择——用户选 `gpu` 说明
    // 设备渲染能力有限，此时启用丢帧追赶 + 限制解码线程。
    final lowEndGpu = nativeSurface && _voOverride == 'gpu';
    final options = <String, String>{
      if (effectiveSurface) 'vo': useGpuNext ? 'gpu-next' : 'gpu',
      'vid': 'auto',
      'aid': 'auto',
      // force-window 仅 surface 模式设 no（显式 wid 已给窗口）；纹理模式
      // 由 AndroidVideoController 后置设 yes，此处若设 no 会与其冲突。
      if (effectiveSurface) 'force-window': 'no',
      if (effectiveSurface) 'wid': '$_surfaceHandle',
      // 合成画布尺寸：必须与 surface 实测一致，否则 mpv 按默认尺寸合成后
      // 被 ANativeWindow 拉伸（竖屏画布根因）。初始未知时不写，等
      // surfaceChanged 补。
      if (effectiveSurface && _surfaceWidth > 0 && _surfaceHeight > 0)
        'android-surface-size': '${_surfaceWidth}x$_surfaceHeight',
      // 697：优先 Vulkan（libplacebo 的 DV compute 需要它），失败自动回退。
      //
      // 【关键】mpv 的上下文名按 API 区分：
      //   OpenGL → `android`
      //   Vulkan → `androidvk`
      // 两个选项都支持逗号分隔的优先级列表：mpv 依次尝试，第一个能初始化
      // 的生效。Vulkan 初始化失败（驱动/设备不支持）会自动落到 OpenGL，
      // 不会出现「vo 起不来 → 黑屏有声」。
      if (effectiveSurface)
        'gpu-api': (_vulkanOk && !_forceOpenGl) ? 'vulkan,opengl' : 'opengl',
      if (effectiveSurface)
        'gpu-context':
            (_vulkanOk && !_forceOpenGl) ? 'androidvk,android' : 'android',
      // 纹理模式（!nativeSurface）必须 copy-back 硬解：渲染纹理没有真实
      // Surface 给 MediaCodec 直写，`auto` 会先试零拷贝 → "Both surface and
      // native_window are NULL" → 首帧解码失败 → 上层弹「播放失败」。
      // copy-back 解到系统内存再上传 GPU。Surface 模式保留 auto（可直写）。
      // 【697 真机回归：改成 mediacodec 后黑屏有声】
      // 显式 `mediacodec`（非 copy）要求硬解直写 Surface；部分设备/驱动
      // 直写失败时不回退，表现为「有声无画」。`auto-copy` 是 copy-back
      // 路径（解码到系统内存再上传 GPU），兼容性最好。
      //
      // 恢复 `auto`：`hwdec-software-fallback=yes` 保证硬解不可用时
      // 自动退软解。Vulkan 硬解后端虽在候选里，但 mpv 只在 Vulkan 上下文
      // 初始化成功后才用它；Android 的 gpu-api 默认 opengl，不会选中。
      // 697：Vulkan 渲染时**必须**走 copy-back。MediaCodec 直通（HW+，
      // 即 `mediacodec`）输出的是 ANativeWindow Surface，Vulkan 没有对应
      // 的导入互操作 → 解码正常但画面出不来（有声无画）。
      // 列表语义：依次尝试，mpv 对 Vulkan RA 会跳过不可用的直通档。
      'hwdec': !effectiveSurface
          ? 'auto-copy'
          : (hwdecMode == 'software'
              ? 'no'
              : (vulkanRenderingPreferred
                  ? 'mediacodec,mediacodec-copy,no'
                  : 'auto')),
      'hwdec-software-fallback': 'yes',
      'cache': 'yes',
      'demuxer-max-bytes': '${256 * 1024 * 1024}',
      'demuxer-max-back-bytes': '${128 * 1024 * 1024}',
      'sub-ass': 'yes',
      'sub-visibility': 'yes',
      'osd-level': '0',
      'osc': 'no',
      // HDR 直出：mpv 官方手册明确 `--target-colorspace-hint` 仅
      // `--vo=gpu-next` 支持，故老 GPU 降级时不能走这条。
      if (hdr && effectiveSurface && useGpuNext) ...<String, String>{
        'target-colorspace-hint': 'yes',
        'target-prim': 'bt.2020',
        'target-trc': hlg ? 'hlg' : 'pq',
        'hdr-compute-peak': 'auto',
        // 697：DV 用感知映射（bt.2390 + hybrid），普通 HDR10 保持 clip。
        // DV 是动态元数据，clip 按单一峰值硬裁切会丢高光、暗部发灰。
        'tone-mapping': dv ? 'bt.2390' : 'clip',
        if (dv) 'tone-mapping-mode': 'hybrid',
      },
      // 639：老 GPU 无法 HDR 直出 → 对 HDR 内容做 SDR tone mapping，
      // 避免直接输出导致过曝/发灰。
      if (hdr && effectiveSurface && !useGpuNext) ...<String, String>{
        'tone-mapping': 'spline',
        'target-prim': 'bt.709',
        'target-trc': 'srgb',
        'hdr-compute-peak': 'auto',
      },
      // 640：弱 GPU（TV 盒子）copy-back 渲染落后音频时钟 → 音画不同步。
      // 允许渲染丢帧追赶（不阻塞音频），并限制解码线程减少 CPU 争抢。
      if (lowEndGpu) ...<String, String>{
        'framedrop': 'vo',
        'audio-buffer': '0.2',
        'vd-lavc-threads': '2',
      },
    };
    final player = Player(
      configuration: PlayerConfiguration(
        // Android 纹理模式必须 vo=gpu（media_kit AndroidVideoController 走
        // TextureRegistry Surface + wid + vo=gpu，非 libmpv 渲染 API）。
        // 传 libmpv 会让 native VideoOutputManager 的 VideoOutput.Resize
        // 事件永不触发 → texture id 恒 null → _waitForTextureId 10s 超时。
        vo: effectiveSurface ? (useGpuNext ? 'gpu-next' : 'gpu') : 'gpu',
        wid: effectiveSurface ? _surfaceHandle : null,
        options: options,
        libass: true,
        logLevel: MPVLogLevel.info,
        // 618：走**同步 FFI**（与 MDK `setActiveTracks` 同语义）——属性写入
        // 与命令不再 `await` 异步回调，切轨观感接近 MDK（旧行为是
        // `mpv_set_property_async` + `await completer.future`，每次切轨要
        // 等 mpv 处理完才返回）。media_kit 默认 `true` 是为 macOS 初始化期
        // AppKit 重入；Android 无此约束。
        async: false,
      ),
    );
    _player = player;
    // 日志订阅必须在纹理等待之前：纹理路径若卡住/超时，也应有 mpv 日志
    // 可查（曾因订阅在等待之后，纹理失败时全程零 mpv 日志 → 盲调）。
    _wire(player);
    if (!effectiveSurface) {
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          // 与上一致：Android 纹理走 gpu（wid），不走 libmpv。
          vo: 'gpu',
          hwdec: 'auto-copy',
          width: width,
          height: height,
        ),
      );
      _controller = controller;
      void updateTextureId() {
        final id = controller.id.value;
        // Resize 到达（id 首次非空）必须进 LogService：它是纹理注册成功
        // 的唯一标志，也是死锁是否解除的判决值（debugPrint 不进导出）。
        _log('纹理 id 变化: id=$id');
        if (id != null && id > 0 && id != _textureId) {
          _textureId = id;
          _emit('texture-id', id);
        }
      }

      _textureIdListener = updateTextureId;
      controller.id.addListener(updateTextureId);
      // 主动踢：native onSurfaceAvailable（→VideoOutput.Resize→id/wid）原
      // 依赖 videoParams→SetSurfaceSize，而 vo=null 时 mpv 可能不产出
      // video-params → 死锁（id 恒 null、wid=0、vo 永远上不来）。这里在
      // 注册后直接 SetSurfaceSize 强制 surface 就绪，打破对 videoParams
      // 的时序依赖。
      unawaited(_kickTextureSurface(player, controller));
      // 640：**不阻塞**——纹理在后台等，拿到即 emit。
      //
      // 真机回归「加载好久后失败，重试才正常」（手机与 TV 都复现）：
      // 旧实现在**打开媒体之前**就 `await _waitForTextureId`（最长 20s），
      // 而纹理注册依赖 `VideoOutput.Resize` → 需要 mpv 已有视频输出 →
      // 需要媒体已打开。形成时序死锁：慢设备上必然超时 → 抛异常 →
      // 上层「播放失败」→ 重试时媒体已开、纹理就绪 → 正常。
      //
      // 改为先开媒体（下方 `_openNow`），纹理在后台等，不阻塞播放启动。
      unawaited(_awaitTextureInBackground(controller));
    }
    try {
      await (player.platform as dynamic)?.setProperty?.call('vid', 'auto');
      for (final entry in _pendingProperties.entries) {
        await (player.platform as dynamic)
            ?.setProperty
            ?.call(entry.key, entry.value);
      }
      _pendingProperties.clear();
      if (_pendingVolume != null) await player.setVolume(_pendingVolume!);
      if (_pendingSpeed != null) await player.setRate(_pendingSpeed!);
    } catch (_) {}
    final pending = _pendingUrl;
    if (pending != null && pending.isNotEmpty) {
      _pendingUrl = null;
      await _openNow(pending);
    }
  }

  /// 640：后台等待纹理 id（不阻塞播放启动）。
  ///
  /// 拿到即 `_emit('texture-id')`；超时只记日志，**不抛异常**——上层
  /// 不应因纹理慢而判「播放失败」。注册成功后 listener 仍会补发。
  Future<void> _awaitTextureInBackground(VideoController controller) async {
    try {
      final id = await _waitForTextureId(controller);
      if (_disposed) return;
      if (_textureId != id) {
        _textureId = id;
        _emit('texture-id', id);
      }
      _log('纹理就绪（后台）id=$id');
    } catch (e) {
      _log('纹理后台等待超时/异常: $e（当前 id=${controller.id.value}）');
    }
  }

  Future<int> _waitForTextureId(VideoController controller) {
    final existing = controller.id.value;
    if (existing != null && existing > 0) return Future<int>.value(existing);
    final completer = Completer<int>();
    void listener() {
      final id = controller.id.value;
      if (id != null && id > 0 && !completer.isCompleted) {
        completer.complete(id);
      }
    }

    controller.id.addListener(listener);
    // 20s：4K HEVC + copy-back 首帧注册慢；超时前再复查一次，防错过瞬时
    // 注册（listener 可能晚于实际赋值一帧）。
    return completer.future.timeout(const Duration(seconds: 20)).whenComplete(() {
      controller.id.removeListener(listener);
      if (!completer.isCompleted) {
        final id = controller.id.value;
        if (id != null && id > 0) {
          _log('纹理注册超时前复查命中 id=$id');
        }
      }
    });
  }

  void _wire(Player player) {
    _positionSub = player.stream.position.listen((d) {
      _positionMs = d.inMilliseconds;
      _emit('time-pos/full', _positionMs / 1000.0);
    });
    _durationSub = player.stream.duration.listen((d) {
      _durationMs = d.inMilliseconds;
      _emit('duration/full', _durationMs / 1000.0);
    });
    player.stream.buffer.listen((d) {
      _bufferedMs = d.inMilliseconds;
      _emit('demuxer-cache-time', _bufferedMs / 1000.0);
    });
    _playingSub = player.stream.playing.listen((playing) {
      _paused = !playing;
      _emit('pause', _paused);
    });
    _completedSub = player.stream.completed.listen((completed) {
      _eof = completed;
      _emit('eof-reached', completed);
    });
    player.stream.buffering.listen((b) {
      _emit('paused-for-cache', b);
    });
    // mpv 自身日志（logLevel=info 才有 [vd]/[vo]/[ffmpeg] 关键行）：
    // 黑屏定性全靠它——解码器选择、vo 初始化、EGL/surface 报错都在这里。
    // info 级别量可控（每秒个位数），直接进 LogService 落盘。
    //
    // 655：这里**不再**触发任何自动回退。日志只用于诊断；视频路径由
    // 设置页决定（见类注释里对 640 自动回退的删除说明）。
    _logSub = player.stream.log.listen((log) {
      if (_disposed) return;
      _log('mpv[${log.level}][${log.prefix}] ${log.text}');
    }, onError: (_) {});
  }

  // 655：640 的三个自动回退方法（`_maybeFallbackOnLog` /
  // `_startVoConfiguredWatch` / `_fallbackToTexture`）已全部删除。
  //
  // 删除理由见类字段处的注释。要点：判据太宽会误伤正常设备，且误判被
  // 持久化成 `userSet=true` 后无法自愈（一次误判 = 永久锁定纹理）。
  // 视频路径改为**纯手动**：只由设置页的 `mpvVideoOutput` 决定。

  void _emit(String name, Object? value) {
    if (_disposed || _events.isClosed) return;
    _events.add(<Object?, Object?>{
      'type': 'property',
      'name': name,
      'value': value,
    });
  }

  Future<void> _openNow(String url) async {
    final player = _player;
    if (player == null) {
      _pendingUrl = url;
      return;
    }
    await (player.platform as dynamic)?.setProperty?.call('vid', 'auto');
    await player.open(
      Media(
        url,
        httpHeaders: _pendingHeaders,
        start: Duration(milliseconds: _pendingStartMs),
      ),
      play: !_pendingPause,
    );
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    int startMs = 0,
    bool pause = false,
  }) async {
    _lastUrl = url;
    _lastHeaders = headers;
    _pendingUrl = url;
    _pendingHeaders = headers;
    _pendingStartMs = startMs;
    _pendingPause = pause;
    if (_player != null) {
      _pendingUrl = null;
      await _openNow(url);
    }
  }

  @override
  Future<bool> isReady() async => _player != null;

  @override
  Future<void> kickStart() async {
    await _player?.play();
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> seek(int positionMs) async {
    await _player?.seek(Duration(milliseconds: positionMs));
  }

  @override
  Future<void> setVolume(double volume) async {
    _pendingVolume = (volume * 100).clamp(0, 100);
    await _player?.setVolume(_pendingVolume!);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _pendingSpeed = speed;
    await _player?.setRate(speed);
  }

  /// media_kit 的 `state.tracks.*` **前置 `[auto, no]` 两条伪轨**（id 分别是
  /// `'auto'` / `'no'`，见 media_kit `real.dart` 的 track-list 解析）。
  ///
  /// 【617 真机回归：选中的音轨/字幕与实际不一致】旧实现直接 `tracks[id-1]`：
  /// 选第 1 条 → `tracks[0] = auto`（mpv 自选，可能落到别的轨）；选第 2 条 →
  /// `tracks[1] = no`（关闭）。必须跳过这两条伪轨再按 Emby 顺序取。
  static bool _isRealTrack(dynamic track) {
    final id = track?.id;
    return id != 'auto' && id != 'no';
  }

  /// 真实轨道（已剔除 auto/no 伪轨），顺序 = 容器内出现顺序 = Emby 流顺序。
  List<AudioTrack> _realAudioTracks() =>
      (_player?.state.tracks.audio ?? const <AudioTrack>[])
          .where(_isRealTrack)
          .toList(growable: false);

  List<SubtitleTrack> _realSubtitleTracks() =>
      (_player?.state.tracks.subtitle ?? const <SubtitleTrack>[])
          .where(_isRealTrack)
          .toList(growable: false);

  /// 选轨直调 `platform` 并**跳过 media_kit 的全局锁**（618）。
  ///
  /// `Player.setAudioTrack` 内部走 `lock.synchronized(...)`，而该 `lock` 是
  /// `static final`（**全进程所有 player 操作共用**）——切轨要排在其它
  /// 播放操作后面。MDK 的 `setActiveTracks` 是同步 FFI、无锁，这正是
  /// 「MDK 切轨无感、MPV 卡一下」的结构性差异。这里用 `synchronized: false`
  /// 直调（切轨是单次操作，不存在与自身并发的风险）。
  Future<void> _selectTrackNoLock(
    Future<void> Function(dynamic platform) apply,
  ) async {
    final platform = _player?.platform as dynamic;
    if (platform == null) return;
    try {
      await apply(platform);
    } catch (e) {
      _log('选轨直调失败: $e');
    }
  }

  @override
  Future<void> setAudioTrack(int id) async {
    if (id <= 0) {
      await _selectTrackNoLock(
        (p) => p.setAudioTrack(AudioTrack.no(), synchronized: false),
      );
      return;
    }
    // 617：`id` 可能是**真实 mpv track id**（track-list 映射命中）或
    // **1-based Emby 序号**（轨道表未就绪的兜底）。先按真实 id 精确匹配，
    // 匹配不到再按序号取——只按下标取会忽略真实 id，且踩中 auto/no 伪轨。
    final real = _realAudioTracks();
    final byTrackId =
        real.where((t) => int.tryParse(t.id) == id).firstOrNull;
    final track = byTrackId ??
        (id - 1 < real.length ? real[id - 1] : null);
    if (track == null) return;
    await _selectTrackNoLock(
      (p) => p.setAudioTrack(track, synchronized: false),
    );
  }

  @override
  Future<void> setSubtitleTrack(int id) async {
    if (id <= 0) {
      await _selectTrackNoLock(
        (p) => p.setSubtitleTrack(SubtitleTrack.no(), synchronized: false),
      );
      return;
    }
    // 语义同 setAudioTrack：真实 track id 优先、1-based 序号兜底。
    final real = _realSubtitleTracks();
    final byTrackId =
        real.where((t) => int.tryParse(t.id) == id).firstOrNull;
    final track = byTrackId ??
        (id - 1 < real.length ? real[id - 1] : null);
    if (track == null) return;
    await _selectTrackNoLock(
      (p) => p.setSubtitleTrack(track, synchronized: false),
    );
  }

  @override
  Future<void> addSubtitle(
    String url, {
    String title = 'external',
    String lang = 'auto',
  }) async {
    await _player?.setSubtitleTrack(
      SubtitleTrack.uri(url, title: title, language: lang),
    );
  }

  @override
  Future<void> setProperty(String name, Object value) async {
    _pendingProperties[name] = '$value';
    try {
      await (_player?.platform as dynamic)?.setProperty?.call(name, '$value');
    } catch (_) {}
  }

  @override
  Future<String?> getProperty(String name) async {
    try {
      final v = await (_player?.platform as dynamic)?.getProperty?.call(name);
      return v?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 数值属性直读（属性缺失/格式异常返回 null，不让轮询整体失败）。
  Future<double?> _readDouble(String name) async {
    final raw = await getProperty(name);
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<int?> _readInt(String name) async {
    final raw = await getProperty(name);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw) ?? double.tryParse(raw)?.round();
  }

  @override
  Future<void> resizeTexture(int width, int height) async {
    if (nativeSurface || width <= 0 || height <= 0) return;
    try {
      await _controller?.setSize(width: width, height: height);
    } catch (_) {}
  }

  @override
  Future<Uint8List?> screenshot() async {
    try {
      return await (_player?.platform as dynamic)?.screenshot?.call();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getTracks() async {
    final tracks = _player?.state.tracks;
    if (tracks == null) return null;
    // 617：剔除 media_kit 前置的 auto/no 伪轨——否则 Dart 侧解析出的
    // track id 表比 Emby 流多 2 项，面板顺序整体错位。
    return jsonEncode(<String, dynamic>{
      'video': tracks.video.where(_isRealTrack).map(_trackJson).toList(),
      'audio': tracks.audio.where(_isRealTrack).map(_trackJson).toList(),
      'subtitle': tracks.subtitle.where(_isRealTrack).map(_trackJson).toList(),
    });
  }

  Map<String, dynamic> _trackJson(dynamic track) => <String, dynamic>{
        'id': track.id,
        'title': track.title,
        'language': track.language,
        'codec': track.codec,
        'external': track.isExternal,
      };

  /// 输入色彩元数据（mpv `video-params` 的**标量子属性**）。
  ///
  /// 【697 真机回归】旧实现是**伪造**的——只拼 `{'w','h'}`，导致
  /// `primaries`/`gamma`/`sig-peak` 全部缺失，HDR/DV 排查拿不到片源真相。
  ///
  /// 现在读真实子属性（标量，media_kit 的 getProperty 直接支持）。
  /// DV Profile 不在这里（它在 `current-tracks/video` 下，见 Dart 侧
  /// 统一的 `readDebugProperties` 路径）。
  @override
  Future<String?> getVideoParams() async {
    final player = _player;
    if (player == null) return null;
    final w = player.state.width;
    final h = player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;

    final map = <String, dynamic>{'w': w, 'h': h};
    // 逐项读取，缺失就跳过（不同 mpv 版本/片源字段可用性不同）
    for (final entry in <String, String>{
      'primaries': 'video-params/primaries',
      'gamma': 'video-params/gamma',
      'sig-peak': 'video-params/sig-peak',
      'pixelformat': 'video-params/pixelformat',
      'min-luma': 'video-params/min-luma',
      'max-luma': 'video-params/max-luma',
    }.entries) {
      final v = await getProperty(entry.value);
      if (v != null && v.isNotEmpty) {
        // sig-peak / min-luma / max-luma 是浮点，其余是字符串
        if (entry.key.endsWith('luma') || entry.key == 'sig-peak') {
          final d = double.tryParse(v);
          if (d != null) map[entry.key] = d;
        } else {
          map[entry.key] = v;
        }
      }
    }
    return jsonEncode(map);
  }

  @override
  Future<String?> getAudioParams() async => null;

  @override
  Future<MpvPollResult?> pollState() async {
    final player = _player;
    if (player == null) return null;
    final state = player.state;
    // 【621 真机回归：安卓弹幕仍然跳动】统一位置数据源。
    //
    // 旧实现 `positionMs: _positionMs` 读的是**会话缓存字段**——它由
    // `player.stream.position`（异步 Stream）在 564 行写入，而事件路径
    // 又把同一个值 `_emit` 给 Dart（走 EventChannel，**也是异步**）。
    // 两条路径到达 Dart 的时序不确定 → Dart 侧 `_positionMs` 在
    // `X` 与 `X±几十ms` 之间反复横跳 → 619 的「值去重」拦不住（值不同）
    // → `setClock` 反复重锚 → 弹幕跳动。
    //
    // 改为**直读 mpv 实时属性**（与事件路径同一个源头），轮询与事件
    // 从此给出**同一个值**，横跳消失。
    final rawPos = await _readDouble('time-pos');
    final positionMs = rawPos != null && rawPos >= 0
        ? (rawPos * 1000).round()
        : _positionMs;   // 属性读不到时回落缓存（不阻塞播放）
    return MpvPollResult(
      durationMs: _durationMs,
      positionMs: positionMs,
      bufferedMs: _bufferedMs,
      paused: _paused,
      eofReached: _eof || state.completed,
      idleActive: state.playlist.medias.isEmpty,
      playlistCount: state.playlist.medias.length,
      pausedForCache: state.buffering,
      cachePercent: state.bufferingPercentage,
      videoParams: await getVideoParams(),
      trackList: await getTracks(),
      hwdecCurrent: await getProperty('hwdec-current'),
      gpuContext: await getProperty('gpu-context'),
      currentVo: await getProperty('current-vo'),
      voConfigured: await getProperty('vo-configured'),
      // 黑屏定性三元组：直读 mpv 属性（media_kit state 曾失真）。
      videoFps: await _readDouble('estimated-vf-fps'),
      frameDropCount: await _readInt('frame-drop-count'),
      videoWidth: await _readInt('width'),
      videoHeight: await _readInt('height'),
      // Android 侧 wid 直接指向 SurfaceView 的 Java Surface 全局引用：
      // 播放器存在且有有效 handle 即视为已附着（诊断行靠它定位黑屏）。
      surfaceAttached: _player != null && _surfaceHandle > 0,
      surfaceId: _surfaceHandle > 0 ? '$_surfaceHandle' : null,
      mediaTitle: state.playlist.medias.isEmpty
          ? null
          : state.playlist.medias.first.uri,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _kickGeneration++; // 作废孤儿踢循环
    final controller = _controller;
    final listener = _textureIdListener;
    if (controller != null && listener != null) {
      controller.id.removeListener(listener);
    }
    _controller = null;
    _textureIdListener = null;
    _textureId = 0;
    await _surfaceSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _logSub?.cancel();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      await _methods.invokeMethod<void>('releaseSurface');
    } catch (_) {}
    await _events.close();
  }
}
