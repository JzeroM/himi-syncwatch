import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/room_panel_layout.dart';
import 'package:himi_syncwatch/services/platform/windows_window_style.dart';

/// 677：Windows Qt 播放器**房间模式**。
///
/// ## 本组测试覆盖什么
///
/// 房间模式的三条主干：
///   1. **播放态回传**：Qt 接管后 mpv 在 Qt 进程，Flutter 的 `_player`
///      是从未起播的空闲引擎 → 心跳/广播必须改读真实引擎（`_roomEngine`）
///   2. **观众权限**：对齐安卓/鸿蒙「隐藏但占位」（`canControl` /
///      `segmentEnabled`）
///   3. **全屏 × 并排互斥**：Esc 统一拦截、退全屏回并排矩形、摆位去重
///
/// 另外覆盖 Dart 侧的并排摆位纯函数（`RoomPanelLayout`）。
void main() {
  const dir = 'native/windows_qt_player';
  String read(String p) => File(p).readAsStringSync();

  late String mpvH;
  late String mpvCpp;
  late String mainCpp;
  late String pipeH;
  late String pipeCpp;
  late String stateH;
  late String stateCpp;
  late String pipeDart;
  late String adapterDart;
  late String playerScreen;
  late String bottomBar;
  late String topBar;
  late String overlayQml;
  late String mainQml;
  late String shortcutsQml;
  late String gesturesQml;
  late String sliderQml;

  setUpAll(() {
    mpvH = read('$dir/src/mpv_window.h');
    mpvCpp = read('$dir/src/mpv_window.cpp');
    mainCpp = read('$dir/src/main.cpp');
    pipeH = read('$dir/src/pipe_server.h');
    pipeCpp = read('$dir/src/pipe_server.cpp');
    stateH = read('$dir/src/player_state.h');
    stateCpp = read('$dir/src/player_state.cpp');
    pipeDart = read('lib/services/player/qt_player_pipe.dart');
    adapterDart = read('lib/services/player/qt_player_adapter.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
    bottomBar = read('$dir/src/qml/BottomBar.qml');
    topBar = read('$dir/src/qml/TopBar.qml');
    overlayQml = read('$dir/src/qml/Overlay.qml');
    mainQml = read('$dir/src/qml/Main.qml');
    shortcutsQml = read('$dir/src/qml/PlayerShortcuts.qml');
    gesturesQml = read('$dir/src/qml/VideoGestures.qml');
    sliderQml = read('$dir/src/qml/PlayerSlider.qml');
  });

  // ═══════════════════════════════════════════════════════════════
  // A. 播放态回传（Qt → Dart `playback` 帧）
  // ═══════════════════════════════════════════════════════════════

  group('A 播放态回传（Qt → Dart）', () {
    test('A1 协议新增 playback / windowState / splitLayout 三种出站帧', () {
      // Qt 侧发送端
      expect(pipeH, contains('sendPlayback'));
      expect(pipeH, contains('sendWindowState'));
      expect(pipeH, contains('sendSplitLayout'));
      expect(pipeCpp, contains('"playback"'));
      expect(pipeCpp, contains('"windowState"'));
      expect(pipeCpp, contains('"splitLayout"'));
      // Dart 侧接收端
      expect(pipeDart, contains("type == 'playback'"));
      expect(pipeDart, contains("type == 'windowState'"));
      expect(pipeDart, contains("type == 'splitLayout'"));
      expect(pipeDart, contains('Stream<Map<String, Object?>> get playback'));
      expect(pipeDart, contains('Stream<Map<String, Object?>> get windowStates'));
      expect(pipeDart, contains('Stream<Map<String, Object?>> get layouts'));
    });

    test('A2 playback 帧带全量播放态（位置/时长/暂停/倍速/缓冲）', () {
      for (final key in [
        'positionMs',
        'durationMs',
        'paused',
        'rate',
        'buffering',
      ]) {
        expect(mainCpp, contains('QStringLiteral("$key")'),
            reason: 'playback 帧缺 $key');
      }
    });

    test('A3 节流 200ms + 暂停边沿立即 flush', () {
      // 位置高频 → 节流；暂停是边沿 → 立刻发（否则观众最多等 200ms）
      expect(mainCpp, contains('setInterval(200)'));
      expect(mainCpp, contains('setSingleShot(true)'));
      // pausedChanged 直连 pipe（不经节流定时器）
      expect(
        mainCpp,
        contains('QObject::connect(&mpv, &MpvWindow::pausedChanged, &app'),
      );
    });

    test('A4 Dart 镜像播放态**绝不回发 IPC**（防自激）', () {
      // 必须直接写私有字段，不能走 setter（setter 会 sendCommandRaw）
      final applyBody = _extract(adapterDart, 'void _applyPlayback(');
      expect(applyBody, contains('_positionMs = pos'));
      expect(applyBody, contains('_durationMs = dur'));
      expect(applyBody, contains('_playbackRate = rate'));
      expect(applyBody, contains('_setState('));
      // 绝不能出现 setter 赋值（`state = ` / `playbackRate = `）——
      // 用「行首无下划线」精确判定（`_playbackRate = rate` 是合法镜像）
      expect(applyBody, isNot(contains(RegExp(r'(?<![_\w])state = '))));
      expect(
        applyBody,
        isNot(contains(RegExp(r'(?<![_\w])playbackRate = '))),
      );
      expect(applyBody, isNot(contains('sendCommandRaw')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 房间引擎门面（读真实引擎）
  // ═══════════════════════════════════════════════════════════════

  group('B 房间引擎门面', () {
    test('B1 _roomEngine 在 Qt 存活时返回 Qt 适配器', () {
      expect(playerScreen, contains('PlayerAdapter get _roomEngine'));
      final body = _extract(playerScreen, 'PlayerAdapter get _roomEngine');
      expect(body, contains('MpvSessionPlatform.activeQtAdapter'));
      expect(body, contains('qt.isAlive'));
      expect(body, contains('return _player'));
    });

    test('B2 心跳读真实引擎（房主 position 不再恒 0）', () {
      final body = _extract(playerScreen, 'void _startHeartbeat()');
      expect(body, contains('final engine = _roomEngine'));
      expect(body, contains('engine.position / 1000.0'));
      expect(body, contains('engine.state == AdapterPlaybackState.playing'));
      expect(body, contains('engine.playbackRate'));
    });

    test('B3 观众纠偏作用在真实引擎（seek/rate/state 全部）', () {
      final body = _extract(playerScreen, 'void _handleHeartbeat');
      expect(body, contains('final engine = _roomEngine'));
      expect(body, contains('engine.seek('));
      expect(body, contains('engine.playbackRate = 1.02'));
      expect(body, contains('engine.state = AdapterPlaybackState'));
    });

    test('B4 房间命令下发作用在真实引擎', () {
      final body = _extract(playerScreen, 'void _handleCommand');
      expect(body, contains('final engine = _roomEngine'));
      expect(body, contains('engine.seek('));
      expect(body, contains('engine.state = AdapterPlaybackState.playing'));
      expect(body, contains('engine.playbackRate = r'));
    });

    test('B5 房主广播/切集 syncPlay 读真实引擎', () {
      // _broadcastRoomInfo 的 paused
      final bcast = _extract(playerScreen, 'Future<void> _broadcastRoomInfo(');
      expect(bcast, contains('_roomEngine.state'));
      // _switchToEpisode 的 position
      final sw = _extract(playerScreen, 'Future<void> _switchToEpisode(');
      expect(sw, contains('_roomEngine.position / 1000.0'));
    });

    test('B6 _syncPlayState / _seekGuarded 房间路径走真实引擎', () {
      final sync = _extract(playerScreen, 'void _syncPlayState()');
      expect(sync, contains('widget.roomCode == null ? _player : _roomEngine'));
      final seek = _extract(playerScreen, 'Future<void> _seekGuarded');
      expect(
        seek,
        contains('widget.roomCode == null ? _player : _roomEngine'),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 用户意图转发（房主广播 / 观众丢弃）
  // ═══════════════════════════════════════════════════════════════

  group('C 用户意图转发', () {
    test('C1 适配器把 transport 命令改成「上报意图」而非就地消化', () {
      final body = _extract(adapterDart, 'void _handleCommand');
      // 四个 transport 类型合并到同一分支
      expect(body, contains("case 'togglePlay':"));
      expect(body, contains("case 'seekTo':"));
      expect(body, contains("case 'seekRelative':"));
      expect(body, contains("case 'setSpeed':"));
      expect(body, contains('_emitTransportIntent'));
      // 不能再出现「就地赋值 state =」（旧实现会回发 setPaused）
      expect(body, isNot(contains('state = _state ==')));
    });

    test('C2 观众意图在适配器层直接丢弃（622 兜底的 Qt 版）', () {
      final body = _extract(adapterDart, 'void _handleCommand');
      expect(body, contains('if (!canControlPlayback)'));
      expect(body, contains('观众无权执行播放控制'));
    });

    test('C3 意图类型齐全（playPause / seek / rate）', () {
      expect(adapterDart, contains('sealed class QtTransportIntent'));
      expect(adapterDart, contains('QtPlayPauseIntent'));
      expect(adapterDart, contains('QtSeekIntent'));
      expect(adapterDart, contains('QtRateIntent'));
    });

    test('C4 房主意图转成房间命令（play/pause/seek/rate 四类）', () {
      final body = _extract(playerScreen, 'void _handleQtTransportIntent');
      expect(body, contains('AppConstants.actionPlay'));
      expect(body, contains('AppConstants.actionPause'));
      expect(body, contains('AppConstants.actionSeek'));
      // 房间协议里 rate 此前是「只收不发」的死代码
      expect(body, contains('AppConstants.actionRate'));
      expect(body, contains('if (!_canControlPlayback) return'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 观众权限（对齐安卓 / 鸿蒙）
  // ═══════════════════════════════════════════════════════════════

  group('D 观众权限（对齐安卓/鸿蒙）', () {
    test('D1 Qt PlayerState 补 canControl / segmentEnabled 字段', () {
      // Dart 早就在发，Qt 此前从未解析 → QML 无门可依
      expect(stateH, contains('Q_PROPERTY(bool canControl READ canControl'));
      expect(stateH, contains('Q_PROPERTY(bool segmentEnabled READ segmentEnabled'));
      expect(stateH, contains('bool canControl() const'));
      expect(stateH, contains('bool segmentEnabled() const'));
      expect(stateCpp, contains('readBool(json, "canControl"'));
      expect(stateCpp, contains('readBool(json, "segmentEnabled"'));
    });

    test('D2 底栏传输组隐藏占位（不塌、不位移）', () {
      // 对齐安卓 INVISIBLE / 鸿蒙 Visibility.Hidden：opacity 而非 visible
      expect(bottomBar, contains('opacity: playerState.canControl ? 1.0 : 0.0'));
      expect(bottomBar, contains('enabled: playerState.canControl'));
    });

    test('D3 进度条 interactive 门（不可点/不可拖）', () {
      expect(bottomBar, contains('interactive: playerState.canControl'));
      expect(sliderQml, contains('property bool interactive: true'));
      expect(sliderQml, contains('enabled: root.interactive'));
    });

    test('D4 双击/空格/方向键加 canControl 门', () {
      final dbl = _extract(gesturesQml, 'onDoubleClicked');
      expect(dbl, contains('if (!playerState.canControl) return'));
      expect(shortcutsQml, contains('if (!playerState.canControl) return'));
      // 空格与左右键共三处门
      final gates = RegExp(r'if \(!playerState\.canControl\) return')
          .allMatches(shortcutsQml)
          .length;
      expect(gates, greaterThanOrEqualTo(3));
    });

    test('D5 右键片头片尾走 segmentEnabled 门', () {
      expect(gesturesQml, contains('playerState.segmentEnabled'));
    });

    test('D6 选集面板点集 / 自动下一集 / 跳过胶囊加门', () {
      final panel = _extract(overlayQml, 'function handlePanelItem');
      expect(panel, contains('if (!playerState.canControl) return'));
      final ended = _extract(overlayQml, 'function onPlaybackEnded');
      expect(ended, contains('if (!playerState.canControl) return'));
      final skip = _extract(overlayQml, 'function skipSegmentLocal');
      expect(skip, contains('if (!playerState.canControl) return'));
    });

    test('D7 顶栏画面比例房间隐藏（对齐两端 !isRoom）', () {
      final fit = _extract(topBar, '// 画面比例（图标随模式）');
      expect(fit, contains('visible: !playerState.isRoom'));
    });

    test('D8 本地 UI 类控件**保留**（全屏/音量/弹幕/字幕/音轨/解码）', () {
      // 全屏按钮无 canControl 门（两端都保留）
      final full = _extract(bottomBar, '// 窗口全屏（仅底栏，用户明确）');
      expect(full, isNot(contains('canControl')));
      // 字幕/音轨/解码面板也不受限
      final panel = _extract(overlayQml, 'function handlePanelItem');
      final audioBranch = panel.substring(panel.indexOf('音轨'));
      expect(audioBranch, contains('selectAudio'));
      expect(panel.substring(panel.indexOf('解码方式')),
          contains('setDecodeMode'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. 全屏 × 房间并排互斥
  // ═══════════════════════════════════════════════════════════════

  group('E 全屏与并排互斥', () {
    test('E1 全屏态提升为 Q_PROPERTY（图标双向可绑定）', () {
      expect(mpvH, contains('Q_PROPERTY(bool hostFullscreen'));
      expect(mpvH, contains('hostFullscreenChanged'));
      // 按钮图标双向
      expect(bottomBar, contains('Icons.closeFullscreen'));
      expect(bottomBar, contains('mpvWindow.hostFullscreen'));
    });

    test('E2 两处 QML Escape Shortcut 已删除，改 C++ 统一拦截', () {
      // 真凶：Main.qml 的 Esc 是 requestExit+Qt.quit()，全屏下直接退进程
      expect(mainQml, isNot(contains('sequence: "Escape"')));
      expect(overlayQml, isNot(contains('sequence: "Escape"')));
      // C++ 统一拦截 + 信号
      expect(mpvH, contains('void escapePressed()'));
      expect(mainCpp, contains('installEventFilter'));
      expect(mainCpp, contains('Qt::Key_Escape'));
    });

    test('E3 三层语义保留（收面板 → 退全屏 → 请求退出）', () {
      final body = _extract(overlayQml, 'function onEscapePressed');
      expect(body, contains('root.closePanels()'));
      expect(body, contains('mpvWindow.isHostFullscreen()'));
      expect(body, contains('requestExit'));
      // 房间模式不本地 quit（交给 Dart 弹确认框）
      expect(body, contains('if (!playerState.isRoom) Qt.quit()'));
    });

    test('E4 退全屏显式回并排矩形（不落回 Qt 记忆的旧位置）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::setHostFullscreen');
      expect(body, contains('splitRect_'));
      expect(body, contains('host_->setGeometry(splitRect_)'));
      expect(body, contains('hasSplitRect_'));
    });

    test('E5 全屏中收到**不同**摆位 → 自动退全屏；相同则忽略', () {
      final body = _extract(mpvCpp, 'void MpvWindow::setWindowRect');
      // 去重（面板刷新重发不会误退）
      expect(body, contains('splitRect_ == next'));
      // 不同则先退全屏
      expect(body, contains('isHostFullscreen()'));
      expect(body, contains('showNormal()'));
    });

    test('E6 全屏切换后立即重贴悬浮层（控件不被视频盖住）', () {
      expect(mainCpp, contains('hostFullscreenChanged'));
      expect(mainCpp, contains('syncOverlayGeometry();'));
      expect(mainCpp, contains('overlay->raise()'));
    });

    test('E7 F11 与 F 并存', () {
      expect(shortcutsQml, contains('sequence: "F11"'));
      expect(shortcutsQml, contains('sequence: "F"'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // F. 房间并排跟随（Qt 自跟随）
  // ═══════════════════════════════════════════════════════════════

  group('F 房间并排跟随', () {
    test('F1 Qt 用 --parent-pid + 类名定位 Flutter 主窗', () {
      expect(mpvH, contains('HWND findParentWindow()'));
      expect(mpvCpp, contains('EnumWindows'));
      expect(mpvCpp, contains('FLUTTER_RUNNER_WIN32_WINDOW'));
      expect(mpvCpp, contains('GetWindowThreadProcessId'));
    });

    test('F2 跟随用 DwmGetWindowAttribute 取真实可见边界', () {
      // GetWindowRect 含 Win10/11 不可见边框 + 阴影 → 两窗重叠一条缝
      expect(mpvCpp, contains('DwmGetWindowAttribute'));
      expect(mpvCpp, contains('DWMWA_EXTENDED_FRAME_BOUNDS'));
    });

    test('F3 DPI 物理像素 → 逻辑像素换算', () {
      // Qt 6 的 QScreen 几何是逻辑像素，GetWindowRect 是物理像素
      expect(mpvCpp, contains('devicePixelRatio()'));
      expect(mpvCpp, contains('parentLogical'));
    });

    test('F4 跟随只在矩形变化时才动（零抖动）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      expect(body, contains('if (next == lastFollowRect_) return'));
    });

    test('F5 全屏时跳过跟随（覆盖 Flutter 窗，用户明确例外）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      expect(body, contains('if (isHostFullscreen()) return'));
    });

    test('F6 主窗最小化时保持上一有效矩形（不隐藏视频）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      expect(body, contains('IsIconic(parent)'));
    });

    test('F7 总宽不超屏：Qt 保底最小宽 + 主窗最大尺寸受限', () {
      final follow = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      expect(follow, contains('kMinWidth'));
      final split = _extract(mpvCpp, 'void MpvWindow::requestSplitLayout');
      expect(split, contains('minVideoWidth'));
      expect(split, contains('maxPanelW'));
    });

    test('F8 50ms 节拍驱动跟随（复用现有 syncTimer）', () {
      expect(mainCpp, contains('followParentOncePublic'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // G. 房间面板态 + 切集广播 + 退房语义
  // ═══════════════════════════════════════════════════════════════

  group('G 房间面板态与退房', () {
    test('G1 房间模式不 attach QtPlayerSession（否则切集不广播）', () {
      // 真凶：Session 接管 onNativeUiCommand 后自己消化 SelectEpisode，
      // 不知道房间的存在 → 房主切集不广播 syncPlay/roomInfo
      final body = _extract(playerScreen, 'Future<bool> _startQtPlayer(');
      expect(body, contains('if (widget.roomCode != null)'));
      expect(body, contains('_wireRoomQtAdapter(adapter)'));
      // 房间分支必须在 attach 之前 return
      final roomIdx = body.indexOf('_wireRoomQtAdapter(adapter)');
      final attachIdx = body.indexOf('QtPlayerSession.attach');
      expect(roomIdx, greaterThan(0));
      expect(attachIdx, greaterThan(roomIdx));
    });

    test('G2 房间接线注入权限 + 意图 + 摆位', () {
      final body = _extract(playerScreen, 'void _wireRoomQtAdapter');
      expect(body, contains('adapter.canControlPlayback = _canControlPlayback'));
      expect(body, contains('adapter.onTransportIntent'));
      expect(body, contains('adapter.onSplitLayout'));
      expect(body, contains('_enterRoomSplitLayout'));
    });

    test('G3 面板态：全窗渲染房间面板，不渲染视频区', () {
      expect(playerScreen, contains('bool get _roomPanelMode'));
      expect(playerScreen, contains('Widget _buildRoomPanelOnly'));
      final body = _extract(playerScreen, 'Widget _buildRoomPanelOnly');
      expect(body, contains('_buildResourcePanel()'));
      // 实底（路由 opaque:false，详情页会透出）
      expect(body, contains('backgroundColor'));
    });

    test('G4 房间面板态在 _qtUiHidden 之后判定（单人仍隐身）', () {
      final build = _extract(playerScreen, 'Widget build(BuildContext context)');
      final hiddenIdx = build.indexOf('if (_qtUiHidden)');
      final roomIdx = build.indexOf('if (_roomPanelMode)');
      expect(hiddenIdx, greaterThan(0));
      expect(roomIdx, greaterThan(hiddenIdx));
    });

    test('G5 退房恢复主窗（并排摆位清理）', () {
      expect(playerScreen, contains('Future<void> _exitRoomSplitLayout'));
      expect(playerScreen, contains('_roomRestoreBounds'));
      final body = _extract(playerScreen, 'Future<void> _exitRoomSplitLayout');
      expect(body, contains('setFollowParent(false)'));
      expect(body, contains('setMaximumSize'));
      // 桌面断点保护（恢复值过窄会触发手机布局）
      expect(body, contains('kShellDesktopBreakpoint'));
    });

    test('G6 房间 RequestExit 走「解散/离开房间」确认', () {
      final body = _extract(playerScreen, 'Future<void> _handleNativeUiCommand');
      expect(body, contains('command is RequestExit'));
      expect(body, contains('_confirmLeaveRoom'));
      // 取消则把 Qt 窗拉回最前
      expect(body, contains('focus()'));
    });

    test('G7 房间资源面板点集加权限门', () {
      // 观众只读：面板点击不生效（命令层之外的第二道门）
      final body = _extract(playerScreen, 'Widget _buildEpisodeListItem');
      expect(body, contains('if (!_isHost) return'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // H. Dart 侧并排摆位纯函数
  // ═══════════════════════════════════════════════════════════════

  group('H 并排摆位纯函数', () {
    test('H1 标准屏：面板贴右、视频占左', () {
      final layout = RoomPanelLayout.compute(
        workArea: const Rect.fromLTWH(0, 0, 1920, 1040),
        currentBounds: const Rect.fromLTWH(100, 100, 1280, 720),
      );
      expect(layout, isNotNull);
      expect(layout!.panelBounds.width, RoomPanelLayout.panelWidth);
      expect(layout.panelBounds.right, 1920);
      expect(layout.videoRect.width, 1920 - RoomPanelLayout.panelWidth);
      expect(layout.videoRect.left, 0);
      // 退房恢复原 bounds
      expect(layout.restoreBounds, const Rect.fromLTWH(100, 100, 1280, 720));
    });

    test('H2 纵向占满工作区（房间面板是列表，越高越好用）', () {
      final layout = RoomPanelLayout.compute(
        workArea: const Rect.fromLTWH(0, 40, 1920, 1000),
        currentBounds: Rect.zero,
      );
      expect(layout!.panelBounds.top, 40);
      expect(layout.panelBounds.height, 1000);
      expect(layout.videoRect.height, 1000);
    });

    test('H3 窄屏放得下时保持标准面板宽（不无谓压缩）', () {
      final layout = RoomPanelLayout.compute(
        workArea: const Rect.fromLTWH(0, 0, 900, 700),
        currentBounds: Rect.zero,
      );
      // 380 + 480 = 860 ≤ 900 → 保持 380，视频区 520
      expect(layout!.panelBounds.width, RoomPanelLayout.panelWidth);
      expect(layout.videoRect.width, 520);
    });

    test('H3b 真正放不下时才压缩面板（不低于 300）', () {
      final layout = RoomPanelLayout.compute(
        workArea: const Rect.fromLTWH(0, 0, 820, 700),
        currentBounds: Rect.zero,
      );
      // 380 + 480 = 860 > 820 → 面板压到 340，视频区保底 480
      expect(layout!.panelBounds.width, 340);
      expect(layout.videoRect.width, RoomPanelLayout.minVideoWidth);
    });

    test('H4 超窄屏放不下双窗 → 返回 null（调用方退回单窗）', () {
      final layout = RoomPanelLayout.compute(
        workArea: const Rect.fromLTWH(0, 0, 700, 600),
        currentBounds: Rect.zero,
      );
      // 700 - 480 = 220 < 300 → 放弃
      expect(layout, isNull);
    });

    test('H5 工作区无效（0 尺寸）→ null，不崩', () {
      expect(
        RoomPanelLayout.compute(workArea: Rect.zero, currentBounds: Rect.zero),
        isNull,
      );
    });

    test('H6 主窗最大尺寸 = 工作区宽 - Qt 最小宽（连最大化一起受限）', () {
      final size = RoomPanelLayout.maxPanelWindowSize(
        const Rect.fromLTWH(0, 0, 1920, 1040),
      );
      expect(size.width, 1920 - RoomPanelLayout.minVideoWidth);
      expect(size.height, 1040);
    });

    test('H7 最大尺寸不低于面板宽（超宽屏不会小于 380）', () {
      final size = RoomPanelLayout.maxPanelWindowSize(
        const Rect.fromLTWH(0, 0, 800, 600),
      );
      // 800 - 480 = 320 < 380 → 取 380
      expect(size.width, RoomPanelLayout.panelWidth);
    });
  });
  // ═══════════════════════════════════════════════════════════════
  // I. 678：进房即摆位 / 高度跟随 / 不堆叠 / 标题栏
  // ═══════════════════════════════════════════════════════════════

  group('I 进房即摆位与缩放约束', () {
    test('I1 预启动成功即接线摆位（未选片也要摆好）', () {
      // 真机回归：只在 _startQtPlayer（有媒体起播）里接线 → 进房间未选片
      // 时两窗根本没摆好（Qt 默认 1280×720 出现在左上）
      final body = _extract(playerScreen, 'Future<void> _ensureQtPlayerProcess(');
      expect(body, contains('widget.roomCode != null'));
      expect(body, contains('_wireRoomQtAdapter(adapter)'));
      expect(body, contains('setState('));
    });

    test('I2 接线幂等（预启动 + 起播不重复摆位）', () {
      expect(playerScreen, contains('bool _roomQtWired'));
      final body = _extract(playerScreen, 'void _wireRoomQtAdapter');
      expect(body, contains('if (_roomQtWired) return'));
      expect(body, contains('_roomQtWired = true'));
    });

    test('I3 Qt 高度跟随 Flutter 窗（不再固定工作区全高）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      // 纵向取 Flutter 窗 top/bottom 并夹紧到工作区
      expect(body, contains('parentLogical.top()'));
      expect(body, contains('parentLogical.bottom()'));
      expect(body, contains('qMax(parentLogical.top(), work.top())'));
      expect(body, contains('qMin(parentLogical.bottom(), work.bottom())'));
      // 不能再用固定 work.top()/work.height() 作为窗口纵向
      expect(body, isNot(contains('const QRect next(left, work.top()')));
    });

    test('I4 宽度不足时**保持上一有效矩形**（不撑大 → 不堆叠）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      // 真机回归：旧实现会把 w 强行撑到最小宽，越过 Flutter 窗左缘
      // → 面板压在视频上（截图）。现在改为不足即 return（保持不动）。
      expect(body, contains('if (w < kMinWidth) return'));
      // 不得出现「赋值式撑大」（旧写法的特征）
      expect(
        body,
        isNot(contains(RegExp(r'if \(w < kMinWidth\)\s*w\s*='))),
        reason: '撑大 w 会越过 Flutter 窗左缘造成两窗堆叠',
      );
      expect(mpvCpp, contains('constexpr int kMinWidth = 480'));
    });

    test('I5 高度不足时同样保持不动（不闪不叠）', () {
      final body = _extract(mpvCpp, 'void MpvWindow::followParentOnce');
      expect(body, contains('if (h < kMinHeight) return'));
      expect(body, contains('kMinHeight'));
    });

    test('I6 面板窗最小尺寸注入（320×500）', () {
      final body = _extract(playerScreen, 'Future<void> _applyRoomSplitLayout');
      expect(body, contains('setMinimumSize'));
      expect(body, contains('RoomPanelLayout.minPanelWidth'));
      expect(body, contains('RoomPanelLayout.minPanelHeight'));
      // 常量值必须与 Qt 侧一致
      expect(RoomPanelLayout.minPanelWidth, 320);
      expect(RoomPanelLayout.minPanelHeight, 500);
      // Qt 侧 kMinPanelWidth 与 Dart 对齐
      expect(mpvCpp, contains('kMinPanelWidth = 320'));
    });

    test('I7 退房放开最小/最大尺寸限制', () {
      final body = _extract(playerScreen, 'Future<void> _exitRoomSplitLayout');
      expect(body, contains('setMaximumSize'));
      expect(body, contains('setMinimumSize'));
      expect(body, contains('_roomQtWired = false'));
    });

    test('I8 房间模式去掉最大化/最小化按钮', () {
      final body = _extract(playerScreen, 'Future<void> _applyRoomSplitLayout');
      expect(body, contains('WindowsWindowStyle.setRoomChrome(true)'));
      final exit = _extract(playerScreen, 'Future<void> _exitRoomSplitLayout');
      expect(exit, contains('WindowsWindowStyle.setRoomChrome(false)'));
    });

    test('I9 标题栏样式位运算正确（去/恢复 MAXIMIZEBOX+MINIMIZEBOX）', () {
      // WS_MAXIMIZEBOX = 0x10000, WS_MINIMIZEBOX = 0x20000
      const withBoxes = 0x00CF0000;  // 含两个按钮
      final stripped = WindowsWindowStyle.stripMaxMinBoxes(withBoxes);
      expect(stripped & 0x00010000, 0, reason: 'WS_MAXIMIZEBOX 未清除');
      expect(stripped & 0x00020000, 0, reason: 'WS_MINIMIZEBOX 未清除');
      // 其它位不动（WS_THICKFRAME 拖边缩放必须保留）
      expect(stripped & 0x00040000, isNot(0), reason: 'WS_THICKFRAME 被误删');
      // 恢复
      final restored = WindowsWindowStyle.restoreMaxMinBoxes(stripped);
      expect(restored, withBoxes);
      expect(WindowsWindowStyle.hasMaxMinBoxes(withBoxes), isTrue);
      expect(WindowsWindowStyle.hasMaxMinBoxes(stripped), isFalse);
    });

    test('I10 标题栏调整发 SWP_FRAMECHANGED（否则按钮不刷新）', () {
      final src = read('lib/services/platform/windows_window_style.dart');
      expect(src, contains('SWP_FRAMECHANGED'));
      expect(src, contains('SetWindowPos'));
      expect(src, contains('FLUTTER_RUNNER_WIN32_WINDOW'));
      // 保留关闭按钮：不得碰 WS_SYSMENU
      expect(src, isNot(contains('WS_SYSMENU')));
    });

    test('I11 找不到主窗时静默跳过（不影响房间功能）', () {
      final src = read('lib/services/platform/windows_window_style.dart');
      expect(src, contains('未找到主窗口'));
      expect(src, contains('catch (e)'));
    });
  });
  // ═══════════════════════════════════════════════════════════════
  // J. 678：房间分享控件 / Qt 播放窗内资源面板
  // ═══════════════════════════════════════════════════════════════

  group('J 房间分享与 Qt 资源面板', () {
    test('J1 资源面板头部含分享按钮（仅房主）', () {
      final body = _extract(playerScreen, 'Widget _buildResourcePanel()');
      expect(body, contains('Icons.share'));
      expect(body, contains('_showShareRoomDialog'));
      // 观众隐藏（对齐 Flutter 顶栏 showShare + 安卓/鸿蒙同款）
      expect(body, contains('_roomData != null && _isHost'));
    });

    test('J2 分享弹窗期间 Qt 播放窗让位（否则弹窗被顶层窗盖住）', () {
      final body = _extract(playerScreen, 'Future<void> _showShareRoomDialog()');
      expect(body, contains('_suspendQtForDialog'));
      expect(body, contains('_resumeQtAfterDialog'));
      final suspend = _extract(playerScreen, 'Future<bool> _suspendQtForDialog()');
      expect(suspend, contains('setWindowVisible(false)'));
      final resume = _extract(playerScreen, 'Future<void> _resumeQtAfterDialog');
      expect(resume, contains('setWindowVisible(true)'));
      expect(resume, contains('focus()'));
    });

    test('J3 Qt 适配器与 C++ 支持 setWindowVisible 命令', () {
      expect(adapterDart, contains('void setWindowVisible(bool visible)'));
      expect(adapterDart, contains("'type': 'setWindowVisible'"));
      expect(mpvH, contains('Q_INVOKABLE void setWindowVisible(bool visible)'));
      expect(mpvCpp, contains('void MpvWindow::setWindowVisible'));
      expect(mainCpp, contains('setWindowVisible'));
    });

    test('J4 Qt PlayerState 补房间面板字段', () {
      for (final f in [
        'Q_PROPERTY(QString roomCode',
        'Q_PROPERTY(QString audienceName',
        'Q_PROPERTY(QVariantList resourceGroups',
        'Q_PROPERTY(QVariantList broadcasts',
        'Q_PROPERTY(bool resourcePanelOpen',
      ]) {
        expect(stateH, contains(f), reason: 'PlayerState 缺 $f');
      }
      // 解析
      expect(stateCpp, contains('setResourceGroups'));
      expect(stateCpp, contains('setBroadcasts'));
      expect(stateCpp, contains('readBool(json, "resourcePanelOpen"'));
    });

    test('J5 Qt 房间面板 QML 存在并接入 Overlay', () {
      final roomPanel = read('$dir/src/qml/RoomPanel.qml');
      expect(roomPanel, contains('playerState.resourceGroups'));
      expect(roomPanel, contains('playerState.broadcasts'));
      expect(roomPanel, contains('playerState.onlineUserCount'));
      expect(roomPanel, contains('playerState.isHost'));
      // 观众只读
      expect(roomPanel, contains('if (!playerState.canControl) return'));
      // 命令参数与 Dart NativePlayerCommand 一致
      expect(roomPanel, contains('"type": "toggleResourceGroup", "index"'));
      expect(roomPanel, contains('"groupIndex"'));
      expect(roomPanel, contains('"seasonIndex"'));
      // 加资源命令在 Overlay 装配处（RoomPanel 只发信号）
      expect(overlayQml, contains('"type": "openResourceSearch"'));
      // Overlay 装配
      expect(overlayQml, contains('RoomPanel {'));
      // CMake 注册
      expect(read('$dir/CMakeLists.txt'), contains('RoomPanel'));
    });

    test('J6 底栏房间面板开关（仅房间模式）', () {
      expect(bottomBar, contains('playerState.resourcePanelOpen'));
      expect(bottomBar, contains('"type": "toggleResourcePanel"'));
      // 该按钮必须由 isRoom 门控
      final idx = bottomBar.indexOf('"type": "toggleResourcePanel"');
      expect(idx, greaterThan(0));
      final before = bottomBar.substring(0, idx);
      final lastVisible = before.lastIndexOf('visible: playerState.isRoom');
      expect(lastVisible, greaterThan(0));
    });

    test('J7 面板显隐由 Dart 的 resourcePanelOpen 驱动', () {
      final roomPanel = read('$dir/src/qml/RoomPanel.qml');
      expect(roomPanel, contains('property bool open: playerState.isRoom'));
      expect(roomPanel, contains('playerState.resourcePanelOpen'));
      expect(roomPanel, contains('visible: open'));
    });

    test('J8 RoomPanel 必须同时进 QML_FILES 与 alias 循环', () {
      // 【CI 真机回归 43044933527】只加 alias 循环、漏加 QML_FILES →
      // 文件不进 qrc → `RoomPanel is not a type`（冒烟退出码 -5）。
      final cmake = read('$dir/CMakeLists.txt');
      final qmlFilesBlock = cmake.substring(
        cmake.indexOf('QML_FILES'),
        cmake.indexOf('# ── EvolveUI 资产'),
      );
      expect(qmlFilesBlock, contains('src/qml/RoomPanel.qml'),
          reason: 'RoomPanel.qml 未进 QML_FILES → 不会被打进 qrc');
      // alias 循环里也要有（否则 qrc 路径带 src/qml 前缀）
      final aliasBlock = cmake.substring(
        cmake.indexOf('foreach(_qml Main Overlay'),
        cmake.indexOf('# EvolveUI vendor'),
      );
      expect(aliasBlock, contains('RoomPanel'));
    });
  });
}

/// 从源码里截取一个方法/函数的实现体（按大括号配平）。
///
/// 【必须跳过参数列表里的花括号】Dart 的命名参数写成 `({int? x})`，
/// 直接数 `{` 会在参数列表处误判（`_switchToEpisode` / `_startQtPlayer`
/// 都是这种签名）。这里先走到参数列表结束（括号配平），再开始数花括号。
String _extract(String source, String signature) {
  final idx = source.indexOf(signature);
  if (idx < 0) {
    fail('未找到: $signature');
  }
  // 1. 找到函数体的起始 `{`：括号配平后遇到的第一个 `{`
  var paren = 0;
  var bodyStart = -1;
  for (var i = idx; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') {
      paren++;
    } else if (ch == ')') {
      paren--;
    } else if (ch == '{' && paren == 0) {
      bodyStart = i;
      break;
    } else if (ch == ';' && paren == 0) {
      break; // 声明（无实现体）
    }
  }
  if (bodyStart < 0) return source.substring(idx);
  // 2. 从函数体起始花括号开始配平
  var depth = 0;
  for (var i = bodyStart; i < source.length; i++) {
    final ch = source[i];
    if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return source.substring(idx, i + 1);
    }
  }
  return source.substring(idx);
}
