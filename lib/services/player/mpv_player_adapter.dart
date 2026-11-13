import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:himi_mpv_android/himi_mpv_android.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';
import 'package:himi_syncwatch/models/app_settings.dart' show AppSettings;
import 'mpv_session_platform.dart';
import '../danmaku/danmaku_comment.dart';
import 'native/native_player_command.dart';
import 'native/native_player_controller.dart';
import 'native/native_player_gating.dart';
import 'native/native_player_state.dart';
import 'package:himi_syncwatch/services/decode_mode_service.dart';
import 'package:himi_syncwatch/services/debug/debug_metrics.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:image/image.dart' as img;

import 'player_adapter.dart';

/// 把应用层的硬解档位映射为 Windows libmpv 的 `hwdec` 值。
///
/// Windows 原生的 d3d11va 零拷贝互操作在部分显卡驱动上会在首帧前崩溃，
/// 统一走 copy-back 更稳；纯软解保持 `no`。非 Windows 不做转换。
String resolveWindowsHwdec(String mode, {required bool windows}) {
  // 内部语义（本文件的 `_hwdec` 取值）：
  //   'no'   → 纯软解
  //   'hw'   → 纯硬解（不回退）        ← 640 新增
  //   'auto' → 硬解优先、软解兜底
  //
  // 映射到 mpv 的合法 `hwdec` 取值（'hw' 不是 mpv 认的值，直接传会导致
  // 解码器初始化失败）。mpv 的 `auto-safe` 语义 = 只用白名单内的硬解器、
  // 不做软解兜底，正是「纯硬解」。
  if (mode == 'hw') return windows ? 'auto-copy-safe' : 'auto-safe';
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

  /// 656：当前媒体是否 HDR（只读，供 Qt 播放器启动时传参）。
  bool get isHdrContent => _hdrContentForMedia;

  /// 656：当前媒体是否 HLG（只读，供 Qt 播放器启动时传参）。
  bool get isHlgContent => _hlgContentForMedia;

  /// 697：当前媒体是否为杜比视界内容。
  ///
  /// 【为什么要单独标记】DV 的 tone-mapping 需求与普通 HDR10 不同：
  /// - **HDR10**：静态元数据（整片一个峰值），`clip` 硬裁切影响有限
  /// - **DV**：动态元数据（逐场景峰值），必须用 `bt.2390` 感知映射 +
  ///   `hybrid` 模式，否则高光细节大量丢失、暗部发灰
  ///
  /// 【处理链路】DV 元数据由 FFmpeg 解析（安卓侧有
  /// `android-mediacodec-dovi.patch` 补丁），`gpu-next` 内置的
  /// libplacebo 消费它做动态映射。**不要额外加 `vf=libplacebo`**——
  /// 那是把 HDR 转 SDR 的滤镜方案（media_kit 用 Flutter 纹理时的妥协），
  /// 我们三平台都是直出，加 vf 会自废 HDR 直出能力。
  bool _dvContentForMedia = false;
  set dvContent(bool value) {
    if (_dvContentForMedia == value) return;
    _dvContentForMedia = value;
    unawaited(_refreshHdrOutputForCurrentSession());
  }

  /// 697：当前媒体是否杜比视界（只读）。
  bool get isDvContent => _dvContentForMedia;

  /// SDR 纹理链路不可用时强制原生 Surface。
  bool _forceNativeSurface = false;
  set forceNativeSurface(bool value) => _forceNativeSurface = value;

  /// MPV 视频路径设置：surface/texture。仅 MPV 生效。
  String _mpvVideoOutput = MpvOutputPolicy.surface;
  bool _mpvVideoOutputUserSet = false;

  /// 655：Android Surface 路径的渲染器（'auto' / 'gpu-next' / 'gpu'）。
  ///
  /// 由 `AppSettings.mpvRenderer` 经播放页注入。
  ///
  /// 697：移除 `auto` 档（运行时本就等价 `gpu-next`），默认直接
  /// `gpu-next`；`gpu` 用于老 GPU 兼容。见 `AppSettings.mpvRenderer`
  /// 注释里对「删除 GLES 自动探测」的说明。
  String _mpvRenderer = AppSettings.defaultMpvRenderer;
  set mpvRenderer(String value) => _mpvRenderer = value;

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

  /// 697：调试面板——实际 vo / gpu-context（最近一次轮询）。
  String? get mpvCurrentVo => _currentVo;
  String? get mpvGpuContext => _gpuContext;

  /// 697：最近一次解析的输入色彩信息（`video-params`）。
  ///
  /// 调试面板与原生 UI 共用——避免两处各自解析 `video-params` 导致
  /// 显示不一致（HDR 排查最忌讳「两个面板说不同的数」）。
  VideoColorInfo? _colorInfo;
  VideoColorInfo? get colorInfo => _colorInfo;

  /// 697：最近一次直读的 mpv 调试属性（HDR/DV 相关）。
  ///
  /// 【必须随轮询刷新】旧实现只在调试面板采集时赋值，而原生 UI 的状态
  /// 推送（`buildNativePlayerState`）从 `_debugProps` 取值 → 面板没开时
  /// 这些字段恒为空（真机截图：`目标`/`映射`/`编码`/`gpu-api` 全空）。
  Map<String, String> _debugProps = const {};
  Map<String, String> get debugProps => _debugProps;

  /// 697：最近一次实际下发的 `target-prim`（`_debugProps` 为空时兜底）。
  String? _targetPrim;

  /// 697：最近一次实际下发的 `tone-mapping`（同上）。
  String? _targetToneMapping;

  /// 697：Emby 元数据声明的杜比视界 Profile（0 = 非 DV / 未知）。
  ///
  /// mpv 的 `current-tracks/video/dolby-vision-profile` 在部分构建
  /// （鸿蒙/安卓自建 libmpv）读不到，此时用 Emby 的静态声明兜底，
  /// 避免面板把 P5 显示成「非 DV 内容」。
  int _embyDoviProfile = 0;
  int get embyDoviProfile => _embyDoviProfile;
  set embyDoviProfile(int value) => _embyDoviProfile = value;

  /// 697：原生 UI 需要的输出/管线属性清单。
  ///
  /// 与 [VideoColorInfo.propertyNames]（输入色彩）分开：这些是「我们怎么
  /// 渲染的」，不需要 1s 级刷新，2s 一次足够。
  static const _nativeDebugPropertyNames = <String>[
    ...VideoColorInfo.propertyNames,
    'target-prim',
    'target-trc',
    'target-peak',
    'tone-mapping',
    'tone-mapping-mode',
    'hdr-compute-peak',
    'gpu-api',
    'gpu-context',
    'video-format',
    'hwdec-current',
    'estimated-vf-fps',
    'frame-drop-count',
    'decoder-frame-drop-count',
  ];

  /// 697：低频刷新 [_debugProps]（原生 UI 状态推送的数据源）。
  ///
  /// 【为什么必须自动跑】旧实现只在调试面板采集时赋值，而
  /// `buildNativePlayerState()` 从这里取值 → 面板没开时
  /// `目标`/`映射`/`编码`/`gpu-api` 恒为空（真机截图实证）。
  ///
  /// 2s 一次：14 次跨进程属性读，频率再高没有收益。
  void _startNativeDebugRefresh() {
    _nativeDebugTimer?.cancel();
    _nativeDebugTimer =
        Timer.periodic(const Duration(seconds: 2), (_) {
      if (_disposed || _player == null) return;
      unawaited(readDebugProperties(_nativeDebugPropertyNames));
    });
    // 立即跑一次，避免起播后前 2s 面板空白
    unawaited(readDebugProperties(_nativeDebugPropertyNames));
  }

  void _stopNativeDebugRefresh() {
    _nativeDebugTimer?.cancel();
    _nativeDebugTimer = null;
  }

  Timer? _nativeDebugTimer;

  /// 697：调试面板——读取 mpv 实时属性（异步直读，非缓存）。
  ///
  /// 【为什么需要】HDR/DV 排查依赖 `video-params`（输入色彩元数据）、
  /// `tone-mapping` / `target-prim` / `target-trc`（输出映射）等属性，
  /// 这些没有走事件订阅，只能按需直读。面板刷新频率低（1s），开销可忽略。
  ///
  /// 单个属性读取失败静默跳过（不同 mpv 版本支持的属性不同）。
  Future<Map<String, String>> readDebugProperties(
    List<String> names,
  ) async {
    final player = _player;
    final out = <String, String>{};
    if (player == null) return out;
    for (final name in names) {
      try {
        final v = await player.getProperty(name);
        if (v != null && v.isNotEmpty) out[name] = v;
      } catch (_) {}
    }
    // 697：缓存最近一次结果——原生 UI 状态下发时复用，避免重复 IPC，
    // 也保证「Flutter 面板」与「原生面板」显示同一份数据。
    _debugProps = out;
    // 标量子属性优先（鸿蒙/安卓可读），整块 JSON 只在 NODE 可读时兜底
    _colorInfo = VideoColorInfo.fromProperties(out) ??
        (out['video-params'] != null
            ? VideoColorInfo.tryParse(out['video-params'])
            : null);
    return out;
  }

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

  /// 655：**已移除** 640 的 surface 渲染失败回调。
  ///
  /// 旧字段 `onSurfaceRenderFailed` 用于「检测到 EGL 失败就持久化
  /// texture 输出」，现已删除——视频路径改为纯手动设置（见
  /// `MpvSessionPlatform` / 插件类注释）。保留此说明避免将来重复引入。

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

  /// 画面比例 → mpv 显示属性（真机回归：原生 UI 下 _videoFit 只改图标，
  /// 画面纹丝不动 →「点了没反应」。BoxFit 语义必须落到 mpv 属性）：
  /// - contain 自适应：keepaspect 保持宽高比完整显示（letterbox）；
  /// - cover 裁剪：panscan=1 裁边填满；
  /// - fill 铺满：keepaspect=no 拉伸变形；
  /// - none 原始：video-unscaled=yes 1:1 像素。
  ///
  /// 注意：**不设** video-aspect-override——该属性取值语义随 mpv 版本漂移
  ///（-1/no/0），设错会把画面拉变形（真机「竖屏比例不对」的高危源）。
  /// keepaspect 自带按元数据显示宽高比（含旋转元数据）。
  Future<void> applyVideoFit(String fit) async {
    final player = _player;
    if (player == null) return;
    final props = switch (fit) {
      'cover' => <String, String>{
          'keepaspect': 'yes',
          'panscan': '1.0',
          'video-unscaled': 'no',
        },
      'fill' => <String, String>{
          'keepaspect': 'no',
          'panscan': '0',
          'video-unscaled': 'no',
        },
      'none' => <String, String>{
          'video-unscaled': 'yes',
          'panscan': '0',
        },
      _ => <String, String>{
          'keepaspect': 'yes',
          'panscan': '0',
          'video-unscaled': 'no',
        },
    };
    for (final entry in props.entries) {
      try {
        await player.setProperty(entry.key, entry.value);
      } catch (e) {
        LogService().log('mpv', 'applyVideoFit ${entry.key}=${entry.value} 失败: $e');
      }
    }
    LogService().log('mpv', 'applyVideoFit=$fit → $props');
  }

  /// 应用 fit 后重同步 surface 尺寸（594）。
  ///
  /// 【真机「全屏控件失效」】`applyVideoFit` 只写 mpv 属性
  /// （`keepaspect`/`panscan`/`video-unscaled`），但 letterbox 依赖 surface
  /// 的**当前尺寸**。分栏刚切换时 surface 窗 `setLayout` 是异步生效的：
  /// 属性已改、尺寸还没到 → 画面按旧尺寸裁切，看起来「没全屏」。
  ///
  /// 这里补一次 surface 重同步，让 fit 落在最新尺寸上。
  Future<void> refreshSurfaceAfterFit() async {
    try {
      await _player?.refreshSurface();
    } catch (e) {
      LogService().log('mpv', 'refreshSurfaceAfterFit 失败: $e');
    }
  }

  /// 646：同步原生顶层窗口几何（Windows HDR 直出模式）。
  ///
  /// 视频渲染在独立 `WS_POPUP` 顶层窗口里，不在 Flutter 布局树内，
  /// 故播放页几何变化（拖动/缩放/全屏/分栏）时必须显式驱动。
  Future<void> updateHostGeometry({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    final session = _player;
    if (session == null || session is! MpvHostWindowSession) return;
    final host = session as MpvHostWindowSession;
    try {
      await host.updateHostGeometry(
        x: x,
        y: y,
        width: width,
        height: height,
      );
    } catch (e) {
      LogService().log('mpv', 'updateHostGeometry 失败: $e');
    }
  }

  /// 648：原生窗口事件流（关闭/按键/点击）。
  ///
  /// 独立窗口独占焦点，Flutter 收不到这些输入，必须由原生转发后在此
  /// 交给播放页处理（离房确认 / 播放暂停 / seek / 全屏 / 控件显隐）。
  Stream<Map<Object?, Object?>> get hostEvents {
    final session = _player;
    if (session == null || session is! MpvHostWindowSession) {
      return const Stream<Map<Object?, Object?>>.empty();
    }
    return (session as MpvHostWindowSession).hostEvents;
  }

  Future<void> _applyHdrOutputProperties(bool enabled) async {
    final player = _player;
    if (player == null) return;
    _targetTrc = enabled ? (_hlgContentForMedia ? 'hlg' : 'pq') : 'auto';
    // 697：DV 用感知映射（bt.2390 + hybrid），普通 HDR10 保持 clip。
    //
    // 【为什么 DV 不能继续用 clip】DV 是**动态元数据**（逐场景峰值），
    // `clip` 按单一峰值硬裁切 → 高光细节丢失、暗部发灰。`bt.2390`
    // 是感知映射曲线，`hybrid` 模式同时考虑亮度与色彩，是 DV 的
    // 标准做法（与 media_kit 路径的 `tonemapping=bt.2390` 一致）。
    final toneMapping = _dvContentForMedia ? 'bt.2390' : 'clip';
    final props = enabled
        ? <String, String>{
            'target-colorspace-hint': 'yes',
            'target-prim': 'bt.2020',
            'target-trc': _hlgContentForMedia ? 'hlg' : 'pq',
            'hdr-compute-peak': 'auto',
            'tone-mapping': toneMapping,
            if (_dvContentForMedia) 'tone-mapping-mode': 'hybrid',
            if (defaultTargetPlatform == TargetPlatform.windows)
              'd3d11-output-format': 'rgb10_a2',
          }
        : <String, String>{
            'target-colorspace-hint': 'no',
            'target-prim': 'auto',
            'target-trc': 'auto',
            // SDR 输出：HDR/DV 内容都走感知映射（避免降级观感发灰）。
            // 显式设置而不是条件设置——否则切到 SDR 片源时会残留上一次
            // 的 tone-mapping（mpv 属性是持久的），诊断面板也会显示错值。
            'tone-mapping': toneMapping,
            'tone-mapping-mode': _dvContentForMedia ? 'hybrid' : 'auto',
            if (defaultTargetPlatform == TargetPlatform.windows)
              'd3d11-output-format': 'auto',
          };
    // 记录实际下发的值——原生 UI 在调试面板未开启时靠它兜底显示
    //（否则 `目标` / `映射` 两行恒为空）。
    _targetPrim = props['target-prim'];
    _targetToneMapping = props['tone-mapping'];
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
        // 697：DV 内容传给原生层，决定 tone-mapping 策略
        //（bt.2390 + hybrid，而非 clip）。
        dv: _dvContentForMedia,
        // 655：渲染器由设置决定（Android Surface 路径）。
        vo: AppSettings.resolveMpvVo(
          renderer: _mpvRenderer,
          nativeSurface: nativeSurface,
        ),
      );
      if (_disposed) {
        // 创建期间已被销毁：立刻回收，避免泄漏。
        unawaited(player.dispose());
        return;
      }
      _player = player;
      // Android 会话的诊断日志接到 LogService（进 App 调试面板 + 落盘 +
      // logcat），否则 surface 事件时序完全不可见（黑屏盲区）。
      //
      // 655：不再接 `onSurfaceRenderFailed`（该回调已随自动回退一起删除）。
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
    // 转圈看门狗复位（589）：新文件重新计时。
    _loadingWatchdogFired = false;

    // 启动轮询兜底：mpv 的事件/属性回调经 JSBind 绑定，在部分设备上
    // 可能完全不送达（表现为纹理有了但时长/分辨率永远为空 → 无限转圈）。
    // 轮询与事件流并行，谁先到用谁，互相补齐。
    _startPolling();
    // 697：原生 UI 的输出/管线属性（2s 低频）——面板未开启也要跑，
    // 否则 `buildNativePlayerState` 的相关字段恒为空。
    _startNativeDebugRefresh();
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
    // 626：`video-params` 在鸿蒙上**读不到**（NODE 属性，`getPropertyString`
    // 返回空串），`_parseVideoParams` 永不触发 → `_lastVideoW/H` 恒为 0
    // → 鸿蒙原生 UI 的 `videoFitW/H()` 返回 -1 → XComponent 回落 100%
    // 撑满 → 画布仍然拉伸（真机回归）。
    //
    // 这里用 `pollState` 的 `videoWidth`/`videoHeight`（走 `width`/`height`
    // 标量属性，鸿蒙可读）做兜底——`hasVideoFrame` 早就用它做「首帧已出」
    // 判据（588），只是没同步给 `_lastVideoW/H`。
    if ((state.videoWidth ?? 0) > 0 && (state.videoHeight ?? 0) > 0) {
      _lastVideoW = state.videoWidth!;
      _lastVideoH = state.videoHeight!;
    }
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
    // 画面已出的第二判据（588）：`video-params` 在鸿蒙上常读不到——它是
    // NODE 类型属性，`getPropertyString` 返回空串，而 `width`/`height` 可读。
    // 只认 video-params 会让 `_videoParamsSeen` 永远 false：
    // ① 播放中一直转圈（showLoading 恒真）；
    // ② 3 秒后被 `_maybeFallbackToSoftwareDecode` 误判「有声无画」→ 强制
    //    切软解重载（真机「播一会儿闪一下重新加载」）。
    if (hasVideoFrame(state)) _videoParamsSeen = true;
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
    } else if (state.bufferedMs > 0 || state.positionMs > 0) {
      // 588：位置已推进也是「在出帧」的铁证。鸿蒙 `demuxer-cache-time`
      // 常读不到（bufferedMs 恒 0），只看它会让缓冲位卡住 → 播放中一直
      // 转圈。
      _setBuffering(false);
    }
    if (_prepared && hasProgress) {
      _setState(state.paused
          ? AdapterPlaybackState.paused
          : AdapterPlaybackState.playing);
    }
    _maybeKickStalledLoad(state);
    _maybeFallbackToSoftwareDecode(state);
    // 转圈看门狗（589）：在播且位置已推进 ≥3s 即永久收起加载指示器。
    // 位置推进不依赖任何视频属性（video-params/width/fps 都可能读不到），
    // 是「媒体真的在跑」最可靠的证据。
    if (!_loadingWatchdogFired &&
        MpvPlayerAdapter.shouldFireLoadingWatchdog(
          state: _state,
          positionMs: _positionMs,
        )) {
      _loadingWatchdogFired = true;
      LogService().log('mpv', '转圈看门狗触发（position=${_positionMs}ms）');
    }
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
    if (state.videoParams != null || hasVideoFrame(state) || state.idleActive) {
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

  /// 选集/版本列表：PlayerScreen 注入（Emby 元数据，非 mpv 轨道），
  /// 纳入原生状态推送，供选集/线路面板展示。见 _buildNativePlayerState。
  List<NativeEpisode> _nativeEpisodes = const <NativeEpisode>[];

  /// Emby 轨显示名（`MediaStream.displayInfo`，按 Emby 流序；见
  /// [applyNativePanelData]）。空 = 不挂 label，原生回退 title/lang。
  List<String> _nativeAudioLabels = const <String>[];
  List<String> _nativeSubtitleLabels = const <String>[];
  List<NativeVersion> _nativeVersions = const <NativeVersion>[];
  int _nativeCurrentEpisodeIndex = -1;
  int _nativeCurrentVersionIndex = 0;

  /// 控制层布局/样式附加状态（设置、锁定、网速、字幕/弹幕参数等）。
  NativePlayerUiExtras _nativeUiExtras = const NativePlayerUiExtras();

  /// PlayerScreen 注入控制层附加状态（整体替换后立即推送）。
  void setNativeUiExtras(NativePlayerUiExtras extras) {
    _nativeUiExtras = extras;
    _pushNativeUiState();
  }

  /// 主动立即推送一次权威快照（设置变化/锁定/切集后调用）。
  void refreshNativeUiState() {
    _pushNativeUiState(immediate: true);
  }

  /// 批量注入控制层数据（选集/线路/附加状态），只推送一次快照。
  void applyNativePanelData({
    required List<NativeEpisode> episodes,
    required List<NativeVersion> versions,
    required int currentEpisodeIndex,
    required int currentVersionIndex,
    required NativePlayerUiExtras extras,
    List<String> audioLabels = const <String>[],
    List<String> subtitleLabels = const <String>[],
  }) {
    _nativeEpisodes = episodes;
    _nativeVersions = versions;
    _nativeCurrentEpisodeIndex = currentEpisodeIndex;
    _nativeCurrentVersionIndex = currentVersionIndex;
    _nativeUiExtras = extras;
    // Emby 显示名（MediaStream.displayInfo）按 Emby 流序注入，构建快照时
    // 挂到对应 mpv 轨上——面板命名与 Emby 一致（真机回归：旧实现只用
    // mpv title/lang，显示 `chi`/`轨 2`）。
    _nativeAudioLabels = audioLabels;
    _nativeSubtitleLabels = subtitleLabels;
    _pushNativeUiState();
    // 画面比例落 mpv 属性（引擎切换/重载会重置属性，这里兜底重放）。
    if (extras.videoFit != _appliedVideoFit) {
      _appliedVideoFit = extras.videoFit;
      unawaited(applyVideoFit(extras.videoFit));
    }
  }

  /// 最近一次落到 mpv 的画面比例（避免重复设置）。
  String _appliedVideoFit = '';

  /// 最近解析的显示宽高（旋转互换后；尺寸变化重放 fit 的判据）。
  int _lastVideoW = 0;
  int _lastVideoH = 0;

  /// 弹幕全量列表（PlayerScreen 解析后注入；原生 UI 的弹幕渲染数据源）。
  List<DanmakuComment> _nativeDanmakuComments = const [];

  /// 注入弹幕全量（原生 UI 打开期间由 [_buildDanmakuWindow] 切窗推送）。
  set nativeDanmakuComments(List<DanmakuComment> comments) {
    _nativeDanmakuComments = comments;
    _pushNativeUiState();
  }

  /// 弹幕时间窗：[当前位置-保留时长, 当前位置+30s]，原生端按 timeMs 自调度。
  /// 纯位置推导，seek 后自然对齐（与 Flutter DanmakuTimeline 语义一致）。
  ///
  /// 【保留时长必须覆盖整段驻留/穿屏】滚动 8s÷speed、驻留 4s。旧下界
  /// `pos-2s` 会把刚入屏 2 秒的滚动弹幕移出数据源 → 滚到一半就消失
  ///（真机回归）。
  List<NativeDanmakuItem> _buildDanmakuWindow() {
    if (_nativeDanmakuComments.isEmpty) return const [];
    var comments = _nativeDanmakuComments;
    // 屏蔽链（588）：与 Flutter `DanmakuTimeline._filter` 逐条同序 ——
    // 顶/底屏蔽 → 屏蔽词（子串）→ 数量采样 → 时间升序。
    //
    // 旧实现只做数量采样 + 时间窗，屏蔽完全没生效：原生 UI 下 Flutter 弹幕层
    // 随视频区退场，屏蔽词/顶底开关在安卓与鸿蒙原生弹幕上全部失效（真机回归）。
    final blockTop = _nativeUiExtras.danmakuBlockTop;
    final blockBottom = _nativeUiExtras.danmakuBlockBottom;
    final blockWords = _nativeUiExtras.danmakuBlockWords;
    if (blockTop || blockBottom || blockWords.isNotEmpty) {
      comments = comments.where((c) {
        if (blockTop && c.mode == DanmakuMode.top) return false;
        if (blockBottom && c.mode == DanmakuMode.bottom) return false;
        for (final word in blockWords) {
          if (word.isNotEmpty && c.text.contains(word)) return false;
        }
        return true;
      }).toList(growable: false);
    }
    // 数量上限：超量按时间等间隔采样（照抄 Flutter DanmakuTimeline._sampleEvenly：
    // 排序后确定性采样、保留首条）。在窗口切片前对全量采样 = 与 Flutter 全局
    // 采样语义一致，且样本稳定（弹幕不会中途互换进出，防闪烁）。
    final maxCount = _nativeUiExtras.danmakuMaxCount;
    if (maxCount != null && maxCount > 0 && comments.length > maxCount) {
      final sorted = [...comments]..sort((a, b) => a.time.compareTo(b.time));
      final total = sorted.length;
      final sampled = <DanmakuComment>[];
      for (var i = 0; i < maxCount; i++) {
        sampled.add(sorted[(i * total) ~/ maxCount]);
      }
      comments = sampled;
    }
    final posSec = _positionMs / 1000.0;
    final speed = _nativeUiExtras.danmakuSpeed.clamp(0.25, 4.0);
    final travelSec = 8.0 / speed;
    final keepSec = (travelSec > 4.0 ? travelSec : 4.0) + 2.0;
    final out = <NativeDanmakuItem>[];
    for (final c in comments) {
      if (c.time < posSec - keepSec || c.time > posSec + 30) continue;
      out.add(NativeDanmakuItem(
        timeMs: (c.time * 1000).round(),
        text: c.text,
        mode: switch (c.mode) {
          DanmakuMode.top => 'top',
          DanmakuMode.bottom => 'bottom',
          DanmakuMode.scroll => 'scroll',
        },
        color: '#${c.color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
      ));
    }
    // 时间升序（588）：原生行分配必须按时间序增量推进（与 Flutter/鸿蒙
    // `sort(timeMs)` 一致）。旧实现保持原始顺序 → 行冲突表按乱序推进，
    // 后到的早弹幕抢不到行被误丢、已入屏的被重排到别的行（整屏跳行）。
    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }

  /// PlayerScreen 注入选集列表（内容/剧集变化时调用）。
  set nativeEpisodes(List<NativeEpisode> episodes) {
    _nativeEpisodes = episodes;
    _pushNativeUiState();
  }

  /// PlayerScreen 注入版本/线路列表（媒体源变化时调用）。
  set nativeVersions(List<NativeVersion> versions) {
    _nativeVersions = versions;
    _pushNativeUiState();
  }

  /// 当前选集下标（-1 = 未定）。
  set nativeCurrentEpisodeIndex(int index) {
    _nativeCurrentEpisodeIndex = index;
    _pushNativeUiState();
  }

  /// 当前版本/线路上标。
  set nativeCurrentVersionIndex(int index) {
    _nativeCurrentVersionIndex = index;
    _pushNativeUiState();
  }

  /// mpv `track-list` 里音轨/字幕轨的 id（1-based，按出现顺序）。
  ///
  /// 上层的 `activeAudioTracks`/`activeSubtitleTracks` 传的是 **Emby 流索引**
  /// （0-based，与 Emby 元数据数组对齐），而 mpv 的 `aid`/`sid` 是它自己的
  /// track id。两者必须映射，否则选第 2 条字幕会切到别的轨。
  ///
  /// 【617 真机回归：面板选中的字幕/音频与实际不一致】映射表此前**恒为空**
  /// （见 [_parseTracks] 的三处缺陷），选轨永远退回「Emby 索引 + 1」兜底；
  /// 而安卓 `setAudioTrack(id)` 把该值当 **1-based 数组下标**用，media_kit
  /// 的 `tracks` 又前置 `[auto, no]` 两条伪轨 → 选第 1 条实际落到 `auto`
  ///（mpv 自选），选第 2 条落到 `no`（关闭）。这就是「选的和实际不一致」。
  ///
  /// 现统一语义：**这里始终传真实 mpv track id**（映射成功时取表内 id，
  /// 未就绪时退回 1-based 序号），两端平台按「真实轨 id」或「第 N 条真实轨」
  /// 解析，顺序严格跟随 Emby 服务端流顺序。
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
    if (tracks.isEmpty) {
      // 空列表 = 关闭音频（与字幕同语义；旧实现直接 return 会静默忽略）。
      unawaited(_player?.setAudioTrack(0));
      return;
    }
    final index = tracks.first;
    final trackId = _mapIndexToTrackId(_audioTrackIds, index);
    // 轨道表未就绪（文件刚 open）时按 Emby 序号 +1 兜底（平台侧按
    // 「第 N 条真实轨」解析，跳过 auto/no 伪轨）。
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


  /// 首帧等待状态（v1.2.89）：true = 有视频轨且媒体在播，但视频参数
  /// 尚未到手（解码器起热中）。UI 盖缓冲遮罩用。
  final ValueNotifier<bool> firstFramePending = ValueNotifier<bool>(false);
  bool _videoParamsSeen = false;
  bool _trackHasVideo = false;

  /// 是否已拿到可用画面尺寸（= 首帧已出，渲染层已配置好视频轨）。
  ///
  /// 588：作为「画面已出」的**独立**判据，与 `video-params` 字符串并列。
  /// 鸿蒙 `video-params`（NODE 属性）经 `getPropertyString` 常读不到，但
  /// `width`/`height` 可读——只靠 video-params 会永远判「首帧未出」。
  ///
  /// 589：再加 `estimated-vf-fps > 0` 作为第三判据——它表示 mpv **确实在
  /// 持续出帧**，比尺寸更直接（某些设备连 `width`/`height` 也读不到）。
  @visibleForTesting
  static bool hasVideoFrame(MpvPollResult state) =>
      ((state.videoWidth ?? 0) > 0 && (state.videoHeight ?? 0) > 0) ||
      (state.videoFps ?? 0) > 0;

  /// 画面是否已出（供跳过片头/片尾提示门禁）。
  ///
  /// 「首帧未出」时不弹跳过提示：此时进度可能已推进（音频先出），
  /// 但用户看到的还是黑屏/转圈，弹「跳过片头」属于时机不对。
  bool get firstFrameReady => !firstFramePending.value;

  /// 转圈看门狗：在播且位置已推进超过该时长即强制收起加载指示器。
  ///
  /// 589：所有「首帧已出」判据都依赖内核属性可读；只要有一条读不到就会
  /// 永久转圈。看门狗是最后一道保险——位置推进是**不依赖任何视频属性**
  /// 的铁证（有进度就说明媒体真的在跑）。
  @visibleForTesting
  static const int loadingWatchdogMs = 3000;

  /// 看门狗是否应触发（纯函数，供测试）。
  @visibleForTesting
  static bool shouldFireLoadingWatchdog({
    required AdapterPlaybackState state,
    required int positionMs,
  }) =>
      state == AdapterPlaybackState.playing && positionMs >= loadingWatchdogMs;

  /// 看门狗已触发（本集内一旦触发不再回退，避免缓冲期又闪出转圈）。
  bool _loadingWatchdogFired = false;

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
    // 697：同步缓存输入色彩信息（HDR/DV 排查的「输入」层）。
    //
    // 【为什么在这里更新而不是只在采集时】`video-params` 是事件驱动的，
    // 视频参数一变就到达。原生 UI 的状态推送（`buildNativePlayerState`）
    // 读的就是 `_colorInfo`——只在调试面板采集时更新会导致「面板没开时
    // 原生面板永远显示上一次的值」。
    _colorInfo = VideoColorInfo.tryParse(value);
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return;
      var w = (decoded['w'] as num?)?.round() ?? 0;
      var h = (decoded['h'] as num?)?.round() ?? 0;
      if (w <= 0 || h <= 0) return;
      // 旋转元数据：mpv 显示时自动转 90/270 → UI 宽高互换（诊断/letterbox
      // 计算用显示宽高；真机回归「竖屏视频比例不对」的元数据来源）。
      final rotate = ((decoded['rotate'] as num?)?.round() ?? 0) % 360;
      if (rotate == 90 || rotate == 270) {
        final t = w;
        w = h;
        h = t;
      }
      // 尺寸变化（含旋转翻转）后重放画面比例——引擎重载/旋转会重置 mpv 属性。
      final dimsChanged = _lastVideoW != w || _lastVideoH != h;
      if (dimsChanged && _lastVideoW > 0 && _appliedVideoFit.isNotEmpty) {
        unawaited(applyVideoFit(_appliedVideoFit));
      }
      _lastVideoW = w;
      _lastVideoH = h;
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

  /// 解析 `track-list` → 音轨/字幕轨的 mpv track id（按**出现顺序**）。
  ///
  /// 【617 真机回归：面板选中的字幕/音频与实际不一致】
  ///
  /// 旧实现有三处缺陷，导致映射表恒为空、选轨退回「Emby 索引 + 1」兜底：
  /// 1. `if (decoded is! List) return`——安卓 `getTracks()` 返回的是**分组
  ///    Map**（`{video:[], audio:[], subtitle:[]}`），不是 mpv 原生 List，
  ///    直接 return → 整段跳过；
  /// 2. `if (id is! int) continue`——media_kit 的 `_Track.id` 是 **String**，
  ///    即使结构对上也会被全部跳过；
  /// 3. `catch (_) {}`——失败静默，真机无从诊断（本 bug 潜伏的根因）。
  ///
  /// 现同时兼容两平台结构，并把 id 统一转 int（保留出现顺序 =
  /// **Emby 服务端流顺序**，见 `_mapIndexToTrackId`）。
  void _parseTracks(Object? value) {
    if (value is! String) return;
    try {
      final decoded = jsonDecode(value);
      final audioIds = <int>[];
      final subIds = <int>[];

      void take(Object? track, String type) {
        if (track is! Map) return;
        // media_kit 的 id 是 String；鸿蒙 mpv 原生 track-list 是 int。
        final raw = track['id'];
        final id = raw is int
            ? raw
            : raw is String
                ? int.tryParse(raw)
                : null;
        if (id == null) return;
        if (type == 'audio') {
          audioIds.add(id);
        } else if (type == 'sub') {
          subIds.add(id);
        }
      }

      if (decoded is List) {
        // 鸿蒙：mpv 原生 `track-list`（每项自带 type 字段）。
        for (final track in decoded) {
          take(track, track is Map ? '${track['type']}' : '');
        }
      } else if (decoded is Map) {
        // 安卓：分组 Map（无 type 字段，靠分组名判定）。
        final audio = decoded['audio'];
        if (audio is List) {
          for (final track in audio) {
            take(track, 'audio');
          }
        }
        final sub = decoded['subtitle'];
        if (sub is List) {
          for (final track in sub) {
            take(track, 'sub');
          }
        }
      }

      if (audioIds.isEmpty && subIds.isEmpty) {
        // 619：起播早期轨道表**本来就是空的**（`{"video":[],"audio":[],
        // "subtitle":[]}`）——这是正常状态，不是结构不符。旧实现在这里
        // 每次都打日志，真机日志被刷了 20+ 条（纯噪音）。
        // 只在「确实有轨道数据但解析不出 id」时才报警。
        final hasRawTracks = (decoded is List && decoded.isNotEmpty) ||
            (decoded is Map &&
                ((decoded['audio'] is List &&
                        (decoded['audio'] as List).isNotEmpty) ||
                    (decoded['subtitle'] is List &&
                        (decoded['subtitle'] as List).isNotEmpty)));
        if (hasRawTracks) {
          final preview =
              value.length > 200 ? '${value.substring(0, 200)}...' : value;
          LogService()
              .log('mpv', 'track-list 有轨道但解析无 id（结构不符？）: $preview');
        }
        return;
      }
      // 617：即使某一类为空也要落表（空列表 = 该类无轨），否则旧的
      // 「isNotEmpty 才覆盖」会让上一集的 id 残留 → 换集后选轨错位。
      _audioTrackIds
        ..clear()
        ..addAll(audioIds);
      _subtitleTrackIds
        ..clear()
        ..addAll(subIds);
      _mediaInfo = AdapterMediaInfo(
        duration: _durationMs,
        format: _mediaInfo.format,
        audio: _mediaInfo.audio,
        video: _mediaInfo.video,
        subtitleCount: subIds.length,
      );
    } catch (e) {
      // 617：解析异常不再静默吞掉（真机日志可见）。
      LogService().log('mpv', 'track-list 解析失败: $e');
    }
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
  List<String> get videoDecoders {
    // 640：按当前平台返回对应硬解器名（旧实现恒返回 'ohcodec'，会让
    // Android/Windows 的诊断面板与设置回显显示成鸿蒙硬解器）。
    final hw = DecodeModeService.platformHwDecoderName;
    switch (_hwdec) {
      case 'no':
        return const ['FFmpeg'];
      case 'hw':
        return <String>[hw];
      default:
        return <String>[hw, 'FFmpeg'];
    }
  }

  @override
  set videoDecoders(List<String> decoders) {
    if (_disposed) return;
    // 上层的语义（DecodeModeService，按平台返回不同硬解器名）：
    //   ['FFmpeg']                    → 软解（no）
    //   [<硬解器>]                     → 纯硬解
    //   [<硬解器>, 'FFmpeg']           → 智能（auto，硬解优先软解兜底）
    //
    // 640：**平台无关**识别硬解器名。旧实现只认 `ohcodec`（鸿蒙），
    // 导致 Android 的 `AMediaCodec` / Windows 的 `D3D11`/`DXVA` /
    // Apple 的 `VT` 全被判为「无硬解」→ `decodeMode='hw'` 静默退化成
    // `auto`（真机「MPV 硬解模式没生效」）。
    const hwDecoderHints = <String>[
      'ohcodec', // 鸿蒙
      'mediacodec', // Android
      'd3d11', 'dxva', // Windows
      'vt', 'videotoolbox', // Apple
      'vaapi', 'vdpau', 'nvdec', 'cuda', // Linux/NVIDIA
    ];
    final hasHw = decoders.any((d) {
      final lower = d.toLowerCase();
      return hwDecoderHints.any(lower.contains);
    });
    final hasSw = decoders.any((d) => d.toLowerCase().contains('ffmpeg'));
    final String next;
    if (!hasHw && hasSw) {
      next = 'no';
    } else if (hasHw && !hasSw) {
      // 纯硬解：不写具体解码器名（mpv 的 hwdec 取值是 auto/mediacodec 等
      // 语义名，不是 DecodeModeService 的平台解码器名）。
      next = 'hw';
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
  ///
  /// [waitForPlatformViewTeardown]：重开场景（597 搜索返回）需要多等
  /// 两帧，让 Flutter 侧平台视图先卸载、其 SurfaceView 销毁，再打开
  /// 原生宿主窗口；否则两个 SurfaceView 短暂并存会抢 surface 绑定
  /// （v1.5.4 安卓黑屏根因）。prepare 首次打开时平台视图尚未挂载，
  /// 无需等待。
  Future<void> _openNativeUiIfNeeded({
    bool waitForPlatformViewTeardown = false,
  }) async {
    if (_disposed || _nativeUiController != null) return;
    // 【613：允许在 prepare() 之前打开】空房间/初始未播放时没有剧集要加载
    // → `prepare()` 不调用 → `_nativeUiEnabled` 从未计算过。此时按设置
    // 预判（`prefersNativeRoomUi` 是纯计算、不建会话）补算一次。
    if (!_nativeUiEnabled) {
      // 【614 真机回归：安卓画面拉伸 / 视频贴左上角】613 在这里补算并
      // **写回** `_nativeUiEnabled`，导致安卓非房间播放也打开原生窗口，
      // 而安卓 surface 尺寸与窗口尺寸不同步（`window.setLayout` 用
      // displayMetrics 反推）→ 画面被缩成左上角一小块。
      // 613 的「提前打开」只在**鸿蒙**生效（鸿蒙用 Flex 流式布局、
      // 尺寸由框架算，不存在这个不同步问题）；安卓回退到 612 行为
      //（只在 prepare() 里按实际会话判定）。
      if (!MpvSessionPlatform.isOhos) return;
      if (!prefersNativeRoomUi) return;
      // 不写回 `_nativeUiEnabled`（避免跨会话残留，见 _closeNativeUi）。
    }
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
      if (waitForPlatformViewTeardown) {
        // 两帧 + 少量余量：足够 Flutter 侧重建并卸载平台视图。
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_disposed || _nativeUiController != controller) return;
      }
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

  /// 临时隐藏原生 UI 宿主（**不销毁** session / surface 绑定，603）。
  ///
  /// 【603 真机回归：点「取消」后播任何视频都白屏 / 搜索后黑屏】
  /// 原生窗口 z-order 在 Flutter 页面之上，要显示 Flutter UI（搜索页 /
  /// 离房确认框）必须先隐藏它。
  ///
  /// 与 [closeNativeUi] 的区别：只 hide 窗口，controller / session /
  /// surface 绑定**全部保留** → [resumeNativeUi] 恢复时画面立刻回来，
  /// 零白屏。旧实现用 close + [reopenNativeUi] 要重建窗口并重新绑定
  /// surface，有「两个 SurfaceView 抢绑定」风险（v1.5.4 安卓黑屏根因）。
  Future<void> suspendNativeUi() async {
    if (_disposed || _nativeUiController == null) return;
    try {
      await MpvSessionPlatform.suspendNativeUi();
      _nativeUiSuspended = true;
    } catch (e) {
      LogService().log('mpv', '隐藏原生 UI 失败: $e');
    }
  }

  /// 恢复被 [suspendNativeUi] 隐藏的宿主（幂等；未 suspend 时无副作用）。
  Future<void> resumeNativeUi() async {
    if (_disposed || _nativeUiController == null) return;
    if (!_nativeUiSuspended) {
      // 没 suspend 过：只需补推一次状态（数据可能已变）。
      _pushNativeUiState(immediate: true);
      return;
    }
    try {
      await MpvSessionPlatform.resumeNativeUi();
      _nativeUiSuspended = false;
      // 恢复后立即补推权威状态（隐藏期间面板数据/播放态可能已变）。
      _pushNativeUiState(immediate: true);
    } catch (e) {
      LogService().log('mpv', '恢复原生 UI 失败: $e');
    }
  }

  /// 原生宿主是否处于「已隐藏」状态（见 [suspendNativeUi]）。
  bool _nativeUiSuspended = false;

  /// 卸载当前媒体并停止播放（606）。
  ///
  /// 【真机回归：删除正在播放的资源后仍在播】
  /// `_removeEpisode` 设了 `state = AdapterPlaybackState.stopped`（该 setter
  /// 确实会调 `player.stop()`），但适配器的 500ms 轮询里
  /// `_applyPolledState` 有：
  /// ```dart
  /// if (_prepared && hasProgress) {
  ///   _setState(state.paused ? paused : playing);   // ← 把 stopped 覆盖回 playing
  /// }
  /// ```
  /// `_prepared` 只在 `prepare()` 里置 true、**从不重置**，而 `durationMs`
  /// / `positionMs` 仍在 → 下一轮轮询立刻把状态改回 `playing` →
  /// `player.play()` → 画面继续播。
  ///
  /// 本方法重置 `_prepared` 与进度字段，让轮询不再认为「有进度在播」，
  /// 并显式 stop。删除当前播放资源时调用。
  Future<void> unloadMedia() async {
    if (_disposed) return;
    _prepared = false;
    _positionMs = 0;
    _durationMs = 0;
    _bufferedMs = 0;
    _propertyCache.remove('time-pos');
    _propertyCache.remove('duration');
    _mediaStatus = AdapterMediaStatus.unloaded;
    try {
      await _player?.stop();
    } catch (e) {
      LogService().log('mpv', '卸载媒体失败: $e');
    }
    _setState(AdapterPlaybackState.stopped);
    _pushNativeUiState(immediate: true);
  }

  /// 按当前设置预判「房间 UI 该走原生还是 Flutter」（613）。
  ///
  /// 【真机回归：空房间/初始未播放时房间头部三控件不显示】原生 UI 只在
  /// `prepare()` 里打开，而 `prepare()` 只在加载剧集时调用——空房间没有
  /// 剧集 → 原生窗口从未打开 → 用户看到的是 **Flutter 播放页**，而 Flutter
  /// 头部条件 `_roomData != null` 在 async 的 `_setupRoomSync()` 里才满足
  /// → 三控件不显示。播放后才打开原生窗口、那时 `isHost` 已推送 → 显示。
  ///
  /// 本 getter **不创建会话**，只按「引擎 + 输出路径设置 + 平台门控」算出
  /// 该走哪条路——与 `prepare()` 里的判定同源（`_resolveMpvVideoOutput()`
  /// 是纯计算，只读设置与平台，不需要会话）。
  bool get prefersNativeRoomUi {
    if (_disposed) return false;
    return NativePlayerGating.shouldUseCurrent(
      engine: 'mpv',
      actualVideoOutput: _resolveMpvVideoOutput(),
      settingEnabled: _nativeUiSettingEnabled,
    );
  }

  /// 重新打开原生 UI 宿主（597）。
  ///
  /// 【真机回归：原生入口进资源搜索后回播放页黑屏】`closeNativeUi()` 会
  /// 关掉宿主并把 `nativeUiActive` 置 false，PlayerScreen 随之重新挂载
  /// Flutter 平台视图；但 `_openNativeUiIfNeeded()` 只在 `prepare()` 里
  /// 调用，**没有任何路径会再打开宿主**。于是搜完资源回到播放页时：
  /// 原生窗口已关、Flutter 视频层也因 `nativeUiActive` 曾是 true 而未
  /// 挂载 → 纯黑（当前暂停的视频与新添加的资源都一样）。
  ///
  /// 这里提供显式重开入口，走的是已验证的 `_openNativeUiIfNeeded()` 路径
  /// （含 `nativeUiActive=true` → `open` → `refreshSurface()` 的顺序，
  /// 避免两个 SurfaceView 并存抢绑定）。
  Future<void> reopenNativeUi() async {
    if (_disposed) return;
    if (nativeUiActive.value && _nativeUiController != null) {
      // 已开着：只需重新推一次权威状态（房间面板数据可能已变）。
      _pushNativeUiState(immediate: true);
      return;
    }
    // 残留控制器（宿主已被系统销毁等）先清干净，避免 open 被守卫拦掉。
    _nativeUiController = null;
    await _openNativeUiIfNeeded(waitForPlatformViewTeardown: true);
  }

  /// 关闭原生 UI 宿主（幂等）。
  Future<void> _closeNativeUi() async {
    final controller = _nativeUiController;
    _nativeUiController = null;
    _nativeUiSuspended = false;
    // 【614】重置门控——否则该字段一旦为 true 就跨会话残留，后续非房间
    // 播放也会误走原生窗口（真机「613 起非房间竖屏画面不在屏幕内」）。
    _nativeUiEnabled = false;
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

  /// 656：公开的状态快照（供 Qt 播放器推送用）。
  ///
  /// 内部仍走 [_buildNativePlayerState]，保证与安卓/鸿蒙原生 UI 拿到的
  /// 是**同一份** 87 字段结构，三端行为天然一致。
  NativePlayerState buildNativePlayerState() => _buildNativePlayerState();

  /// 把适配器当前状态转成原生 UI 权威快照（计划书 §7.4 数据源）。
  NativePlayerState _buildNativePlayerState() {    final paused = _state == AdapterPlaybackState.paused ||
        _state == AdapterPlaybackState.stopped;
    final buffering =
        (_mediaStatus.rawValue & AdapterMediaStatus.buffering.rawValue) != 0;
    // 加载指示器（587）：**必须在每次推送时现算**。
    //
    // 586 的坑：该值曾随 `NativePlayerUiExtras` 下发，而 extras 只在
    // 设置变更/切集/开关面板等低频时机重建；播放态变化走本方法的 200ms
    // 轮询，送下去的一直是起播前算出的 `true` → 鸿蒙/安卓「视频都在播了
    // 还一直转圈」。
    //
    // 判定语义与 `PlayerScreen.shouldShowLoadingSpinner` 一致（首帧未出
    // **或** 缓冲中），但这里只用手边的高频字段：
    // - [firstFramePending]：有视频轨、时长已到但 video-params 未到 = 首帧
    //   未出（比 `position==0` 更准，起播后第一秒就能收起）；
    // - 时长与位置都为 0 且未进入 playing = 首帧前的纯黑窗口；
    // - [buffering]：中途卡顿。
    //
    // 589 看门狗兜底：即使「首帧已出」的判据全部失效（某些设备
    // `video-params`/`width` 都读不到），只要确实在播放且位置已推进超过
    // [loadingWatchdogMs]，就强制收起转圈——绝不允许永久转圈。
    // 【614 真机回归：初始未播放时仍有加载器】旧判定没有「是否加载了媒体」
    // 的守卫——空房间/初始未播放时 `_durationMs==0 && _positionMs==0 &&
    // 非playing` 恒真 → 转圈永久显示（真机截图：占位提示旁一直转圈）。
    final hasMedia = _prepared || _uri != null;
    final showLoading = hasMedia &&
        !_loadingWatchdogFired &&
        (buffering ||
            firstFramePending.value ||
            (_durationMs == 0 &&
                _positionMs == 0 &&
                _state != AdapterPlaybackState.playing));
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
      // 697：HDR/DV 调试指标（原生面板用，与 Flutter 面板同源）
      videoParamsPrimaries: _colorInfo?.primaries ?? '',
      videoParamsGamma: _colorInfo?.gamma ?? '',
      videoParamsSigPeak: _colorInfo?.sigPeak ?? 0,
      videoParamsBitDepth: _colorInfo?.bitDepth ?? 0,
      videoParamsPixelFormat: _colorInfo?.pixelFormat ?? '',
      // DV Profile：mpv 优先（逐场景真实值），读不到用 Emby 静态声明
      doviProfile: (_colorInfo?.doviProfile ?? 0) > 0
          ? _colorInfo!.doviProfile
          : _embyDoviProfile,
      doviLevel: _colorInfo?.doviLevel ?? 0,
      dvContent: _dvContentForMedia,
      // 【必须有兜底】`_debugProps` 在面板未开启时可能为空，
      // 直接用会显示空字符串（真机截图：目标/映射/编码全空）。
      targetPrim: _debugProps['target-prim'] ?? _targetPrim ?? '',
      toneMapping: _debugProps['tone-mapping'] ?? _targetToneMapping ?? '',
      toneMappingMode: _debugProps['tone-mapping-mode'] ?? '',
      hdrComputePeak: _debugProps['hdr-compute-peak'] ?? '',
      gpuApi: _debugProps['gpu-api'] ?? '',
      gpuContext: _debugProps['gpu-context'] ?? _gpuContext ?? '',
      estimatedVfFps: double.tryParse(_debugProps['estimated-vf-fps'] ?? '') ?? 0,
      frameDropCount: int.tryParse(_debugProps['frame-drop-count'] ?? '') ?? 0,
      decoderFrameDropCount:
          int.tryParse(_debugProps['decoder-frame-drop-count'] ?? '') ?? 0,
      videoFormat: _debugProps['video-format'] ?? '',
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
      title: _nativeUiExtras.title,
      mediaTitle: _propertyCache['media-title'],
      // 625：视频显示宽高（已含旋转翻转）——鸿蒙原生 UI 用它算 XComponent
      // 的 letterbox 尺寸（鸿蒙 ohosvk 不响应运行时画布重配，靠属性改不掉
      // 拉伸；让画布本身就是视频比例才是根治）。
      videoWidth: _lastVideoW,
      videoHeight: _lastVideoH,
      logoUrl: _nativeUiExtras.logoUrl,
      networkSpeedText: _nativeUiExtras.networkSpeedText,
      clockFormat: _nativeUiExtras.clockFormat,
      glassUi: _nativeUiExtras.glassUi,
      engineLabel: _nativeUiExtras.engineLabel,
      engineOptions: _nativeUiExtras.engineOptions,
      videoFit: _nativeUiExtras.videoFit,
      decodeMode: _nativeUiExtras.decodeMode,
      subtitleScale: _nativeUiExtras.subtitleScale,
      subtitleMarginY: _nativeUiExtras.subtitleMarginY,
      subtitleDelayEnabled: _nativeUiExtras.subtitleDelayEnabled,
      subtitleStyleDisabled: _nativeUiExtras.subtitleStyleDisabled,
      danmakuEnabled: _nativeUiExtras.danmakuEnabled,
      danmakuSpeed: _nativeUiExtras.danmakuSpeed,
      danmakuFontSize: _nativeUiExtras.danmakuFontSize,
      danmakuOpacity: _nativeUiExtras.danmakuOpacity,
      danmakuScrollRows: _nativeUiExtras.danmakuScrollRows,
      danmakuTopRows: _nativeUiExtras.danmakuTopRows,
      danmakuBottomRows: _nativeUiExtras.danmakuBottomRows,
      danmakuMaxCount: _nativeUiExtras.danmakuMaxCount,
      // 弹幕时间窗：原生 UI 下 Flutter 弹幕层随视频区一并退场，弹幕改由
      // 原生层渲染（真机回归「弹幕开关点了没反应」）。窗口随每次状态推送
      // 刷新，原生端按 timeMs 与当前播放位置自调度（seek 自愈）。
      danmakuItems: _buildDanmakuWindow(),
      segmentEnabled: _nativeUiExtras.segmentEnabled,
      segmentIntroEndMs: _nativeUiExtras.segmentIntroEndMs,
      segmentOutroStartMs: _nativeUiExtras.segmentOutroStartMs,
      skipPrompt: _nativeUiExtras.skipPrompt,
      showDebug: _nativeUiExtras.showDebug,
      // 加载指示器（587）：现算值（见方法开头注释），不再读低频 extras。
      showLoading: showLoading,
      // 是否有可播放内容（607）：无内容时原生渲染「请从资源面板选择要
      // 播放的内容」占位（对齐 Flutter `_buildVideoArea` 的空态分支）。
      // 判据与 PlayerScreen 一致：未就绪（删除了当前集 / 尚未起播）。
      playerReady: _prepared && !_disposed,
      // 房间资源面板（595）：这 5 个字段此前**从未传入** NativePlayerState
      // （构造时漏传 + toJson 未序列化），导致原生 `resourceGroups` 永远空、
      // `resourcePanelOpen` 永远默认 true（真机「面板永远空白、开关点了没
      // 反应」）。
      roomCode: _nativeUiExtras.roomCode,
      isHost: _nativeUiExtras.isHost,
      onlineUserCount: _nativeUiExtras.onlineUserCount,
      audienceName: _nativeUiExtras.audienceName,
      resourceGroups: _nativeUiExtras.resourceGroups,
      broadcasts: _nativeUiExtras.broadcasts,
      resourcePanelOpen: _nativeUiExtras.resourcePanelOpen,
      isRoom: _nativeUiExtras.isRoom,
      canScreenshot: _nativeUiExtras.canScreenshot,
      locked: _nativeUiExtras.locked,
      canControl: _nativeUiExtras.canControl,
      tvMode: _nativeUiExtras.tvMode,
      audioStreamCount: _nativeUiExtras.audioStreamCount,
      subtitleStreamCount: _nativeUiExtras.subtitleStreamCount,
      tracks: _panelTracksFromEmby(),
      selectedAudioId: _panelSelectedId(_activeAudioTracks),
      selectedSubtitleId: _panelSelectedId(_activeSubtitleTracks),
      episodes: _nativeEpisodes,
      versions: _nativeVersions,
      currentEpisodeIndex: _nativeCurrentEpisodeIndex,
      currentVersionIndex: _nativeCurrentVersionIndex,
      debugLines: _nativeDebugLines(),
    );
  }

  /// 面板轨道列表：**全部由 Emby 流生成**（真机回归「字幕/音轨面板没对接
  /// 选项」：旧实现依赖 mpv `track-list` 属性事件，事件不送达则恒空）。
  ///
  /// 约定与原生命令一致：`id = Emby 索引 + 1`（0 = 关闭字幕），
  /// `selected` 由 Dart 侧 [_activeAudioTracks]/[_activeSubtitleTracks] 判定。
  List<NativeTrack> _panelTracksFromEmby() {
    final out = <NativeTrack>[];
    for (var i = 0; i < _nativeAudioLabels.length; i++) {
      out.add(NativeTrack(
        id: i + 1,
        type: 'audio',
        label: _nativeAudioLabels[i],
        selected: _activeAudioTracks.isNotEmpty && _activeAudioTracks.first == i,
      ));
    }
    for (var i = 0; i < _nativeSubtitleLabels.length; i++) {
      out.add(NativeTrack(
        id: i + 1,
        type: 'sub',
        label: _nativeSubtitleLabels[i],
        selected:
            _activeSubtitleTracks.isNotEmpty && _activeSubtitleTracks.first == i,
      ));
    }
    return out;
  }

  /// 面板选中 id（Emby 索引 + 1；未选 = 0）。
  static int _panelSelectedId(List<int> active) =>
      active.isNotEmpty && active.first >= 0 ? active.first + 1 : 0;

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
  @override
  bool get isDisposed => _disposed;

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
    _stopNativeDebugRefresh();
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
