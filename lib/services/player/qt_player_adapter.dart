import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../../services/log_service.dart';
import '../player/player_adapter.dart';
import 'mpv_player_adapter.dart' show resolveWindowsHwdec;
import 'native/native_player_command.dart';
import 'qt_player_pipe.dart';

/// 656：Qt 播放器窗口的 Flutter 侧适配器。
///
/// 【定位】Qt 进程自己拥有 mpv（`wid` 直出，HDR），本适配器只做**代理**：
/// 把 `PlayerAdapter` 的调用翻译成 IPC 命令，把 Qt 推来的状态翻译回
/// Flutter 的属性读取。
///
/// 【为什么不复用 MpvPlayerAdapter】那条路要求 mpv 在**同一进程**（`wid`
/// 必须是本进程的 HWND）。Qt 是独立进程，mpv 也在那边，所以只能走 IPC。
///
/// 【与现有 646 的关系】646 的原生窗口（`himi_mpv_windows` 插件）仍在，
/// 本适配器是**可选的另一条路**：设置里开启「Qt 播放器」才走这里。
/// 这样即使 Qt 方案出问题，回退到 646 只改一个开关。
///
/// 【状态来源】所有 getter 读本地缓存（`_lastState`），由 IPC 推送更新。
/// 好处是 `position` 这类高频读取不产生 IPC 往返；代价是有最多 200ms
/// 的延迟（推送节流），对 UI 显示足够。
class QtPlayerAdapter implements PlayerAdapter {
  QtPlayerAdapter._(this._pipe) {
    _bindPipe();
  }

  /// 拉起 Qt 播放器并创建适配器。
  ///
  /// @param exePath  `himi_qt_player.exe` 的绝对路径
  /// @param hdr      是否请求 HDR 直出
  /// @param hlg      内容是否为 HLG
  static Future<QtPlayerAdapter> launch({
    required String exePath,
    required bool hdr,
    required bool hlg,
  }) async {
    final pipe = await QtPlayerPipe.launch(
      exePath: exePath,
      hdr: hdr,
      hlg: hlg,
    );
    return QtPlayerAdapter._(pipe);
  }

  final QtPlayerPipe _pipe;

  // ── 本地状态缓存（由 IPC 推送更新）──
  AdapterPlaybackState _state = AdapterPlaybackState.stopped;
  AdapterMediaStatus _mediaStatus = AdapterMediaStatus.unloaded;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 1.0;
  double _playbackRate = 1.0;
  int _bufferedMs = 0;
  String _mediaUri = '';
  Map<String, String> _headers = const {};
  List<int> _audioTracks = const [];
  List<int> _subtitleTracks = const [];
  bool _disposed = false;

  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final StreamController<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      _stateController = StreamController.broadcast();
  final StreamController<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      _statusController = StreamController.broadcast();
  final StreamController<AdapterMediaEvent> _eventController =
      StreamController.broadcast();

  /// Qt 进程退出回调（上层据此回详情页）。
  void Function()? onProcessExited;

  /// Qt 亮度滑杆变更回调（由播放页注入）。
  void Function(double value)? onBrightnessChanged;

  /// 原生命令回调（与 MpvPlayerAdapter.onNativeUiCommand 同签名）。
  ///
  /// 【662 修复：命令链路断点】切集/选轨/选版本/弹幕/显示调节这类**带
  /// payload** 的命令，此前只被包装成 `AdapterMediaEvent('native.command',
  /// type)` 丢进事件流——**没有任何消费方**，Qt 窗口里的选集/字幕/音轨/
  /// 多版本面板全部是死按钮。现在解析成 [NativePlayerCommand] 直接交给
  /// 播放页的 `_handleNativeUiCommand`（与安卓/鸿蒙原生 UI 同链路）。
  Future<void> Function(NativePlayerCommand command)? onNativeUiCommand;

  void _bindPipe() {
    _pipe.commands.listen(_handleCommand);
    _pipe.onDisconnected = () {
      if (_disposed) return;
      LogService().log('QtPlayer', 'Qt 进程已退出');
      _setState(AdapterPlaybackState.stopped);
      onProcessExited?.call();
    };
  }

  /// 处理 Qt 发来的命令（`NativePlayerCommand` 的 JSON）。
  ///
  /// 这里只处理**播放控制类**（播放/暂停/seek/音量/倍速）；
  /// 切集/选轨/弹幕这类需要 Flutter 逻辑的，由播放页的
  /// `onNativeUiCommand` 链路处理（与安卓/鸿蒙一致）。
  void _handleCommand(Map<String, Object?> cmd) {
    final type = cmd['type'] as String?;
    switch (type) {
      case 'togglePlay':
        state = _state == AdapterPlaybackState.playing
            ? AdapterPlaybackState.paused
            : AdapterPlaybackState.playing;
      case 'seekTo':
        final ms = (cmd['positionMs'] as num?)?.toInt() ?? 0;
        unawaited(seek(positionMs: ms));
      case 'seekRelative':
        final delta = (cmd['deltaMs'] as num?)?.toInt() ?? 0;
        unawaited(seek(positionMs: _positionMs + delta));
      case 'setVolume':
        volume = (cmd['volume'] as num?)?.toDouble() ?? 1.0;
      case 'setSpeed':
        playbackRate = (cmd['speed'] as num?)?.toDouble() ?? 1.0;
      case 'setBrightness':
        final v = (cmd['brightness'] as num?)?.toDouble() ?? 0.5;
        onBrightnessChanged?.call(v);
      default:
        // 其余命令（切集/选轨/选版本/弹幕/显示调节等）解析成
        // [NativePlayerCommand] 交给播放页（与安卓/鸿蒙原生 UI 同链路）。
        // 【662 修复】此前只发 AdapterMediaEvent('native.command')——
        // 没有任何消费方，Qt 窗口的选集/字幕/音轨/多版本面板全是死按钮。
        final command = NativePlayerCommand.fromMap(cmd);
        final forward = onNativeUiCommand;
        if (command != null && forward != null) {
          unawaited(forward(command));
        } else {
          // 无上层接线（或未知命令类型）时保留事件兜底。
          _eventController.add(
            AdapterMediaEvent(0, 'native.command', type ?? 'unknown'),
          );
        }
    }
  }

  /// 推送完整状态给 Qt（由播放页调用，200ms 节流）。
  ///
  /// [stateJson] 是 `NativePlayerState.toJson()` 的结果。
  void pushNativeState(Map<String, Object?> stateJson, {String? playUrl}) {
    if (_disposed) return;
    _pipe.pushState(stateJson, playUrl: playUrl);
  }

  void _setState(AdapterPlaybackState next) {
    if (_state == next) return;
    final old = _state;
    _state = next;
    _stateController.add((oldValue: old, newValue: next));
  }

  void _setMediaStatus(AdapterMediaStatus next) {
    if (_mediaStatus == next) return;
    final old = _mediaStatus;
    _mediaStatus = next;
    _statusController.add((oldValue: old, newValue: next));
  }

  // ── 播放控制 ──────────────────────────────────────────────

  @override
  AdapterPlaybackState get state => _state;

  @override
  set state(AdapterPlaybackState value) {
    if (_disposed) return;
    _setState(value);
    // Qt 侧的命令是「togglePlay」而非「setState」，这里按目标状态映射。
    if (value == AdapterPlaybackState.playing ||
        value == AdapterPlaybackState.paused) {
      _pipe.sendCommandRaw({
        'type': 'setPaused',
        'paused': value == AdapterPlaybackState.paused,
      });
    }
  }

  @override
  Future<void> seek({required int positionMs}) async {
    if (_disposed) return;
    _positionMs = positionMs.clamp(0, _durationMs > 0 ? _durationMs : positionMs);
    _pipe.sendCommandRaw({'type': 'seekTo', 'positionMs': _positionMs});
  }

  // ── 媒体加载 ──────────────────────────────────────────────

  @override
  set media(String uri) => _mediaUri = uri;

  @override
  Future<void> prepare({int startMs = 0}) async {
    if (_disposed) return;
    if (_mediaUri.isEmpty) {
      LogService().log('QtPlayer', 'prepare 失败：media 未设置');
      return;
    }
    _setMediaStatus(AdapterMediaStatus.loading);
    _setState(AdapterPlaybackState.playing);
    // 播放地址与鉴权头通过 IPC 下发（不放在命令行，避免 URL 泄露到
    // 任务管理器 + 规避命令行长度限制）。
    _pipe.sendCommandRaw({
      'type': 'load',
      'url': _mediaUri,
      'startMs': startMs,
      'headers': _headers,
    });
  }

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position => _positionMs;

  @override
  int get duration => _durationMs;

  @override
  AdapterMediaInfo get mediaInfo => AdapterMediaInfo.empty;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    if (_disposed) return;
    _volume = value.clamp(0.0, 1.0);
    _pipe.sendCommandRaw({'type': 'setVolume', 'volume': _volume});
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    if (_disposed) return;
    _playbackRate = value;
    _pipe.sendCommandRaw({'type': 'setSpeed', 'speed': value});
  }

  @override
  AdapterMediaStatus get mediaStatus => _mediaStatus;

  @override
  int buffered() => _bufferedMs;

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  int get nativeHandle => 0;

  // ── 渲染（Qt 自己管，全部空实现）─────────────────────────

  @override
  Future<int> updateTexture({int? width, int? height, bool? tunnel}) async => 0;

  @override
  Future<Size?> get textureSize async => null;

  @override
  void setColorSpace(AdapterColorSpace cs) {}

  @override
  void renderVideo() {}

  // ── 轨道 ──────────────────────────────────────────────────

  @override
  List<int> get activeAudioTracks => _audioTracks;

  @override
  set activeAudioTracks(List<int> tracks) {
    if (_disposed) return;
    _audioTracks = List<int>.from(tracks);
    if (tracks.isNotEmpty) {
      _pipe.sendCommandRaw({'type': 'selectAudio', 'id': tracks.first});
    }
  }

  @override
  List<int> get activeSubtitleTracks => _subtitleTracks;

  @override
  set activeSubtitleTracks(List<int> tracks) {
    if (_disposed) return;
    _subtitleTracks = List<int>.from(tracks);
    _pipe.sendCommandRaw({
      'type': 'selectSubtitle',
      'id': tracks.isEmpty ? -1 : tracks.first,
    });
  }

  // ── 事件 ──────────────────────────────────────────────────

  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged => _stateController.stream;

  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus => _statusController.stream;

  @override
  Stream<AdapterMediaEvent> get onEvent => _eventController.stream;

  // ── 属性通道 ──────────────────────────────────────────────

  /// 669：HDR/HLG 档位晚绑定（进程提前拉起，媒体信息解析完才决定）。
  ///
  /// 时序约定：**先 setHdrMode 再 prepare(load)**——mpv 首帧前应用
  /// 与启动参数等效（Qt 侧 `MpvWindow::setHdrMode`）。
  void setHdrMode({required bool hdr, required bool hlg}) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'setHdrMode', 'hdr': hdr, 'hlg': hlg});
    LogService().log('QtPlayer', 'setHdrMode hdr=$hdr hlg=$hlg');
  }

  @override
  void setProperty(String name, String value) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'setProperty', 'name': name, 'value': value});
  }

  @override
  String? getProperty(String name) => null;

  @override
  void setHttpHeaders(Map<String, String> headers) {
    _headers = Map<String, String>.from(headers);
  }

  @override
  List<String> get videoDecoders => const [];

  /// 解码档位 → mpv `hwdec`（经 Qt 侧 `setProperty` 命令透传）。
  ///
  /// 【662】此前是空实现：Qt 的「解码方式」面板切了档位只落设置，
  /// 正在播的 mpv 根本不知道。映射与 `MpvPlayerAdapter.set
  /// videoDecoders` 同语义：
  ///   ['FFmpeg'] → no（软解）；[硬解器] → hw（纯硬解）；
  ///   [硬解器, 'FFmpeg'] → auto（硬解优先软解兜底）。
  /// 顶层 `resolveWindowsHwdec` 是映射的单一真相源（d3d11 零拷贝
  /// 在部分驱动上崩溃，Windows 统一 copy-back）。
  @override
  set videoDecoders(List<String> decoders) {
    if (_disposed) return;
    const hwDecoderHints = <String>[
      'ohcodec', 'mediacodec', 'd3d11', 'dxva',
      'vt', 'videotoolbox', 'vaapi', 'vdpau', 'nvdec', 'cuda',
    ];
    final hasHw = decoders.any((d) {
      final lower = d.toLowerCase();
      return hwDecoderHints.any(lower.contains);
    });
    final hasSw = decoders.any((d) => d.toLowerCase().contains('ffmpeg'));
    final String mode;
    if (!hasHw && hasSw) {
      mode = 'no';
    } else if (hasHw && !hasSw) {
      mode = 'hw';
    } else {
      mode = 'auto';
    }
    final effective = resolveWindowsHwdec(mode, windows: true);
    _pipe.sendCommandRaw({
      'type': 'setProperty',
      'name': 'hwdec',
      'value': effective,
    });
    LogService().log('QtPlayer', 'videoDecoders $decoders → hwdec=$effective');
  }

  @override
  List<String> get audioDecoders => const [];

  @override
  set audioDecoders(List<String> decoders) {}

  @override
  set audioBackends(List<String> backends) {}

  @override
  void setBufferRange({int min = -1, int max = -1, bool drop = false}) {}

  // ── 字幕 / 截图 ───────────────────────────────────────────

  @override
  Future<void> setMedia(String uri, {required AdapterMediaType type}) async {
    _mediaUri = uri;
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) async => null;

  // ── 生命周期 ──────────────────────────────────────────────

  @override
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _setState(AdapterPlaybackState.stopped);
    unawaited(_pipe.dispose());
    unawaited(_stateController.close());
    unawaited(_statusController.close());
    unawaited(_eventController.close());
    _textureIdNotifier.dispose();
  }
}
