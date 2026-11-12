import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 689：Windows Qt 播放器缺少「跳过片头/片尾」控件。
///
/// ## 真机现象
///
/// Qt 播放窗里从来没见过「跳过片头」/「跳过片尾」胶囊，但 Android / 鸿蒙
/// 都正常。Qt 侧 `BottomBar.qml` 的胶囊 UI 本身是**存在的**（672 D1 就写了），
/// 所以问题在数据链路。
///
/// ## 三个根因
///
/// ### 1. `_skipPromptSegment` 变化没同步给 Qt
///
/// `skipPrompt` 字段只在 `_syncNativePanelData()` 里推送，而设置/清除
/// 提示时只 `setState`——Qt 永远收不到。
///
/// ### 2. `_positionTimer` 读空闲引擎
///
/// ```dart
/// final pos = _player.position;   // Windows Qt 接管时恒 0
/// _evaluateSkipPrompt(pos);       // → 永远 0，条件永不满足
/// ```
///
/// ### 3. `_skipController.evaluate` 的 `playing` 读空闲引擎
///
/// `_player.state` 恒 `stopped` → 判定「未在播放」→ 提示不触发。
///
/// ## 修复
///
/// 三处全部改读 `_reportEngine`（Windows 且 Qt 存活用 Qt），并在
/// 显示/隐藏提示时补 `_syncNativePanelData()`。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String playerScreen;

  setUpAll(() {
    playerScreen = read('lib/screens/player/player_screen.dart');
  });

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  // ═══════════════════════════════════════════════════════════════
  // A. skipPrompt 推送链路
  // ═══════════════════════════════════════════════════════════════

  group('A skipPrompt 同步给 Qt', () {
    test('A1 显示提示时调用 _syncNativePanelData', () {
      // 找到 _evaluateSkipPrompt 里设置 segment 的位置
      final start = playerScreen.indexOf('_skipPromptSegment = segment;');
      expect(start, greaterThan(0));
      // 该 setState 之后必须紧跟一次推送
      final after = playerScreen.substring(start, start + 600);
      expect(after, contains('_syncNativePanelData()'),
          reason: '只 setState 不推送 → Qt 收不到 skipPrompt');
    });

    test('A2 隐藏提示由 setter 自动推送（无需显式调用）', () {
      // `_skipPromptSegment` 的 setter 内部调 `_syncNativePanelData()`，
      // 所以赋值 null 也会同步给 Qt（与显示侧对称）。
      final start = playerScreen.indexOf('set _skipPromptSegment(');
      expect(start, greaterThan(0));
      final block = playerScreen.substring(start, start + 300);
      expect(block, contains('_syncNativePanelData()'));
    });

    test('A3 skipPrompt 字段映射 intro/outro', () {
      expect(playerScreen, contains("skipPrompt: _skipPromptSegment == null"));
      expect(playerScreen, contains("? ''"));
      expect(playerScreen, contains("? 'intro'"));
      expect(playerScreen, contains(": 'outro'"));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 播放位置读真实引擎（提示的触发源）
  // ═══════════════════════════════════════════════════════════════

  group('B 提示触发源', () {
    test('B1 位置定时器读 _reportEngine（否则恒 0）', () {
      final start = playerScreen.indexOf('_evaluateSkipPrompt(pos);');
      expect(start, greaterThan(0));
      // 往前找 pos 的定义
      final before = playerScreen.substring(start - 900, start);
      expect(before, contains('_reportEngine.position'));
      expect(codeOnly(before), isNot(contains('_player.position')));
    });

    test('B2 evaluate 的 playing 读 _reportEngine', () {
      final start = playerScreen.indexOf('_skipController.evaluate(');
      expect(start, greaterThan(0));
      final block = playerScreen.substring(start, start + 500);
      expect(block, contains('_reportEngine.state'));
      expect(codeOnly(block), isNot(contains('_player.state')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. Qt 侧 UI 已存在（确认不需要新增）
  // ═══════════════════════════════════════════════════════════════

  group('C Qt 侧胶囊 UI', () {
    test('C1 BottomBar 有跳过胶囊（skipPrompt 驱动）', () {
      final bottomBar =
          read('native/windows_qt_player/src/qml/BottomBar.qml');
      expect(bottomBar, contains('id: skipCapsule'));
      expect(bottomBar, contains('playerState.skipPrompt === "intro"'));
      expect(bottomBar, contains('playerState.skipPrompt === "outro"'));
      expect(bottomBar, contains('跳过片头'));
      expect(bottomBar, contains('跳过片尾'));
    });

    test('C2 点击回传 skipSegment 命令', () {
      final bottomBar =
          read('native/windows_qt_player/src/qml/BottomBar.qml');
      expect(bottomBar, contains('skipSegmentClicked'));
      final overlay =
          read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay, contains('onSkipSegmentClicked'));
      expect(overlay, contains('"type": "skipSegment"'));
    });

    test('C3 player_state 已解析 skipPrompt 字段', () {
      final state = read('native/windows_qt_player/src/player_state.h');
      expect(state, contains('Q_PROPERTY(QString skipPrompt'));
    });

    test('C4 Dart 侧 skipSegment 命令有处理分支', () {
      expect(playerScreen, contains('case SkipSegment():'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 跳转与播放控制必须作用于真实引擎
  // ═══════════════════════════════════════════════════════════════

  group('D 操作作用于真实引擎', () {
    test('D1 _seekGuarded 走 _reportEngine（跳过片头才真的跳）', () {
      final start = playerScreen.indexOf('Future<void> _seekGuarded(');
      expect(start, greaterThan(0));
      final block = playerScreen.substring(start, start + 900);
      expect(block, contains('_reportEngine'));
      expect(block, contains('.seek(positionMs: targetMs)'));
      // 旧写法只在房间模式用真实引擎
      expect(codeOnly(block),
          isNot(contains('widget.roomCode == null ? _player : _roomEngine')));
    });

    test('D2 _togglePlayPause 走 _reportEngine', () {
      final start = playerScreen.indexOf('void _togglePlayPause()');
      expect(start, greaterThan(0));
      final block = playerScreen.substring(start, start + 500);
      expect(block, contains('final engine = _reportEngine;'));
      expect(codeOnly(block),
          isNot(contains('widget.roomCode == null ? _player : _roomEngine')));
    });

    test('D3 _syncPlayState 走 _reportEngine', () {
      final start = playerScreen.indexOf('void _syncPlayState()');
      expect(start, greaterThan(0));
      final block = playerScreen.substring(start, start + 400);
      expect(block, contains('final engine = _reportEngine;'));
    });

    test('D4 全文件不再有 roomCode==null?_player 三元（统一口径）', () {
      expect(codeOnly(playerScreen),
          isNot(contains('widget.roomCode == null ? _player : _roomEngine')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. 片头片尾完整链路
  // ═══════════════════════════════════════════════════════════════

  group('E 功能完整性', () {
    test('E1 段数据加载受开关控制', () {
      final start = playerScreen.indexOf('Future<void> _loadSkipSegments(');
      final block = playerScreen.substring(start, start + 600);
      expect(block, contains('skipIntroOutroEnabled'));
    });

    test('E2 自动跳过开关', () {
      expect(playerScreen, contains('bool get _autoSkipSegmentEnabled'));
      expect(playerScreen, contains('autoSkipIntroOutroEnabled'));
    });

    test('E3 片头跳段末 / 片尾进下一集', () {
      final start = playerScreen.indexOf('void _skipSegment(');
      final block = playerScreen.substring(start, start + 1400);
      expect(block, contains('MediaSegmentType.outro'));
      expect(block, contains('_handleEpisodeFinished'));
      expect(block, contains('segment.endMs.clamp'));
    });

    test('E4 8 秒自动消失', () {
      expect(playerScreen, contains('Timer(const Duration(seconds: 8)'));
      expect(playerScreen, contains('_dismissSkipPrompt'));
    });

    test('E5 setter 自动同步原生面板（胶囊与 Dart 同帧）', () {
      final start = playerScreen.indexOf('set _skipPromptSegment(');
      expect(start, greaterThan(0));
      final block = playerScreen.substring(start, start + 300);
      expect(block, contains('_syncNativePanelData()'));
    });
  });
}
