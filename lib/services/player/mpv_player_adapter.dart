import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:himi_mpv_android/himi_mpv_android.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';
import 'mpv_session_platform.dart';
import 'native/native_player_command.dart';
import 'native/native_player_controller.dart';
import 'native/native_player_gating.dart';
import 'native/native_player_state.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:image/image.dart' as img;

import 'player_adapter.dart';

/// 把应用层的硬解档位映射为 Windows libmpv 的 `hwdec` 值。
///
/// Windows 原生的 d3d11va 零拷贝互操作在部分显卡驱动上会在首帧前崩溃，
/// 统一走 copy-back 更稳；纯软解保持 `no`。非 Windows 不做转换。
String resolveWindowsHwdec(String mode, {required bool windows}) {
  if (!windows) return mode;
  if (mode == 'no') return 'no';
  if (mode == 'auto' || mode == 'ohcodec') return 'auto-copy';
  return mode;
}

/// 三端统一 MPV 播放器适配器：通过 [MpvSession] 抽象包装鸿蒙/Android/Windows
/// 原生会话，实现 [PlayerAdapter]。mpv 的属性观察通过原生 EventChannel 推送，
/// [onMediaStatus]/[onStateChanged] 在此层转成 Adapter 抽象类型；
/// position/duration 走 mpv 的 `time-pos/full`/`duration/full` 观察。
///
/// 与 mdk 适配器的关键差异：
/// - `nativeHandle` 恒 0；Surface/Texture 由 MPV 视频路径设置决定；
/// - mpv 的 `track-list`/`video-params`/`audio-params` 是 **JSON 字符串**
///   （原生把 mpv_node 序列化后派发），需 `jsonDecode`；
/// - 播完判定靠 `eof-reached` 属性 + `MPV_EVENT_END_FILE` 双保险
///   （mpv 不像 mdk 那样自动把 end 位放进 mediaStatus）。
class MpvPlayerAdapter implements PlayerAdapter, AsyncDisposablePlayer {
  MpvPlayerAdapter({int startMs = 0, String hwdecMode = 'performance'})
      : _startMs = startMs,
        _hwdecRenderMode = hwdecMode {
    MpvLog.sink ??=
        (tag, message) => LogService().log('mpv', '[$tag] $message');
  }

  final int _startMs;

  /// 硬解渲染档位（standard/performance/extreme，来自设置，
  /// 经 PlayerEngineFactory 传入；原生 create 时生效）。
  final String _hwdecRenderMode;
  MpvSession? _player;
  bool _disposed = false;
  bool _prepared = false;
  bool _appliedHdrOutput = false;

  AdapterPlaybackState _state = AdapterPlaybackState.stopped;
  AdapterMediaStatus _mediaStatus = AdapterMediaStatus.unloaded;
  int _positionMs = 0;
  int _durationMs = 0;
  int _bufferedMs = 0;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  AdapterMediaInfo _mediaInfo = AdapterMediaInfo.empty;

  /// 已知属性的字符串快照：`getProperty` 是同步接口，只能从缓存读。
  final Map<String, String> _propertyCache = <String, String>{};

  /// mpv `eof-reached` 状态（播完判定）。
  bool _eofReached = false;

  StreamController<
          ({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>?
      _stateCtrl;
  StreamController<
          ({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>?
      _statusCtrl;
  StreamController<AdapterMediaEvent>? _eventCtrl;

  StreamSubscription<Map<Object?, Object?>>? _rawSub;

  /// 并发调用 [disposeAsync] 时共享同一个释放 Future。
  Future<void>? _disposeFuture;

  /// 原生播放器句柄（mpv 无 SurfaceView 通道，恒 0）。
  @override
  int get nativeHandle => 0;

  // ── 播放控制 ──────────────────────────────────────────────

  @override
  AdapterPlaybackState get state =>
      _disposed ? AdapterPlaybackState.stopped : _state;

  @override
  set state(AdapterPlaybackState value) {
    if (_disposed) return;
    final player = _player;
    if (player == null) return;
    switch (value) {
      case AdapterPlaybackState.playing:
        unawaited(player.play());
        break;
      case AdapterPlaybackState.paused:
        unawaited(player.pause());
        break;
      case AdapterPlaybackState.stopped:
        unawaited(player.stop());
        break;
    }
    // 播放/暂停切换属 requiresImmediatePush 语义：立即同步原生 UI。
    _pushNativeUiState(immediate: true);
  }

  @override
  Future<void> seek({required int positionMs}) async {
    if (_disposed) return;
    // seek 冷却标记：部分 demuxer 在 seek 期间会瞬时报 eof-reached，
    // 状态机若立即采信会触发自动重播（真机 v1.2.93「快进从头播」）。
    _lastSeekCommandAt = DateTime.now();
    await _player?.seek(positionMs);
    // seek 后进度权威值以轮询/事件回读为准；此处先推本地乐观值，
    // 避免原生 UI 进度条回弹。
    _nativeUiOptimisticSeek(positionMs);
    _pushNativeUiState(immediate: true);
  }

  /// 最近一次 seek 命令时间（eof 采信冷却依据）。
  DateTime? _lastSeekCommandAt;

  /// 播完判定：`eof-reached=true` → 置 end 位；回到 false（换集/重播）→ 清位。
  ///
  /// 双守卫（v1.2.94，免疫式修复「快进从头播」）：
  /// 1. 时长未知（duration<=0）忽略——直播/转码流 seek 后瞬时报 eof；
  /// 2. **seek 后 5 秒冷却期内忽略**——文件流 seek 期间 demuxer 也可能
  ///    瞬时翻 eof 位，两路（事件/轮询）都过这道闸。
  void _handleEofReached(bool reached) {
    if (reached) {
      if (_durationMs <= 0) {
        LogService().log('mpv', 'eof-reached 但时长未知，忽略（防 seek 误判播完）');
        return;
      }
      final lastSeek = _lastSeekCommandAt;
      if (lastSeek != null &&
          DateTime.now().difference(lastSeek).inSeconds < 5) {
        LogService().log('mpv', 'eof-reached 在 seek 冷却期内，忽略');
        return;
      }
    }
    _eofReached = reached;
    if (reached) {
      _setStatus(_mediaStatus | AdapterMediaStatus.end);
    } else {
      _setStatus(AdapterMediaStatus(
        _mediaStatus.rawValue & ~AdapterMediaStatus.end.rawValue,
      ));
    }
  }

  // ── 媒体加载 ──────────────────────────────────────────────

  String? _uri;
  Map<String, String> _headers = const {};

  /// 当前媒体是否 HDR：用于 HDR 输出决策与首帧前纹理尺寸保护。
  bool _hdrContentForMedia = false;

  set hdrContent(bool value) {
    if (_hdrContentForMedia == value) return;
    _hdrContentForMedia = value;
    unawaited(_refreshHdrOutputForCurrentSession());
  }

  /// 内容是否为 HLG（用于 HDR 直出时选择 target-trc）。
  bool _hlgContentForMedia = false;
  set hlgContent(bool value) {
    if (_hlgContentForMedia == value) return;
    _hlgContentForMedia = value;
    unawaited(_refreshHdrOutputForCurrentSession());
  }

  /// SDR 纹理链路不可用时强制原生 Surface。
  bool _forceNativeSurface = false;
  set forceNativeSurface(bool value) => _forceNativeSurface = value;

  /// MPV 视频路径设置：surface/texture。仅 MPV 生效。
  String _mpvVideoOutput = MpvOutputPolicy.surface;
  bool _mpvVideoOutputUserSet = false;
  set mpvVideoOutput(String value) => _mpvVideoOutput = value;
  set mpvVideoOutputUserSet(bool value) => _mpvVideoOutputUserSet = value;

  bool? _displayHdr;
  bool _hdrOutputActive = false;
  String _requestedMpvVideoOutput = MpvOutputPolicy.surface;
  String _targetTrc = 'auto';
  bool _surfaceAttached = false;
  String? _surfaceId;
  String? _surfaceError;
  String? _voConfigured;

  /// 最近一次轮询的 vo / gpu-context（诊断与原生 UI 状态用）。
  String? _currentVo;
  String? _gpuContext;

  /// 黑屏定性三元组（直读 mpv，见 [MpvPollResult.videoFps]）：
  /// fps>0 = 在出帧 → 呈现问题；fps=0 → 解码/vo 问题。
  double? _videoFps;
  int? _frameDropCount;
  int? _videoWidth;
  int? _videoHeight;

  /// 起播属性时间线已记录的时间点（2s/5s/10s 各一次，防重复打日志）。
  final Set<int> _timelineLoggedSec = <int>{};
  DateTime? _playbackStartedAt;

  /// 当前 MPV 是否正在输出 HDR（仅 Surface + HDR 内容 + HDR 显示）。
  bool get hdrOutputActive => _hdrOutputActive;

  /// 调试面板：请求的 MPV 视频路径（可能因原生回退与 actual 不同）。
  String get mpvRequestedVideoOutput => _requestedMpvVideoOutput;

  /// 调试面板：实际 MPV 视频路径。
  String get mpvActualVideoOutput =>
      usesNativeSurface ? MpvOutputPolicy.surface : MpvOutputPolicy.texture;

  /// 调试面板：原生实际是否 Surface。
  bool get mpvUsesNativeSurface => usesNativeSurface;

  /// 调试面板：显示端 HDR 能力；null=尚未查询。
  bool? get mpvDisplayHdr => _displayHdr;

  /// 调试面板：当前目标 transfer（pq/hlg/auto）。
  String get mpvTargetTrc => _targetTrc;

  bool get mpvSurfaceAttached => _surfaceAttached;
  String? get mpvSurfaceId => _surfaceId;
  String? get mpvSurfaceError => _surfaceError;
  String? get mpvVoConfigured => _voConfigured;

  // ── 原生播放器 UI（全屏原生窗口）门控 ──────────────────────

  /// 用户设置：是否允许原生播放器 UI（默认开启）。
  bool _nativeUiSettingEnabled = true;
  bool get nativeUiSettingEnabled => _nativeUiSettingEnabled;
  set nativeUiSettingEnabled(bool value) => _nativeUiSettingEnabled = value;

  /// 本次会话是否实际启用原生播放器 UI。
  ///
  /// 门控条件（NativePlayerGating）：引擎 mpv + 实际输出 surface +
  /// 平台 Android/鸿蒙 + 设置开启。会话创建后若原生回退到 Texture，
  /// 则不启用。
  bool _nativeUiEnabled = false;
  bool get nativeUiEnabled => _nativeUiEnabled;

  /// 原生 UI 宿主是否打开（PlayerScreen 据此隐藏 Flutter 视频/控件层；
  /// 值变化时经 [nativeUiActive] 通知重建）。
  final ValueNotifier<bool> nativeUiActive = ValueNotifier<bool>(false);

  /// 原生播放器 UI 控制器（计划书 §4.3；原生 UI 启用时创建）。
  NativePlayerController? get nativeUiController => _nativeUiController;
  NativePlayerController? _nativeUiController;

  /// PlayerScreen 注入：原生 UI 请求退出（back/exit）时回调——由上层
  /// 执行关闭原生宿主 + 退出播放页（适配器不持有导航能力）。
  void Function()? onNativeUiExit;

  /// PlayerScreen 注入：原生命令的通用出口（Phase 2）。
  ///
  /// adapter 自己处理 6 类（播放/seek/音量/倍速/退出），其余转发到此，
  /// 由 PlayerScreen 路由到现成 handler（选集/版本/音轨/字幕/…）。路由
  /// 矩阵见 `docs/native_player_command_routing.md`。
  Future<void> Function(NativePlayerCommand command)? onNativeUiCommand;

  /// 调试面板「HDR 直出」状态：按实际路径判断，不用请求值。
  String get mpvHdrOutputStatus {
    if (_player == null) return '未就绪';
    if (!usesNativeSurface) return '纹理 · SDR（tone map）';
    return _hdrOutputActive ? 'Surface · HDR 直出' : 'Surface · SDR（tone map）';
  }

  Future<bool> _queryDisplayHdr() async {
    final cached = _displayHdr;
    if (cached != null) return cached;
    try {
      final caps = await MpvSessionPlatform.queryHdrCapabilities();
      _displayHdr = caps.displayHdr;
    } catch (_) {
      _displayHdr = false;
    }
    return _displayHdr ?? false;
  }

  String _resolveMpvVideoOutput() => MpvOutputPolicy.effectiveVideoOutput(
        configured: _mpvVideoOutput,
        userSet: _mpvVideoOutputUserSet,
        windows: defaultTargetPlatform == TargetPlatform.windows,
      );

  Future<void> _applyHdrOutputProperties(bool enabled) async {
    final player = _player;
    if (player == null) return;
    _targetTrc = enabled ? (_hlgContentForMedia ? 'hlg' : 'pq') : 'auto';
    final props = enabled
        ? <String, String>{
            'target-colorspace-hint': 'yes',
            'target-prim': 'bt.2020',
            'target-trc': _hlgContentForMedia ? 'hlg' : 'pq',
            'hdr-compute-peak': 'auto',
            'tone-mapping': 'clip',
            if (defaultTargetPlatform == TargetPlatform.windows)
              'd3d11-output-format': 'rgb10_a2',
          }
        : <String, String>{
            'target-colorspace-hint': 'no',
            'target-prim': 'auto',
            'target-trc': 'auto',
            if (defaultTargetPlatform == TargetPlatform.windows)
              'd3d11-output-format': 'auto',
          };
    for (final entry in props.entries) {
      try {
        await player.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
    try {
      final actual = await player.getProperty('target-trc');
      if (actual != null && actual.isNotEmpty) _targetTrc = actual;
    } catch (_) {}
  }

  Future<void> _refreshHdrOutputForCurrentSession() async {
    if (_disposed || !_prepared) return;
    final player = _player;
    if (player == null || !player.usesNativeSurface) return;
    final effective = _resolveMpvVideoOutput();
    if (effective != MpvOutputPolicy.surface) return;
    final decision = MpvOutputPolicy.resolve(
      videoOutput: effective,
      contentHdr: _hdrContentForMedia,
      displayHdr: await _queryDisplayHdr(),
      forceNativeSurface: _forceNativeSurface,
    );
    if (!decision.nativeSurface || decision.hdrOutput == _hdrOutputActive) {
      return;
    }
    await _applyHdrOutputProperties(decision.hdrOutput);
    _hdrOutputActive = decision.hdrOutput && player.usesNativeSurface;
    _targetTrc =
        _hdrOutputActive ? (_hlgContentForMedia ? 'hlg' : 'pq') : 'auto';
    LogService().log(
      'mpv',
      'HDR 输出更新: ${decision.hdrOutput ? "HDR 直出" : "SDR tone map"} '
          '(content=${_hdrContentForMedia ? "HDR" : "SDR"}, '
          'display=${decision.hdrOutput || !_hdrContentForMedia ? "-" : "SDR"})',
    );
  }

  /// 当前输出是否走原生 Surface（平台视图）。
  bool get usesNativeSurface => _player?.usesNativeSurface ?? false;

  /// 把 X-Emby-Token 拼进 URL 的 api_key 参数（Emby 流端点原生支持）。
  ///
  /// 真机（v1.2.77）证实 header 两条传递路径均不可靠，而 app 内同域名
  /// 其他请求全部正常——鉴权必须与 header 传递解耦。URL 已带 api_key
  /// 或无 token 时原样返回。
  String _authorizeUrl(String url) {
    if (url.isEmpty) return url;
    if (url.contains('api_key=')) return url;
    final token = _headers['X-Emby-Token'];
    if (token == null || token.isEmpty) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '${url}${sep}api_key=${Uri.encodeQueryComponent(token)}';
  }

  @override
  set media(String uri) {
    _uri = uri;
  }

  @override
  Future<void> prepare({int startMs = 0}) async {
    if (_disposed) return;
    final start = startMs > 0 ? startMs : _startMs;

    // 首次调用创建播放器并按需订阅原生事件。
    // v1.2.73 起原生 create 内同步完成 initialize（不再等 surface），
    // 所以这里的 setProperty/open 立即真正生效。
    var player = _player;
    final effectiveOutput = _resolveMpvVideoOutput();
    _requestedMpvVideoOutput = effectiveOutput;
    final displayHdr = await _queryDisplayHdr();
    final decision = MpvOutputPolicy.resolve(
      videoOutput: effectiveOutput,
      contentHdr: _hdrContentForMedia,
      displayHdr: displayHdr,
      forceNativeSurface: _forceNativeSurface,
    );
    final nativeSurface = decision.nativeSurface;
    // 原生播放器 UI 门控：请求路径为 surface 时才可能启用；实际是否
    // 启用要等会话创建后按原生回报的 usesNativeSurface 确认。
    final nativeUiRequested = nativeSurface &&
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: MpvOutputPolicy.surface,
          settingEnabled: _nativeUiSettingEnabled,
        );
    if (player != null && player.usesNativeSurface != nativeSurface) {
      // HDR 状态在运行期翻转时，渲染目标必须重建：纹理与原生 Surface
      // 不能在同一 mpv 会话里热切换。
      await _rawSub?.cancel();
      _rawSub = null;
      await player.dispose();
      player = null;
      _player = null;
      _appliedHdrOutput = false;
      _nativeUiEnabled = false;
      unawaited(_closeNativeUi());
    }
    if (player == null) {
      // 初始尺寸只作为提示；实际 Surface/Texture 由设置决定。
      final initW = _hdrContentForMedia ? 1280 : 1920;
      final initH = _hdrContentForMedia ? 720 : 1080;
      player = await MpvSessionPlatform.create(
        hwdecMode: _hwdecRenderMode,
        width: initW,
        height: initH,
        nativeSurface: nativeSurface,
        nativeUi: nativeUiRequested,
        hdr: decision.hdrOutput,
        hlg: decision.hdrOutput && _hlgContentForMedia,
      );
      if (_disposed) {
        // 创建期间已被销毁：立刻回收，避免泄漏。
        unawaited(player.dispose());
        return;
      }
      _player = player;
      // Android 会话的诊断日志接到 LogService（进 App 调试面板 + 落盘 +
      // logcat），否则 surface 事件时序完全不可见（黑屏盲区）。
      if (player is HimiMpvAndroidSession) {
        HimiMpvAndroidSession.debugLog =
            (message) => LogService().log('mpv/surface', message);
      }
      // 原生确认实际为 Surface 才启用原生 UI；请求 Surface 但回退
      // Texture 时不打开原生窗口，保持 Flutter UI。
      _nativeUiEnabled = nativeUiRequested && player.usesNativeSurface;
      LogService().log(
          'mpv',
          'session created: native=${player.usesNativeSurface} '
              'texture=${player.textureId} requested=$effectiveOutput '
              'actual=${player.usesNativeSurface ? MpvOutputPolicy.surface : MpvOutputPolicy.texture} '
              'hdrRequested=${decision.hdrOutput} '
              'hdrReported=${player.hdrOutputActive} displayHdr=$displayHdr '
              'nativeUi=$_nativeUiEnabled');
      if (nativeSurface && !player.usesNativeSurface) {
        LogService().log('mpv',
            '输出路径不一致: 请求 Surface，原生实际 Texture(textureId=${player.textureId})');
      }
      // 原生 UI 启用：立即打开宿主窗口（幂等），Flutter 视频/控件层
      // 随 nativeUiActive 翻转隐藏（计划书 §7.3）。
      if (_nativeUiEnabled) {
        unawaited(_openNativeUiIfNeeded());
      }
      _ensureEventSubscription();
      _appliedHdrOutput = decision.hdrOutput;
    } else if (_appliedHdrOutput != decision.hdrOutput) {
      await _applyHdrOutputProperties(decision.hdrOutput);
      _appliedHdrOutput = decision.hdrOutput;
    }
    final reportedHdr = player.hdrOutputActive;
    _hdrOutputActive =
        player.usesNativeSurface && (reportedHdr ?? decision.hdrOutput);
    if (reportedHdr != null && reportedHdr != decision.hdrOutput) {
      LogService()
          .log('mpv', 'HDR 状态不一致: 请求 ${decision.hdrOutput}，原生回报 $reportedHdr');
    }
    _targetTrc =
        _hdrOutputActive ? (_hlgContentForMedia ? 'hlg' : 'pq') : 'auto';

    // 渲染通道就绪标记：v1.2.80 起原生 create 自注册 Flutter 纹理并返回
    // 真实纹理 id（>0 = 纹理渲染模式，上层挂 Texture）；0 = 回退平台视图
    // 模式（上层挂 OhosView/XComponent）。上层 ValueListenableBuilder 靠
    // 它决定渲染分支与视频区显形时机。
    _textureIdListenable.value = player.textureId;

    // 软硬解开关必须在 loadfile 之前写入：mpv 的 hwdec 在解码器创建时
    // 读取，open 之后再改要重载才生效。这里每次都显式写一遍，确保
    // 用户切换「硬解/软解/自动」后下一次起播立即按新配置走。
    //
    // 所有内容（含 HDR10 / DV P5）先按用户档位硬解；ohosvk 提供
    // OHCodec 10bit Vulkan 零拷贝互操作。硬解失败时由「媒体在播但无
    // video-params」的自动软解回退兜底（见 _maybeFallbackToSoftwareDecode）。
    final effectiveHwdec = resolveWindowsHwdec(
      _hwdec,
      windows: defaultTargetPlatform == TargetPlatform.windows,
    );
    try {
      await player.setProperty('hwdec', effectiveHwdec);
      if (effectiveHwdec != 'no') {
        // 硬解模式下允许 mpv 在硬件不支持时回退软解（auto 语义）；
        // 纯硬解（auto-safe）档同样保留回退，否则不支持的编码会直接黑屏。
        await player.setProperty('hwdec-software-fallback', 'yes');
      }
    } catch (e) {
      LogService().log('mpv', 'prepare: hwdec 写入失败: $e');
    }
    LogService().log(
        'mpv',
        'prepare: hwdec=$effectiveHwdec (requested=$_hwdec) '
            'url=${(_uri ?? '').length}字符');

    // 起播恒以暂停态打开：由上层 state setter 决定何时出声，
    // 避免页面未挂载/未就绪时先出声音（与 mdk 的 prepare 语义一致）。
    //
    // 原生侧在 surface 未就绪时缓存 URL（等 XComponent 就绪自动加载，
    // 另有 8s watchdog 兜底），这里不需要等待。
    //
    // 鉴权：v1.2.78 起 token 直接拼进 URL（Emby 流端点原生支持 api_key
    // 查询参数）。真机实测 header 路径（loadfile options + 全局属性双写）
    // 仍未送达——"Failed to open"且 app 内同域名其他请求全部正常，
    // 只可能是 mpv 的请求没带鉴权被服务器拒绝。URL 带 key 后不再依赖
    // 任何 header 传递环节。
    await player.open(
      _authorizeUrl(_uri ?? ''),
      headers: _headers,
      startMs: start,
      pause: true,
    );
    _prepared = true;
    _openedAt = DateTime.now();
    _kickCount = 0;
    // 每次新起播重置软解回退标记：新文件重新给硬解机会
    _swDecodeFallbackDone = false;
    _swStillNoVideoNoted = false;
    _videoWaitSince = null;
    // 首帧等待状态复位（v1.2.89）
    _videoParamsSeen = false;
    _trackHasVideo = false;
    firstFramePending.value = false;

    // 启动轮询兜底：mpv 的事件/属性回调经 JSBind 绑定，在部分设备上
    // 可能完全不送达（表现为纹理有了但时长/分辨率永远为空 → 无限转圈）。
    // 轮询与事件流并行，谁先到用谁，互相补齐。
    _startPolling();
  }

  /// 轮询定时器（事件流失效时的兜底数据源）。
  Timer? _pollTimer;
  bool _pollInFlight = false;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    if (_disposed || _pollInFlight) return;
    final player = _player;
    if (player == null) return;
    _pollInFlight = true;
    try {
      final state = await player.pollState().timeout(
            const Duration(seconds: 2),
          );
      if (state == null || _disposed) return;
      _applyPolledState(state);
    } catch (_) {
      // 轮询失败不影响主流程（事件流可能仍然正常）。
    } finally {
      _pollInFlight = false;
    }
  }

  /// 时长变化统一入口：同步内部字段、属性缓存和 mediaInfo。
  ///
  /// 轮询路径此前只改 `_durationMs`，`mediaInfo.duration` 仍是
  /// video-params 到达时的旧值（通常为 0），上层读 mediaInfo 会一直
  /// 认为时长未知，导致初始转圈不消失。
  void _updateDurationMs(int ms) {
    _durationMs = ms;
    _propertyCache['duration'] = (_durationMs / 1000.0).toStringAsFixed(3);
    _mediaInfo = AdapterMediaInfo(
      duration: _durationMs,
      format: _mediaInfo.format,
      audio: _mediaInfo.audio,
      video: _mediaInfo.video,
      subtitleCount: _mediaInfo.subtitleCount,
    );
  }

  /// 起播属性时间线：2s/5s/10s 各打一次黑屏定性快照，导出日志里能直接
  /// 看到 fps/丢帧/视频尺寸/vo 的演变（单张诊断行只能看到瞬时值）。
  void _maybeLogPlaybackTimeline() {
    final hasProgress = _positionMs > 0 || _durationMs > 0;
    if (!hasProgress) return;
    _playbackStartedAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(_playbackStartedAt!).inSeconds;
    for (final mark in const <int>[2, 5, 10, 20]) {
      if (elapsed >= mark && _timelineLoggedSec.add(mark)) {
        LogService().log(
          'mpv/timeline',
          't+${mark}s fps=${_videoFps ?? "-"} drop=${_frameDropCount ?? "-"} '
              'video=${_videoWidth ?? "-"}x${_videoHeight ?? "-"} '
              'vo=${_voConfigured ?? "-"}(${_currentVo ?? "-"}) '
              'hwdec=${_hwdecActual ?? "-"} '
              'surface=${_surfaceAttached ? "att" : "no"} '
              'pos=${_positionMs}ms',
        );
      }
    }
  }

  /// 把轮询结果并入状态机（与事件回调走同一套更新逻辑）。
  void _applyPolledState(MpvPollResult state) {
    _surfaceAttached = state.surfaceAttached;
    _surfaceId = state.surfaceId;
    _surfaceError = state.surfaceError;
    _voConfigured = state.voConfigured;
    _currentVo = state.currentVo;
    _gpuContext = state.gpuContext;
    _videoFps = state.videoFps;
    _frameDropCount = state.frameDropCount;
    _videoWidth = state.videoWidth;
    _videoHeight = state.videoHeight;
    _maybeLogPlaybackTimeline();
    final hasProgress = state.durationMs > 0 ||
        state.positionMs > 0 ||
        state.videoParams != null ||
        !state.idleActive;
    if (hasProgress) {
      if (state.durationMs > 0 && state.durationMs != _durationMs) {
        _updateDurationMs(state.durationMs);
      }
      // 时长可读、或位置在推进、或已非空闲（文件已加载）都算「已加载」——
      // 转码 HLS 直播流可能永远报不出 duration，不能只看时长（v1.2.75）。
      _setStatus(AdapterMediaStatus.loaded |
          AdapterMediaStatus.prepared |
          AdapterMediaStatus.buffered);
    }
    if (state.positionMs > 0) {
      _positionMs = state.positionMs;
      _propertyCache['time-pos'] = (_positionMs / 1000.0).toStringAsFixed(3);
    }
    if (state.bufferedMs > 0) _bufferedMs = state.bufferedMs;

    if (state.videoParams != null) {
      _parseVideoParams(state.videoParams);
      _videoParamsSeen = true;
    }
    if (state.trackList != null) {
      _parseTracks(state.trackList);
    }
    _trackHwdecActual(state.hwdecCurrent);
    // 首帧等待标记（v1.2.89）：有视频轨、时长已到（声音/进度先出）但
    // video-params 还没来 = 解码器起热中、画面未出——UI 据此盖一层
    // 缓冲遮罩，把「黑屏但有声音」的观感变成「还在加载」。
    _updateFirstFramePending(state);

    if (state.eofReached != _eofReached) {
      _handleEofReached(state.eofReached);
    }
    if (state.pausedForCache) {
      _setBuffering(true);
    } else if (state.bufferedMs > 0) {
      _setBuffering(false);
    }
    if (_prepared && hasProgress) {
      _setState(state.paused
          ? AdapterPlaybackState.paused
          : AdapterPlaybackState.playing);
    }
    _maybeKickStalledLoad(state);
    _maybeFallbackToSoftwareDecode(state);
    // 原生 UI 状态同步：轮询节拍推送（控制器内部 200ms 防抖合并）。
    _pushNativeUiState();
  }

  /// 有声无画的自动回退（v1.2.79）：媒体在播（时长/位置推进）但 5s 内
  /// 一直无 video-params = 视频轨解码没起来——典型原因是 ohcodec 不支持
  /// 该编码且软件回退未生效。自动切软解（hwdec=no）并按当前进度重载。
  /// 单次触发；软解下仍无则记录一次线索不再动作（指向渲染层）。
  bool _swDecodeFallbackDone = false;
  bool _swStillNoVideoNoted = false;
  DateTime? _videoWaitSince;

  void _maybeFallbackToSoftwareDecode(MpvPollResult state) {
    if (_disposed || !_prepared) return;
    if (state.videoParams != null || state.idleActive) {
      _videoWaitSince = null;
      return;
    }
    // 只有确在播放（时长或位置在推进）才介入，避免加载窗口误触发。
    if (state.durationMs <= 0 && state.positionMs <= 0) return;
    final since = _videoWaitSince ??= DateTime.now();
    if (DateTime.now().difference(since).inSeconds < 3) return;
    if (_hwdec == 'no') {
      if (!_swStillNoVideoNoted) {
        _swStillNoVideoNoted = true;
        _noteError('软解下仍无视频参数：视频轨可能不存在，或为渲染层问题（surface 已绑但 vo 未出帧）');
      }
      return;
    }
    if (_swDecodeFallbackDone) return;
    _swDecodeFallbackDone = true;
    _hwdec = 'no';
    _noteError('有声音无画面：自动切软解重载（硬解疑似不支持该内容）');
    unawaited(_player?.setProperty('hwdec', 'no'));
    final uri = _uri;
    if (uri == null || uri.isEmpty) return;
    // 重载窗口复位首帧标记：遮罩重新盖上，声画同步起播逻辑重新生效。
    _videoParamsSeen = false;
    firstFramePending.value = true;
    unawaited(_player?.open(
      _authorizeUrl(uri),
      headers: _headers,
      startMs: _positionMs > 0 ? _positionMs : _startMs,
      pause: false,
    ));
  }

  /// open 之后 6s 无进展的自动救援：
  /// - 空闲且播放列表有条目（loadFile 执行了但没开播）→ kickStart（轻踢，
  ///   playlist-pos=0，不重载）；
  /// - 空闲且播放列表为空（loadfile 从未生效）→ 重发 open（重载）。
  /// 状态写进 lastMpvError 供屏幕诊断展示。
  DateTime? _openedAt;
  int _kickCount = 0;

  void _maybeKickStalledLoad(MpvPollResult state) {
    if (!_prepared || _disposed) return;
    // 已非空闲 = 正在加载/播放，无需救援。
    if (!state.idleActive) return;
    final openedAt = _openedAt;
    if (openedAt == null) return;
    final elapsed = DateTime.now().difference(openedAt);
    if (elapsed.inSeconds < 6 || _kickCount >= 3) return;
    _kickCount += 1;
    _openedAt = DateTime.now();
    if (state.playlistCount > 0) {
      _noteError('条目未开播，轻踢 playlist-pos（$_kickCount/3）');
      unawaited(_player?.kickStart());
      return;
    }
    _noteError('loadfile 未生效，重发 open（$_kickCount/3）');
    final uri = _uri;
    if (uri == null || uri.isEmpty) return;
    unawaited(_player?.open(
      _authorizeUrl(uri),
      headers: _headers,
      startMs: _positionMs > 0 ? _positionMs : _startMs,
      pause: false,
    ));
  }

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position => _positionMs;

  @override
  int get duration => _durationMs;

  @override
  AdapterMediaInfo get mediaInfo => _mediaInfo;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    unawaited(_player?.setVolume(value));
    _pushNativeUiState();
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    _playbackRate = value;
    unawaited(_player?.setSpeed(value));
    _pushNativeUiState(immediate: true);
  }

  @override
  AdapterMediaStatus get mediaStatus => _mediaStatus;

  @override
  int buffered() => _bufferedMs;

  @override
  ValueListenable<int?> get textureId => _textureIdListenable;

  /// 平台视图模式：渲染走 XComponent，`textureId` 不用于挂 Texture。
  ///
  /// 上层据此切换到 [HimiMpvView] 分支。这里用「已就绪」语义填充
  /// ValueListenable，让既有的「输出就绪」判定逻辑无需大改。
  final ValueNotifier<int?> _textureIdListenable = ValueNotifier<int?>(null);

  /// v1.2.80：纹理 id > 0 时为纹理渲染模式（Flutter Texture 合成）；
  /// 仅在原生纹理注册失败回退平台视图时为 false（OhosView/XComponent）。
  bool get usesPlatformView => (_textureIdListenable.value ?? 0) <= 0;

  // ── 渲染 ──────────────────────────────────────────────────

  @override
  Future<int> updateTexture({int? width, int? height, bool? tunnel}) async {
    if (_disposed) return -1;
    final player = _player;
    if (player == null) return -1;
    // 纹理模式：同步真实纹理 id；平台视图回退模式为 0。
    _textureIdListenable.value = player.textureId;
    return player.textureId;
  }

  @override
  Future<Size?> get textureSize async {
    Size? known() {
      final video = _mediaInfo.video;
      if (video.isNotEmpty && video.first.width > 0 && video.first.height > 0) {
        return Size(
          video.first.width.toDouble(),
          video.first.height.toDouble(),
        );
      }
      return null;
    }

    // video-params 在文件加载完成后出现（事件或轮询任一喂到 _mediaInfo）。
    // v1.2.73 起 mpv 在 create 时即完成 initialize，属性读取不依赖
    // surface。这里短等 video-params（1.2s 上限，v1.2.81 起播提速：旧值
    // 6s 会把起播关键路径拖住；屏幕层另有 1s×10 次的重试兜底，尺寸晚到
    // 只影响画面比例一瞬，不阻塞开播）。
    final immediate = known();
    if (immediate != null) return immediate;

    final player = _player;
    if (player == null) return null;

    final deadline = DateTime.now().add(const Duration(milliseconds: 1200));
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) return null;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final cached = known();
      if (cached != null) return cached;
      // 兜底：事件/轮询都还没喂到时直接问一次原生。
      try {
        final params = await player.getVideoParams();
        if (params != null) {
          final size = _sizeFromVideoParams(params);
          if (size != null) return size;
        }
      } catch (_) {}
    }
    LogService().log('mpv', '等待 video-params 超时（1.2s），返回空尺寸（后续重试兜底）');
    return null;
  }

  /// 从 mpv `video-params` JSON 解析分辨率；无效返回 null。
  static Size? _sizeFromVideoParams(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final w = (json['w'] as num?)?.round() ?? 0;
      final h = (json['h'] as num?)?.round() ?? 0;
      if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
    } catch (_) {}
    return null;
  }

  @override
  void setColorSpace(AdapterColorSpace cs) {
    // mpv 自行处理色彩空间（gpu-next 按视频参数做 tone mapping / 色域转换），
    // 无 mdk 那种逐内容 setColorSpace 的入口。
  }

  @override
  void renderVideo() {
    // mpv 的 vo 自主按 vsync 出帧，无需外部驱动。
  }

  // ── 轨道 ──────────────────────────────────────────────────

  List<int> _activeAudioTracks = const [];
  List<int> _activeSubtitleTracks = const [];

  /// mpv `track-list` 里音轨/字幕轨的 id（1-based，按出现顺序）。
  ///
  /// 上层的 `activeAudioTracks`/`activeSubtitleTracks` 传的是 **Emby 流索引**
  /// （0-based，与 Emby 元数据数组对齐），而 mpv 的 `aid`/`sid` 是它自己的
  /// track id。两者必须映射，否则选第 2 条字幕会切到别的轨。
  final List<int> _audioTrackIds = <int>[];
  final List<int> _subtitleTrackIds = <int>[];

  /// 把上层（Emby 索引）映射成 mpv track id；映射不到时返回 null。
  static int? _mapIndexToTrackId(List<int> ids, int index) {
    if (index < 0) return null;
    if (index < ids.length) return ids[index];
    return null;
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> tracks) {
    _activeAudioTracks = tracks;
    if (tracks.isEmpty) return;
    final index = tracks.first;
    final trackId = _mapIndexToTrackId(_audioTrackIds, index);
    // 轨道表未就绪（文件刚 open）时先按 index+1 兜底：mpv 的 aid 通常从 1 起。
    unawaited(_player?.setAudioTrack(trackId ?? (index + 1)));
  }

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> tracks) {
    _activeSubtitleTracks = tracks;
    if (tracks.isEmpty) {
      // 0 = 关闭字幕（mpv 的 sid 语义）。
      unawaited(_player?.setSubtitleTrack(0));
      return;
    }
    final index = tracks.first;
    final trackId = _mapIndexToTrackId(_subtitleTrackIds, index);
    unawaited(_player?.setSubtitleTrack(trackId ?? (index + 1)));
  }

  // ── 事件 ──────────────────────────────────────────────────

  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged =>
          (_stateCtrl ??= StreamController.broadcast()).stream;

  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus =>
          (_statusCtrl ??= StreamController.broadcast()).stream;

  @override
  Stream<AdapterMediaEvent> get onEvent =>
      (_eventCtrl ??= StreamController.broadcast()).stream;

  void _ensureEventSubscription() {
    if (_rawSub != null) return;
    _rawSub = _player?.events.listen(_handleRaw);
  }

  void _handleRaw(Map<Object?, Object?> raw) {
    if (_disposed) return;
    final prop = MpvPropertyEvent.tryParse(raw);
    if (prop != null) {
      _handleProperty(prop);
      return;
    }
    final event = MpvEvent.tryParse(raw);
    if (event != null) {
      _handleMpvEvent(event);
      return;
    }
    // 日志：warn 及以上转存（原生侧只订阅 warn 级）——保留最近 5 条环形
    // 缓冲：mpv 报错顺序有信息量（「URL 打开失败」在前、「ytdl 回退失败」
    // 在后），只留最后一条会把第一现场盖掉（v1.2.76 真机实测）。
    if (raw['type'] == 'log') {
      final level = raw['level'];
      final message = raw['message'];
      if (level == 'error' || level == 'fatal' || level == 'warn') {
        final text = '${message ?? ''}'.trim();
        if (text.isNotEmpty) {
          _mpvErrors.add(text);
          if (_mpvErrors.length > 5) {
            _mpvErrors.removeAt(0);
          }
          LogService().log('mpv', text);
        }
      }
    }
  }

  /// 最近 5 条 mpv warn/error（起播诊断展示用；含救援动作的说明行）。
  final List<String> _mpvErrors = <String>[];

  void _noteError(String text) {
    _mpvErrors.add(text);
    if (_mpvErrors.length > 5) {
      _mpvErrors.removeAt(0);
    }
    LogService().log('mpv', text);
  }

  String? get lastMpvError => _mpvErrors.isEmpty ? null : _mpvErrors.last;

  /// 起播卡住时的诊断快照（无 hilog 环境下直接展示到屏幕）。
  ///
  /// 覆盖「加载没发生 / 加载了没数据 / 解码失败」三段：
  /// 空闲+播放列表0 = loadfile 未生效；非空闲+缓冲中 = 网络停滞；
  /// 有时长+位置0 = 解码/输出侧问题。
  Future<String> debugSnapshot() async {
    final player = _player;
    if (player == null) return 'mpv: 播放器已销毁';
    final buffer = StringBuffer('mpv诊断:');
    MpvPollResult? s;
    try {
      s = await player.pollState();
    } catch (e) {
      buffer.write(' poll异常:$e');
    }
    try {
      buffer.write(' 初始化+surface=${await player.isReady()}');
    } catch (e) {
      buffer.write(' isReady异常:$e');
    }
    if (s != null) {
      buffer
        ..write(' 时长=${s.durationMs}ms 位置=${s.positionMs}ms')
        ..write(' 空闲=${s.idleActive ? "是" : "否"} 播放列表=${s.playlistCount}')
        ..write(' 视频参数=${s.videoParams != null ? "有" : "无"}')
        ..write(' 暂停=${s.paused} 缓冲中=${s.pausedForCache}');
      if (s.cachePercent >= 0) buffer.write(' 缓冲${s.cachePercent.round()}%');
      if (s.bufferedMs > 0)
        buffer.write(' 已缓冲${(s.bufferedMs / 1000).toStringAsFixed(1)}s');
      final title = s.mediaTitle;
      if (title != null && title.isNotEmpty) {
        buffer.write(
            '\n标题: ${title.length > 40 ? title.substring(0, 40) : title}');
      }
      final path = s.pathMasked;
      if (path != null && path.isNotEmpty) buffer.write('\n地址: $path');
      if (s.gpuContext != null) buffer.write(' gpu-context=${s.gpuContext}');
      if (s.currentVo != null) buffer.write(' vo=${s.currentVo}');
    }
    buffer.write(' hwdec=$_hwdec');
    final actual = _hwdecActual;
    if (actual != null) {
      buffer.write('(实际:${actual.isEmpty ? "无" : actual})');
    }
    // 色彩管线实测回读（v1.2.90）：确认 tone mapping/目标色彩空间真的
    // 生效——修 HDR 发暗时可真机验证，不再靠猜。
    for (final p in const ['tone-mapping', 'target-trc', 'target-peak']) {
      try {
        final v = await player.getProperty(p);
        if (v != null && v.isNotEmpty) buffer.write(' $p=$v');
      } catch (_) {}
    }
    if (_mpvErrors.isNotEmpty) {
      buffer.write('\n最近警告/错误（旧→新）:');
      for (final e in _mpvErrors) {
        buffer.write('\n· ${e.length > 150 ? e.substring(0, 150) : e}');
      }
    }
    return buffer.toString();
  }

  void _handleProperty(MpvPropertyEvent prop) {
    final value = prop.value;
    switch (prop.name) {
      case 'time-pos/full':
        if (value is num) {
          _positionMs = (value * 1000).round();
          _propertyCache['time-pos'] =
              (_positionMs / 1000.0).toStringAsFixed(3);
        }
        break;
      case 'duration/full':
        if (value is num) {
          // 时长首显：事件路径同步更新 mediaInfo 并置 loaded 位。
          _updateDurationMs((value * 1000).round());
          _setStatus(AdapterMediaStatus.loaded |
              AdapterMediaStatus.prepared |
              AdapterMediaStatus.buffered);
        }
        break;
      case 'demuxer-cache-time':
        if (value is num) _bufferedMs = (value * 1000).round();
        break;
      case 'media-title':
        if (value is String) _propertyCache['media-title'] = value;
        break;
      case 'seekable':
        if (value is bool) _propertyCache['seekable'] = value.toString();
        break;
      case 'eof-reached':
        if (value is bool) {
          _propertyCache['eof-reached'] = value.toString();
          _handleEofReached(value);
        }
        break;
      case 'pause':
        if (value is bool) {
          _propertyCache['pause'] = value.toString();
          // 只有已加载媒体后才把 pause 变化映射成播放状态，
          // 否则 open 前的默认 pause 会把状态机打乱。
          if (_prepared) {
            _setState(value
                ? AdapterPlaybackState.paused
                : AdapterPlaybackState.playing);
          }
        }
        break;
      case 'paused-for-cache':
        if (value is bool) {
          _setBuffering(value);
        }
        break;
      case 'video-params':
        _parseVideoParams(value);
        break;
      case 'audio-params':
        _parseAudioParams(value);
        break;
      case 'track-list':
        _parseTracks(value);
        break;
      case 'texture-id':
        // media_kit_video 在视频参数变化时会重建纹理，textureId 随之变化；
        // 必须同步给 UI，否则 Texture 继续引用已注销的旧纹理（黑屏）。
        if (value is int && value > 0 && value != _textureIdListenable.value) {
          _textureIdListenable.value = value;
        }
        break;
    }
  }

  /// 缓冲态位：`paused-for-cache` 为 true 时置 buffering 位，false 时清掉。
  void _setBuffering(bool buffering) {
    if (buffering) {
      _setStatus(_mediaStatus | AdapterMediaStatus.buffering);
    } else {
      _setStatus(AdapterMediaStatus(
        _mediaStatus.rawValue &
            ~(AdapterMediaStatus.buffering.rawValue |
                AdapterMediaStatus.stalled.rawValue),
      ));
    }
  }

  /// 实际生效的硬解器（hwdec-current，轮询直读，非事件）。
  String? _hwdecActual;

  /// 最近一次 track-list JSON 原文（原生 UI 状态转换用）。
  String? _lastTrackListRaw;

  /// 首帧等待状态（v1.2.89）：true = 有视频轨且媒体在播，但视频参数
  /// 尚未到手（解码器起热中）。UI 盖缓冲遮罩用。
  final ValueNotifier<bool> firstFramePending = ValueNotifier<bool>(false);
  bool _videoParamsSeen = false;
  bool _trackHasVideo = false;

  void _updateFirstFramePending(MpvPollResult state) {
    if (state.trackList != null) {
      try {
        final decoded = jsonDecode(state.trackList!);
        _trackHasVideo = decoded is List &&
            decoded.any((t) => t is Map && t['type'] == 'video');
      } catch (_) {}
    }
    final pending = _trackHasVideo &&
        !_videoParamsSeen &&
        (state.durationMs > 0 || state.positionMs > 0);
    if (firstFramePending.value != pending) {
      firstFramePending.value = pending;
    }
  }

  /// 硬解实测监控（v1.2.83）：请求硬解但实际在软解（hwdec-current=no）
  /// 时记录一条线索——软解正是 CPU 发烫的主因。值本身来自内核，
  /// 诊断行展示「请求值(实际: x)」。
  void _trackHwdecActual(String? actual) {
    _hwdecActual = actual;
    if (actual == null) return; // 无视频轨（纯音频/未起播）
    if (actual == 'no' && _hwdec != 'no' && !_hwdecFallbackNoted) {
      _hwdecFallbackNoted = true;
      _noteError('注意：请求硬解($_hwdec)但内核实际在软解（hwdec-current=no），'
          'CPU 解码会导致发热；可尝试切换解码档或渲染档');
    }
  }

  bool _hwdecFallbackNoted = false;

  /// 渲染分辨率封顶（v1.2.93 引入，v1.2.98 分级）：
  /// - SDR：宽 ≤1920（4K 降采样，GPU 带宽减半）；
  /// - HDR/10bit：宽 ≤**1280**——真机日志实锤 HDR10 4K 10bit 下 gpu-next
  ///   反复 GL_OUT_OF_MEMORY（纹理体积是主因），1280 在 GLES 上安全，
  ///   手机屏观感差异极小。视频仍由硬件解码全速解 4K，仅渲染缩小。
  static const int _maxRenderWidthSdr = 1920;
  static const int _maxRenderWidthHdr = 1280;

  void _parseVideoParams(Object? value) {
    if (value is! String) return;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return;
      final w = (decoded['w'] as num?)?.round() ?? 0;
      final h = (decoded['h'] as num?)?.round() ?? 0;
      if (w <= 0 || h <= 0) return;
      final codec = (decoded['codec'] as String?) ?? '';
      _mediaInfo = AdapterMediaInfo(
        duration: _durationMs,
        format: _mediaInfo.format,
        audio: _mediaInfo.audio,
        video: [
          AdapterVideoStream(codec: codec, width: w, height: h),
        ],
        subtitleCount: _mediaInfo.subtitleCount,
      );
      // 渲染分辨率封顶：SDR ≤1920、HDR/10bit ≤1280（GL OOM 根除，
      // v1.2.98；视频仍由硬解全速解原始分辨率，仅渲染缩小）。
      final cap = _hdrContentForMedia ? _maxRenderWidthHdr : _maxRenderWidthSdr;
      var rw = w;
      var rh = h;
      if (rw > cap) {
        rw = cap;
        rh = (h * cap / w).round();
      }
      if (!usesNativeSurface) {
        unawaited(_player?.resizeTexture(rw, rh));
      }
    } catch (_) {}
  }

  void _parseAudioParams(Object? value) {
    if (value is! String) return;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return;
      final codec =
          (decoded['format'] as String?) ?? (decoded['codec'] as String?) ?? '';
      final channels = (decoded['channel-count'] as num?)?.round() ?? 0;
      final sampleRate = (decoded['sample-rate'] as num?)?.round() ?? 0;
      if (codec.isEmpty && channels == 0) return;
      _mediaInfo = AdapterMediaInfo(
        duration: _durationMs,
        format: _mediaInfo.format,
        audio: [
          AdapterAudioStream(
            codec: codec,
            channels: channels,
            sampleRate: sampleRate,
          ),
        ],
        video: _mediaInfo.video,
        subtitleCount: _mediaInfo.subtitleCount,
      );
    } catch (_) {}
  }

  void _parseTracks(Object? value) {
    if (value is! String) return;
    _lastTrackListRaw = value;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return;
      final audioIds = <int>[];
      final subIds = <int>[];
      var subCount = 0;
      for (final track in decoded) {
        if (track is! Map) continue;
        final type = track['type'];
        final id = track['id'];
        if (id is! int) continue;
        if (type == 'audio') {
          audioIds.add(id);
        } else if (type == 'sub') {
          subIds.add(id);
          subCount++;
        }
      }
      if (audioIds.isNotEmpty)
        _audioTrackIds
          ..clear()
          ..addAll(audioIds);
      if (subIds.isNotEmpty)
        _subtitleTrackIds
          ..clear()
          ..addAll(subIds);
      _mediaInfo = AdapterMediaInfo(
        duration: _durationMs,
        format: _mediaInfo.format,
        audio: _mediaInfo.audio,
        video: _mediaInfo.video,
        subtitleCount: subCount,
      );
    } catch (_) {}
  }

  void _handleMpvEvent(MpvEvent event) {
    switch (event.id) {
      case 6: // MPV_EVENT_START_FILE
        _eofReached = false;
        _setStatus(AdapterMediaStatus.loading | AdapterMediaStatus.buffering);
        break;
      case 8: // MPV_EVENT_FILE_LOADED
        _setStatus(AdapterMediaStatus.loaded |
            AdapterMediaStatus.prepared |
            AdapterMediaStatus.buffered);
        break;
      case 21: // MPV_EVENT_PLAYBACK_RESTART
        _setStatus(_mediaStatus |
            AdapterMediaStatus.prepared |
            AdapterMediaStatus.buffered);
        break;
      case 7: // MPV_EVENT_END_FILE
        // mpv 在播完后发 END_FILE；以 eof-reached 区分「自然播完」与
        // 「被 stop/换源打断」，只有前者才置 end（否则会误触发自动下一集）。
        // 时长未知时 _eofReached 已被 _handleEofReached 拦截（v1.2.91）。
        if (_eofReached && _durationMs > 0) {
          _setStatus(_mediaStatus | AdapterMediaStatus.end);
        }
        break;
    }
  }

  // ── 属性通道 ──────────────────────────────────────────────

  @override
  void setProperty(String name, String value) {
    if (_disposed) return;
    _propertyCache[name] = value;
    unawaited(_player?.setProperty(name, value));
  }

  @override
  String? getProperty(String name) => _propertyCache[name];

  @override
  void setHttpHeaders(Map<String, String> headers) {
    _headers = headers;
  }

  /// mpv 的 `hwdec` 取值（由上层 videoDecoders 映射而来）。
  ///
  /// v1.2.96 对齐官方 @ohos/ohos_mpv Demo 的三档语义（真机已验证过
  /// ohcodec：v1.2.78 时代 HDR10 硬解即用此值）：
  /// - 智能 → `auto`      优先硬解，失败自动回退软解
  /// - 硬解 → `ohcodec`   官方 HW+ 档（零拷贝硬解）
  /// - 软解 → `no`        纯软解
  /// 且 hwdec 是**运行时属性**：切换即时生效于当前媒体（官方 Demo 确认
  /// 无需重载流），decoder 在下一帧重建。
  String _hwdec = 'auto';
  String get hwdec => _hwdec;

  @override
  List<String> get videoDecoders =>
      _hwdec == 'no' ? const ['FFmpeg'] : const ['ohcodec'];

  @override
  set videoDecoders(List<String> decoders) {
    if (_disposed) return;
    // 上层的语义（DecodeModeService）：
    //   ['FFmpeg']           → 软解（no）
    //   ['ohcodec']          → 硬解（官方 HW+ 档）
    //   ['ohcodec','FFmpeg'] → 智能（auto，硬解优先软解兜底）
    final hasHw = decoders.any((d) => d.toLowerCase().contains('ohcodec'));
    final hasSw = decoders.any((d) => d.toLowerCase().contains('ffmpeg'));
    final String next;
    if (!hasHw && hasSw) {
      next = 'no';
    } else if (hasHw && !hasSw) {
      next = 'ohcodec';
    } else {
      next = 'auto';
    }
    if (next == _hwdec) return;
    _hwdec = next;
    // 运行时属性：写入即对当前媒体生效（decoder 重建），无需重载流。
    final effective = resolveWindowsHwdec(
      next,
      windows: defaultTargetPlatform == TargetPlatform.windows,
    );
    unawaited(_player?.setProperty('hwdec', effective));
    LogService().log(
        'mpv', '解码器切换 → hwdec=$effective (requested=$next, from $decoders)');
  }

  @override
  List<String> get audioDecoders => const [];

  @override
  set audioDecoders(List<String> decoders) {}

  @override
  set audioBackends(List<String> backends) {}

  @override
  void setBufferRange({int min = -1, int max = -1, bool drop = false}) {
    // mpv 通过原生侧 demuxer-max-bytes / demuxer-max-back-bytes 控制缓冲。
  }

  // ── 字幕 / 截图 ───────────────────────────────────────────

  @override
  Future<void> setMedia(String uri, {required AdapterMediaType type}) async {
    if (_disposed) return;
    if (type == AdapterMediaType.subtitle) {
      await _player?.addSubtitle(_toMpvUri(uri));
    }
  }

  /// 把本地路径转成 mpv 能识别的 URL。
  ///
  /// mpv 的 `sub-add` 接受 URL 或绝对路径，但纯路径在部分构建上会被当作
  /// 相对路径解析失败；统一转成 `file://` URI 最稳。已是 http(s)/file
  /// 协议的原样返回。
  static String _toMpvUri(String raw) {
    final lower = raw.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file://')) {
      return raw;
    }
    // Windows 盘符路径（D:\x\y.srt）与 POSIX 路径统一走 Uri.file。
    try {
      return Uri.file(raw).toString();
    } catch (_) {
      return raw;
    }
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) {
    // mpv `screenshot-raw` 返回 BGRA 原始像素；用 image 包组 PNG
    //（v1.2.83：此前直接返回 null，播放页截图按钮无响应）。
    return _snapshotPng();
  }

  Future<Uint8List?> _snapshotPng() async {
    final player = _player;
    if (player == null) return null;
    final video = _mediaInfo.video;
    final w = video.isNotEmpty ? video.first.width : 0;
    final h = video.isNotEmpty ? video.first.height : 0;
    if (w <= 0 || h <= 0) return null;
    try {
      final bgra = await player.screenshot();
      if (bgra == null || bgra.length < w * h * 4) return null;
      final image = img.Image.fromBytes(
        width: w,
        height: h,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      return Uint8List.fromList(img.encodePng(image));
    } catch (e) {
      LogService().log('mpv', '截图失败: $e');
      return null;
    }
  }

  // ── 原生播放器 UI（计划书 §4/§7）──────────────────────────

  /// 打开原生 UI 宿主（会话确认 Surface 后由 prepare 调用；幂等）。
  Future<void> _openNativeUiIfNeeded() async {
    if (!_nativeUiEnabled || _disposed || _nativeUiController != null) return;
    final platform = MpvSessionPlatform.nativeUiPlatformName;
    if (platform == null) return;
    final controller = NativePlayerController(
      onOpen: (_, __) => MpvSessionPlatform.openNativeUi(),
      onClose: MpvSessionPlatform.closeNativeUi,
      onPush: (state) =>
          MpvSessionPlatform.pushNativeState(jsonEncode(state.toJson())),
      onCommand: _handleNativeUiCommand,
      log: (message) => LogService().log('mpv', message),
    );
    _nativeUiController = controller;
    // 先通知 nativeUiActive=true：PlayerScreen 据此卸载 Flutter 平台视图
    // （其 SurfaceView 销毁、把 surface 让给原生宿主）。若等 open 成功再翻，
    // 两个 SurfaceView 会短暂并存，原生宿主的 surface 事件先到、被当作
    // 重绑目标，随后平台视图销毁又把播放器拆掉 → 黑屏。
    nativeUiActive.value = true;
    // 同步给会话：surface 事件据此按来源（platform/native）过滤，
    // 防止垂死平台视图的 surfaceChanged 把绑定抢回即将销毁的 handle。
    _player?.setNativeUiActive(true);
    try {
      await controller.open(
        platform: platform,
        initial: _buildNativePlayerState(),
        commandStream: MpvSessionPlatform.nativeUiCommandStream(),
      );
      // 事件可能丢（宿主销毁不发回调 / 事件早于监听）：主动按
      // getCurrentSurface 轮询重同步，确保 mpv 绑在原生宿主的 surface 上。
      await _player?.refreshSurface();
    } catch (e) {
      LogService().log('mpv', '原生 UI 打开失败: $e');
      _nativeUiController = null;
      nativeUiActive.value = false;
      _player?.setNativeUiActive(false);
    }
  }

  /// 关闭原生 UI 宿主（公开入口：PlayerScreen 退出路径调用；幂等）。
  Future<void> closeNativeUi() => _closeNativeUi();

  /// 关闭原生 UI 宿主（幂等）。
  Future<void> _closeNativeUi() async {
    final controller = _nativeUiController;
    _nativeUiController = null;
    nativeUiActive.value = false;
    _player?.setNativeUiActive(false);
    if (controller == null) return;
    try {
      await controller.close();
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  /// 推送权威状态到原生宿主（无控制器时快速返回）。
  void _pushNativeUiState({bool immediate = false}) {
    final controller = _nativeUiController;
    if (controller == null || !controller.isOpen || _disposed) return;
    unawaited(
        controller.update(_buildNativePlayerState(), immediate: immediate));
  }

  /// seek 乐观值：本地快照立即跟上目标位置，避免原生进度条回弹到旧值
  ///（权威值仍由轮询/事件回读覆盖）。
  void _nativeUiOptimisticSeek(int positionMs) {
    _positionMs = positionMs;
    _propertyCache['time-pos'] = (positionMs / 1000.0).toStringAsFixed(3);
  }

  /// 把适配器当前状态转成原生 UI 权威快照（计划书 §7.4 数据源）。
  NativePlayerState _buildNativePlayerState() {
    final paused = _state == AdapterPlaybackState.paused ||
        _state == AdapterPlaybackState.stopped;
    final buffering =
        (_mediaStatus.rawValue & AdapterMediaStatus.buffering.rawValue) != 0;
    return NativePlayerState(
      engine: 'mpv',
      videoOutputRequested: _requestedMpvVideoOutput,
      videoOutputActual: mpvActualVideoOutput,
      nativeSurface: usesNativeSurface,
      textureId: _textureIdListenable.value ?? 0,
      hdrOutput: _hdrOutputActive,
      displayHdr: _displayHdr ?? false,
      targetTrc: _targetTrc,
      voConfigured: _voConfigured,
      currentVo: _currentVo,
      hwdecCurrent: _hwdecActual,
      surfaceAttached: _surfaceAttached,
      surfaceId: _surfaceId,
      surfaceError: _surfaceError,
      positionMs: _positionMs,
      durationMs: _durationMs,
      bufferedMs: _bufferedMs,
      paused: paused,
      buffering: buffering,
      ended: _eofReached,
      volume: _volume,
      speed: _playbackRate,
      mediaTitle: _propertyCache['media-title'],
      tracks: _nativeTracksFromRaw(_lastTrackListRaw),
      debugLines: _nativeDebugLines(),
    );
  }

  /// track-list JSON → [NativeTrack] 列表（解析失败返回空）。
  static List<NativeTrack> _nativeTracksFromRaw(String? raw) {
    if (raw == null || raw.isEmpty) return const <NativeTrack>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <NativeTrack>[];
      return decoded
          .whereType<Map>()
          .map((t) => NativeTrack.fromJson(t.map(
                (k, v) => MapEntry(k.toString(), v),
              )))
          .toList(growable: false);
    } catch (_) {
      return const <NativeTrack>[];
    }
  }

  /// 原生 UI 顶部诊断行（vo/hwdec/surface 摘要，Phase 1 最小集）。
  List<String> _nativeDebugLines() {
    final buffer = StringBuffer('vo=${_voConfigured ?? "-"}');
    if (_currentVo != null) buffer.write(' | ${_currentVo}');
    if (_gpuContext != null) buffer.write(' | gpu=$_gpuContext');
    buffer.write(' | hwdec=${_hwdecActual ?? "-"}');
    // 黑屏定性：fps>0=mpv 在出帧（黑屏=呈现问题）；fps=0=解码/vo 问题。
    buffer.write(' | fps=${_videoFps ?? "-"}');
    if (_frameDropCount != null) buffer.write(' drop=$_frameDropCount');
    if (_videoWidth != null && _videoWidth! > 0) {
      buffer.write(' v=${_videoWidth}x$_videoHeight');
    }
    if (!_surfaceAttached) buffer.write(' | surface未附着');
    if (_surfaceError != null) buffer.write(' | err=$_surfaceError');
    if (_hdrOutputActive) buffer.write(' | HDR');
    return <String>[buffer.toString()];
  }

  /// 原生命令路由（计划书 §4.3）：适配器可直接执行的命令在此处理，
  /// 选集/版本/弹幕/房间等需要 PlayerScreen 上下文的命令由上层监听
  /// [NativePlayerController.commands] 处理（Phase 2+ 接入）。
  Future<void> _handleNativeUiCommand(NativePlayerCommand command) async {
    if (_disposed) return;
    switch (command) {
      case TogglePlay():
        state = _state == AdapterPlaybackState.playing
            ? AdapterPlaybackState.paused
            : AdapterPlaybackState.playing;
      case SeekTo(:final positionMs):
        await seek(positionMs: positionMs);
      case SeekRelative(:final deltaMs):
        await seek(positionMs: _positionMs + deltaMs);
      case SetVolume(:final volume):
        this.volume = volume.clamp(0.0, 1.0);
      case SetSpeed(:final speed):
        playbackRate = speed.clamp(0.25, 4.0);
      case RequestBack():
      case RequestExit():
        // 退出动作交给 PlayerScreen（关闭原生宿主 + 退出播放页）。
        final exit = onNativeUiExit;
        if (exit != null) {
          exit();
        } else {
          unawaited(_closeNativeUi());
        }
      default:
        // Phase 2 通用出口：其余命令（选集/版本/音轨/字幕/…）转发给
        // PlayerScreen 路由到现成 handler（见 docs/native_player_command_routing.md）。
        final forward = onNativeUiCommand;
        if (forward != null) {
          await forward(command);
        } else {
          LogService().log('mpv',
              '原生命令待接入 PlayerScreen: ${command.toMap()['type']}');
        }
    }
    if (command.requiresImmediatePush) {
      _pushNativeUiState(immediate: true);
    }
  }

  // ── 生命周期 ──────────────────────────────────────────────

  @override
  void dispose() => unawaited(disposeAsync());

  @override
  Future<void> disposeAsync() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    final future = _disposeImpl();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeImpl() async {
    // 先置销毁位：此后所有 setter / 属性回调直接忽略。
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await _rawSub?.cancel();
    } catch (_) {}
    _rawSub = null;

    // 原生 UI 宿主随会话销毁（幂等；先于 mpv dispose，避免子窗口
    // XComponent 引用已销毁的 surface）。
    await _closeNativeUi();
    onNativeUiExit = null;

    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.dispose().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    _textureIdListenable.value = null;
    try {
      firstFramePending.value = false;
      firstFramePending.dispose();
    } catch (_) {}
    try {
      nativeUiActive.value = false;
      nativeUiActive.dispose();
    } catch (_) {}
    try {
      await _stateCtrl?.close();
    } catch (_) {}
    try {
      await _statusCtrl?.close();
    } catch (_) {}
    try {
      await _eventCtrl?.close();
    } catch (_) {}
    _stateCtrl = null;
    _statusCtrl = null;
    _eventCtrl = null;
    _textureIdListenable.dispose();
  }

  // ── 内部辅助 ──────────────────────────────────────────────

  void _setState(AdapterPlaybackState s) {
    if (_state == s) return;
    final old = _state;
    _state = s;
    _stateCtrl?.add((oldValue: old, newValue: s));
  }

  void _setStatus(AdapterMediaStatus s) {
    if (_mediaStatus.rawValue == s.rawValue) return;
    final old = _mediaStatus;
    _mediaStatus = s;
    _statusCtrl?.add((oldValue: old, newValue: s));
  }
}
