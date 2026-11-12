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
  /// @param prewarm  隐藏待命模式（670：窗口收到 load 命令才显示）
  static Future<QtPlayerAdapter> launch({
    required String exePath,
    required bool hdr,
    required bool hlg,
    bool prewarm = false,
  }) async {
    final pipe = await QtPlayerPipe.launch(
      exePath: exePath,
      hdr: hdr,
      hlg: hlg,
      prewarm: prewarm,
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

  /// 682：是否已向 Qt 下发过媒体（`prepare` 置位、`unloadMedia` 清零）。
  ///
  /// 【为什么需要】Qt 在 `stopPlayback()` 后会回一帧 `paused:true`（清进度
  /// 用）。没有这个标志时，[`_applyPlayback`] 会把它翻成 `paused` 状态
  /// → `playerReady` 误判为「有内容」→ Win 房间删空资源后占位文字不显示。
  bool _hasMedia = false;

  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final StreamController<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      _stateController = StreamController.broadcast();
  final StreamController<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      _statusController = StreamController.broadcast();
  final StreamController<AdapterMediaEvent> _eventController =
      StreamController.broadcast();

  /// Qt 进程退出回调（上层据此回详情页）。
  void Function()? onProcessExited;

  /// 671 A1：是否存活（进程在 + 管道未断）——死适配器不得复用。
  bool get isAlive => !_disposed && !_pipe.isClosed;

  /// Qt 亮度滑杆变更回调（由播放页注入）。
  void Function(double value)? onBrightnessChanged;

  /// 677：**播放控制意图**回调（Qt 本地已执行 → 只上报，不回发 IPC）。
  ///
  /// 【为什么要区分「意图」与「程序下发」】
  /// Qt 的 `command` 帧天然只是「本地用户动作」——Qt 不会把 Dart 下发
  /// 的命令回显。所以：
  ///   - 用户点 Qt 的播放/暂停/seek/倍速 → 本回调 → 房主广播房间命令
  ///   - Dart 程序性下发（心跳纠偏 / 同步）→ 走 `state=`/`seek()`，
  ///     **不会**回到本回调 → 天然无广播回环。
  ///
  /// 【为什么不能走 setter】旧实现 `togglePlay` 就地 `state = ...`，
  /// 会经 setter 回发 `setPaused` 给 Qt——而 QML 早已本地
  /// `mpvWindow.togglePause()`，等于把状态又翻一次（真机：点一次播两下）。
  void Function(QtTransportIntent intent)? onTransportIntent;

  /// 677：窗口态回调（全屏切换；房间并排与全屏互斥）。
  void Function(bool fullscreen)? onFullscreenChanged;

  /// 683：Qt 窗被抬到前面 → 把 Flutter 面板窗也抬上来（两窗同层）。
  ///
  /// 【为什么不置顶】用户明确要求「两窗同一层，但不要固定最上层」——
  /// 切到别的软件时两窗要能一起被盖住。
  void Function()? onRaised;

  /// 691：Qt 自然播完 → 自动切下一集。
  ///
  /// 【对齐安卓】安卓靠 `AdapterMediaStatus.end` 事件触发
  /// `_handleEpisodeFinished`；Qt 侧此前没有对应通道，导致 Windows
  /// 播完一集不会自动下一集。
  void Function()? onPlaybackEnded;

  /// 677：房间观众权限（由播放页按 `_canControlPlayback` 注入）。
  ///
  /// 【最后一道防线】即使 QML 漏了 `canControl` 门，这里也直接丢弃
  /// 观众的播放控制意图（与安卓 `_handleNativeUiCommand` 的 622 兜底
  /// 同语义）。
  bool canControlPlayback = true;

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
    _pipe.playback.listen(_applyPlayback);
    _pipe.windowStates.listen(_applyWindowState);
    _pipe.layouts.listen((data) => onSplitLayout?.call(data));
    _pipe.windowMoved.listen((data) => onWindowMoved?.call(data));
    // 683：Qt 窗被抬到前面 → 面板也抬上来（两窗同层，不置顶）
    _pipe.raised.listen((_) => onRaised?.call());
    // 691：自然播完 → 自动切下一集
    _pipe.ended.listen((_) => onPlaybackEnded?.call());
    _pipe.onDisconnected = () {
      if (_disposed) return;
      LogService().log('QtPlayer', 'Qt 进程已退出');
      _setState(AdapterPlaybackState.stopped);
      onProcessExited?.call();
    };
  }

  /// 677：把 Qt 的 `playback` 帧镜像进本地缓存。
  ///
  /// 【绝不能用 setter】`set state` / `set playbackRate` 都会**回发 IPC**
  /// （`setPaused` / `setSpeed`）——收到自己刚发出去的状态再发一遍，
  /// 轻则重复命令，重则状态机自激。这里全部直接写私有字段。
  void _applyPlayback(Map<String, Object?> data) {
    if (_disposed) return;
    final pos = (data['positionMs'] as num?)?.toInt();
    final dur = (data['durationMs'] as num?)?.toInt();
    final paused = data['paused'] as bool?;
    final rate = (data['rate'] as num?)?.toDouble();
    final buffering = data['buffering'] as bool?;

    // 682：**卸载态不接受暂停/播放镜像**。
    //
    // 【真机回归：删除在播资源后 Win 占位文字不出现】`unloadMedia()` 把
    // 状态置 `stopped`，但 Qt 的 `stopPlayback()` 会立刻回一帧
    // `paused:true`（清进度用）→ 旧实现无条件把它翻成 `paused`
    // → `playerReady` 判定「有内容」→ 占位层被隐藏，只剩一片黑。
    // 卸载态下进度/时长仍要清零，但**状态必须保持 stopped**。
    if (!_hasMedia) {
      _positionMs = 0;
      _durationMs = 0;
      _setMediaStatus(AdapterMediaStatus.unloaded);
      _setState(AdapterPlaybackState.stopped);
      return;
    }

    if (pos != null) _positionMs = pos;
    if (dur != null) _durationMs = dur;
    if (rate != null && rate > 0) _playbackRate = rate;
    if (buffering != null) {
      _setMediaStatus(buffering
          ? AdapterMediaStatus.buffering
          : AdapterMediaStatus.loaded);
    }
    if (paused != null) {
      _setState(paused
          ? AdapterPlaybackState.paused
          : AdapterPlaybackState.playing);
    }
  }

  /// 682：是否已加载媒体（`prepare` 后 true、`unloadMedia` 后 false）。
  ///
  /// 【用途】Qt 占位层「请从资源面板选择要播放的内容」的判据。旧实现
  /// 靠 `position >= 0 && (duration > 0 || state != stopped)` 推断——而
  /// `stopPlayback()` 回传的 `paused:true` 会把状态翻成 `paused`，导致
  /// 删空资源后仍判定「有内容」→ 占位不显示（真机回归）。
  bool get hasMedia => _hasMedia && !_disposed;

  /// 677：窗口态（全屏）。
  void _applyWindowState(Map<String, Object?> data) {
    if (_disposed) return;
    final fullscreen = data['fullscreen'] as bool?;
    if (fullscreen == null) return;
    if (fullscreen == _hostFullscreen) return;
    _hostFullscreen = fullscreen;
    onFullscreenChanged?.call(fullscreen);
  }

  /// 677：当前是否全屏（Qt 回传）。
  bool get hostFullscreen => _hostFullscreen;
  bool _hostFullscreen = false;

  /// 677：请求 Qt 全屏/退出全屏（房间并排与全屏互斥）。
  void setHostFullscreen(bool fullscreen) {
    if (_disposed) return;
    _pipe.sendCommandRaw({
      'type': 'setHostFullscreen',
      'fullscreen': fullscreen,
    });
  }

  /// 682：置顶开关（房间并排时与 Flutter 面板窗同层）。
  ///
  /// 【为什么需要】并排是两个独立顶层窗。普通 z-order 下用户切到别的
  /// 软件时可能只盖住其中一个 → 观感「一个被盖、一个没被盖」。
  /// 两窗同时置顶后要么都在上层，要么被另一个置顶窗一起盖住。
  /// 全屏时关闭（用户明确例外：全屏独占屏幕）。
  void setTopmost(bool topmost) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'setTopmost', 'topmost': topmost});
  }

  /// 687：按房间态切换窗口边框（单人带三钮 / 房间无边框）。
  ///
  /// 【为什么必须由 Dart 驱动】窗口在起播时就创建了，那时可能还没进房；
  /// 进房/退房是两个明确的时机，由页面在摆位/恢复时各发一次最准确。
  void setRoomChrome(bool room) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'setRoomChrome', 'room': room});
  }

  /// 677：把播放窗拉回最前。
  void focus() {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'focus'});
  }

  /// 677：房间并排摆位（Dart 算矩形、Qt 应用）。
  void setWindowRect({required int x, required int y, required int w, required int h}) {
    if (_disposed) return;
    _pipe.sendCommandRaw({
      'type': 'setWindowRect',
      'x': x,
      'y': y,
      'w': w,
      'h': h,
    });
  }

  /// 680：卸载当前媒体（删除「正在播放的资源」时调用）。
  ///
  /// 【为什么必须有】Qt 接管时真正的播放引擎是 Qt 进程里的 mpv，本页的
  /// `_player` 是空闲引擎——只重置 `_player` 的话，Qt 窗会**继续播放
  /// 已删除的那一集**（真机回归「删除在播资源后视频还在放」）。
  ///
  /// 语义对齐 `MpvPlayerAdapter.unloadMedia()`：清空进度/时长/缓冲、
  /// 状态置 stopped，并让 Qt 侧 `stop` 掉 mpv（卸载媒体、释放解码器）。
  Future<void> unloadMedia() async {
    if (_disposed) return;
    _positionMs = 0;
    _durationMs = 0;
    _bufferedMs = 0;
    _mediaUri = '';
    // 682：先清标志再置状态——Qt 收到 stop 会回 `paused:true`，
    // 标志未清时会被 `_applyPlayback` 翻回 `paused`（占位文字消失）。
    _hasMedia = false;
    _setMediaStatus(AdapterMediaStatus.unloaded);
    _pipe.sendCommandRaw({'type': 'stop'});
    _setState(AdapterPlaybackState.stopped);
    LogService().log('QtPlayer', '已卸载媒体（删除在播资源）');
  }

  /// 677：房间并排跟随开关（Qt 自己读 Flutter 主窗矩形）。
  void setFollowParent(bool enabled) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'setFollowParent', 'enabled': enabled});
  }

  /// 678：临时显示/隐藏 Qt 播放窗（房间弹窗期间让位）。
  ///
  /// 【为什么不用最小化】最小化后 mpv 会停渲染，恢复时要重新起播（黑屏
  /// 一瞬）；直接 `hide`/`show` 保住解码状态，弹窗关掉即恢复画面。
  void setWindowVisible(bool visible) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'setWindowVisible', 'visible': visible});
  }

  /// 677：请求 Qt 按**它自己的 QScreen** 计算并排矩形。
  ///
  /// 【为什么让 Qt 算】`window_manager` 不暴露屏幕工作区（多屏 + DPI
  /// 全靠猜）；Qt 的 `QScreen::availableGeometry()` 是权威值。
  /// Qt 算完通过 `splitLayout` 帧回传，Dart 只负责应用面板侧。
  void requestSplitLayout({
    required int panelWidth,
    required int minVideoWidth,
  }) {
    if (_disposed) return;
    _pipe.sendCommandRaw({
      'type': 'requestSplitLayout',
      'panelWidth': panelWidth,
      'minVideoWidth': minVideoWidth,
    });
  }

  /// 677：并排布局回调（Qt → Dart，`splitLayout` 帧）。
  void Function(Map<String, Object?> layout)? onSplitLayout;

  /// 679：用户拖动/缩放 Qt 窗回调（`windowMoved` 帧）。
  ///
  /// Dart 侧据此把 Flutter 面板窗跟着挪（双向跟随）。
  void Function(Map<String, Object?> rect)? onWindowMoved;

  /// 679：请求 Qt 开始系统拖动（无边框窗口的顶栏拖拽区）。
  void startSystemMove() {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'startSystemMove'});
  }

  /// 679：请求 Qt 开始边缘拉伸（1=左 2=上 4=右 8=下）。
  void startSystemResize(int edges) {
    if (_disposed) return;
    _pipe.sendCommandRaw({'type': 'startSystemResize', 'edges': edges});
  }

  /// 处理 Qt 发来的命令（`NativePlayerCommand` 的 JSON）。
  ///
  /// 【677 分工重构】播放控制类（播放/暂停/seek/倍速）**不再就地消化**：
  /// Qt 的 QML 早已本地直驱 mpv（`mpvWindow.togglePause()` 等），到这里的
  /// 只是「本地用户意图」。旧实现就地改状态并经 setter 回发 `setPaused`，
  /// 等于把 Qt 刚做的切换又翻一次；同时**完全绕过了房间广播**（房主的
  /// 播放/暂停传不到观众）。
  ///
  /// 现在：意图 → [onTransportIntent] → 播放页（房主广播房间命令 /
  /// 观众丢弃）。切集/选轨/弹幕这类需要 Flutter 逻辑的，仍由
  /// `onNativeUiCommand` 链路处理（与安卓/鸿蒙一致）。
  void _handleCommand(Map<String, Object?> cmd) {
    final type = cmd['type'] as String?;
    switch (type) {
      case 'togglePlay':
      case 'seekTo':
      case 'seekRelative':
      case 'setSpeed':
        // 677：房间观众一律丢弃播放控制意图（622 兜底的 Qt 版）。
        if (!canControlPlayback) {
          LogService().log('QtPlayer', '观众无权执行播放控制: $type');
          return;
        }
        _emitTransportIntent(type!, cmd);
      case 'setVolume':
        // 音量是**本地 UI**（不影响房间同步），两端都允许。
        volume = (cmd['volume'] as num?)?.toDouble() ?? 1.0;
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

  /// 677：把 Qt 的用户动作翻译成 [QtTransportIntent] 上报。
  void _emitTransportIntent(String type, Map<String, Object?> cmd) {
    final sink = onTransportIntent;
    if (sink == null) {
      LogService().log('QtPlayer', '播放意图无消费方: $type');
      return;
    }
    switch (type) {
      case 'togglePlay':
        // 以 Qt 本地刚执行完的目标态为准：QML 先 `mpvWindow.togglePause()`
        // 再发命令，本地 `_state` 可能还没被 playback 帧刷新，所以按
        // 「取反当前镜像」推断目标态，并**立即本地镜像**（不回发 IPC）。
        final willPlay = _state != AdapterPlaybackState.playing;
        _setState(willPlay
            ? AdapterPlaybackState.playing
            : AdapterPlaybackState.paused);
        sink(QtTransportIntent.playPause(playing: willPlay, positionMs: _positionMs));
      case 'seekTo':
        final ms = (cmd['positionMs'] as num?)?.toInt() ?? 0;
        _positionMs = ms;
        sink(QtTransportIntent.seek(positionMs: ms));
      case 'seekRelative':
        final delta = (cmd['deltaMs'] as num?)?.toInt() ?? 0;
        final target = (_positionMs + delta).clamp(0, 1 << 40);
        _positionMs = target;
        sink(QtTransportIntent.seek(positionMs: target));
      case 'setSpeed':
        final speed = (cmd['speed'] as num?)?.toDouble() ?? 1.0;
        _playbackRate = speed;
        sink(QtTransportIntent.rate(speed: speed));
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
    // 682：先置「有媒体」再发 load——Qt 起播后会回 `paused:false`，
    // 标志未置位时会被 `_applyPlayback` 的卸载态分支吞掉。
    _hasMedia = true;
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

/// 677：Qt 播放窗的用户**播放控制意图**。
///
/// 【为什么单独建类型而不是复用 NativePlayerCommand】
/// 1. `NativePlayerCommand` 表达的是「请执行这个动作」，而这里表达的是
///    「用户**已经在 Qt 本地执行完了**，现在只需要记账/广播」——两者
///    语义相反，混用会重复执行（Qt 已 toggle，Dart 再 toggle 一次）。
/// 2. 房间广播需要的参数（position/rate）在这里是必填的，命令类型里
///    是可选 payload。
sealed class QtTransportIntent {
  const QtTransportIntent();

  /// 播放/暂停（[playing] = 执行后的目标态）。
  const factory QtTransportIntent.playPause({
    required bool playing,
    required int positionMs,
  }) = QtPlayPauseIntent;

  /// 跳转（绝对位置，毫秒）。
  const factory QtTransportIntent.seek({required int positionMs}) =
      QtSeekIntent;

  /// 倍速。
  const factory QtTransportIntent.rate({required double speed}) = QtRateIntent;
}

class QtPlayPauseIntent extends QtTransportIntent {
  const QtPlayPauseIntent({required this.playing, required this.positionMs});
  final bool playing;
  final int positionMs;
}

class QtSeekIntent extends QtTransportIntent {
  const QtSeekIntent({required this.positionMs});
  final int positionMs;
}

class QtRateIntent extends QtTransportIntent {
  const QtRateIntent({required this.speed});
  final double speed;
}
