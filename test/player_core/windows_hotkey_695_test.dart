import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/services/player/player_hotkey_bridge.dart';
import 'package:himi_syncwatch/services/room/room_exit_request.dart';
import 'package:himi_syncwatch/widgets/windows_global_hotkeys.dart';

/// 695：Windows MPV 播放器键盘控制（Space=暂停/播放；ESC=退全屏/返回/
/// 房间解散确认）守卫。
///
/// 【背景】
/// - 真机回归「播放窗 Space 暂停/播放现状无效」：QML `Shortcut` 被焦点
///   控件 shortcut-override 吞掉/双窗作用域不稳 → 按键统一上收到 C++
///   窗口级事件过滤器（`KeyRouter`，677 EscapeFilter 同款、已被真机验证）；
/// - 686 曾「Esc 完全禁用」（真凶：旧宿主窗 Esc 直接 requestExit+Qt.quit()，
///   全屏时关掉播放器）——现改三层阶梯：收面板 → 退全屏 → requestExit；
/// - 房间观众禁用 Space（canControl 门禁）；
/// - Flutter 窗聚焦时也要 Space/ESC（app 根部 WindowsGlobalHotkeys）。
void main() {
  final keyRouter = File('native/windows_qt_player/src/key_router.cpp')
      .readAsStringSync();
  final keyRouterH = File('native/windows_qt_player/src/key_router.h')
      .readAsStringSync();
  final mpvH =
      File('native/windows_qt_player/src/mpv_window.h').readAsStringSync();
  final mainCpp =
      File('native/windows_qt_player/src/main.cpp').readAsStringSync();
  final overlayQml = File('native/windows_qt_player/src/qml/Overlay.qml')
      .readAsStringSync();
  final mainQml = File('native/windows_qt_player/src/qml/Main.qml')
      .readAsStringSync();
  final shortcutsQml = File('native/windows_qt_player/src/qml/PlayerShortcuts.qml')
      .readAsStringSync();
  final appDart = File('lib/core/app.dart').readAsStringSync();
  final screenDart =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final bridgeDart = File('lib/services/player/player_hotkey_bridge.dart')
      .readAsStringSync();

  group('① C++ KeyRouter（Space/Esc 窗口级路由）', () {
    test('Space：canControl 门禁（房间观众禁用）+ togglePause + togglePlay 记账', () {
      expect(keyRouter, contains('Qt::Key_Space'));
      expect(keyRouter, contains('state_->canControl()'),
          reason: '677：房间观众不得键盘播放/暂停');
      expect(keyRouter, contains('mpv_->togglePause()'));
      expect(keyRouter, contains('"togglePlay"'),
          reason: '房间同步记账（与旧 QML Shortcut 同链路）');
    });

    test('Esc：只转发信号，语义在 QML 阶梯', () {
      expect(keyRouter, contains('Qt::Key_Escape'));
      expect(keyRouter, contains('mpv_->notifyEscapePressed()'));
      expect(keyRouter, isNot(contains('Qt.quit')),
          reason: '686 真凶：Qt.quit() 与 requestExit 竞态，全屏直接关播放器');
    });

    test('文本输入焦点放行 + 长按 auto-repeat 不重复触发', () {
      expect(keyRouter, contains('textInputFocused'));
      expect(keyRouter, contains('isAutoRepeat()'));
    });

    test('mpv_window.h 暴露 escapePressed 信号 + notifyEscapePressed', () {
      expect(mpvH, contains('void escapePressed()'));
      expect(mpvH, contains('notifyEscapePressed'));
    });

    test('main.cpp 在宿主窗与悬浮窗都装事件过滤器', () {
      expect(mainCpp, contains('host->installEventFilter(keyRouter)'));
      expect(mainCpp, contains('overlay->installEventFilter(keyRouter)'));
      expect(keyRouterH, contains('eventFilter'));
    });
  });

  group('② QML Esc 三层阶梯（Overlay 单点连接）', () {
    test('Overlay 含 onEscapePressed：收面板 → 退全屏 → requestExit', () {
      expect(overlayQml, contains('function onEscapePressed()'));
      final i = overlayQml.indexOf('function onEscapePressed()');
      final body = overlayQml.substring(i, overlayQml.indexOf('}', i) + 200);
      expect(body, contains('closePanels()'), reason: '第一层：收面板');
      expect(body, contains('hostFullscreen'), reason: '第二层：判全屏');
      expect(body, contains('toggleHostFullscreen()'), reason: '第二层：退全屏');
      expect(body, contains('"requestExit"'),
          reason: '第三层：单人=关 Qt 回详情页；房间=解散/离开确认');
    });

    test('onEscapePressed 只连接一处（mpvWindow 两窗共用，防双重触发）', () {
      expect('onEscapePressed'.allMatches(overlayQml).length, 1);
      expect(mainQml, isNot(contains('onEscapePressed')));
    });

    test('PlayerShortcuts 不再有 Space Shortcut（已迁 C++ KeyRouter）', () {
      expect(shortcutsQml, isNot(contains('sequence: "Space"')));
      expect(shortcutsQml, contains('sequence: "F11"'),
          reason: 'F/F11 保留 QML Shortcut');
    });
  });

  group('③ Flutter 全局键接线', () {
    test('app 根部挂 WindowsGlobalHotkeys', () {
      expect(appDart, contains('WindowsGlobalHotkeys('));
    });

    test('player_screen 注册/注销全局键桥', () {
      expect(screenDart,
          contains('PlayerHotkeyBridge.togglePlayPause = _handleHotkeyTogglePlayPause'));
      expect(screenDart,
          contains('PlayerHotkeyBridge.isWindowFullscreen'));
      expect(screenDart, contains('PlayerHotkeyBridge.exitWindowFullscreen'));
      expect(screenDart, contains('PlayerHotkeyBridge.togglePlayPause = null'),
          reason: 'dispose 注销');
    });

    test('桥含三个回调（暂停/播放 + 全屏检测/退出）', () {
      expect(bridgeDart, contains('static VoidCallback? togglePlayPause'));
      expect(bridgeDart, contains('static bool Function()? isWindowFullscreen'));
      expect(bridgeDart, contains('static VoidCallback? exitWindowFullscreen'));
    });
  });

  group('④ resolveWindowsHotkey 决策矩阵', () {
    test('文本输入焦点一律放行', () {
      for (final space in const [true, false]) {
        expect(
          resolveWindowsHotkey(
            isSpace: space,
            isEscape: !space,
            textInputFocused: true,
            canTogglePlay: true,
            isFullscreen: true,
            roomActive: true,
          ),
          WindowsHotkeyAction.ignored,
        );
      }
    });

    test('Space：有权=暂停/播放，无权/无会话=放行', () {
      expect(
        resolveWindowsHotkey(
            isSpace: true,
            isEscape: false,
            textInputFocused: false,
            canTogglePlay: true,
            isFullscreen: false,
            roomActive: false),
        WindowsHotkeyAction.togglePlay,
      );
      expect(
        resolveWindowsHotkey(
            isSpace: true,
            isEscape: false,
            textInputFocused: false,
            canTogglePlay: false,
            isFullscreen: false,
            roomActive: true),
        WindowsHotkeyAction.ignored,
        reason: '房间观众禁用 Space',
      );
    });

    test('ESC 阶梯：全屏 → 退全屏；房间 → 解散确认；其余 → 页面返回', () {
      WindowsHotkeyAction esc({bool fs = false, bool room = false}) =>
          resolveWindowsHotkey(
              isSpace: false,
              isEscape: true,
              textInputFocused: false,
              canTogglePlay: true,
              isFullscreen: fs,
              roomActive: room);
      expect(esc(fs: true, room: true), WindowsHotkeyAction.exitFullscreen,
          reason: '全屏优先（单人和房间全屏时 ESC 退出全屏）');
      expect(esc(room: true), WindowsHotkeyAction.roomExit);
      expect(esc(), WindowsHotkeyAction.pageBack);
    });

    test('其他按键不消费', () {
      expect(
        resolveWindowsHotkey(
            isSpace: false,
            isEscape: false,
            textInputFocused: false,
            canTogglePlay: true,
            isFullscreen: false,
            roomActive: false),
        WindowsHotkeyAction.ignored,
      );
    });
  });

  group('⑤ WindowsGlobalHotkeys widget 行为', () {
    late int toggles;
    late int fullscreenExits;

    setUp(() {
      toggles = 0;
      fullscreenExits = 0;
      PlayerHotkeyBridge.debugReset();
      RoomExitRequest.reset();
    });

    tearDown(() {
      PlayerHotkeyBridge.debugReset();
      RoomExitRequest.reset();
    });

    /// 平台覆写必须在 body 内 try/finally 复位——`_verifyInvariants` 在
    /// tearDown 之前检查 foundation 调试变量（flutter 官方测试同款范式）。
    Future<void> withWindows(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Widget buildHost({Widget? child}) => WindowsGlobalHotkeys(
          child: MaterialApp(
            navigatorKey: routerKey,
            home: child ?? const Scaffold(body: Text('home')),
          ),
        );

    testWidgets('Space → 暂停/播放', (tester) async {
      await withWindows(() async {
        PlayerHotkeyBridge.togglePlayPause = () => toggles++;
        await tester.pumpWidget(buildHost());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        expect(toggles, 1);
      });
    });

    testWidgets('Space 无会话/观众无权 → 放行（回调未注册）', (tester) async {
      await withWindows(() async {
        await tester.pumpWidget(buildHost());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        // 不抛异常即通过（ignored）。
        expect(toggles, 0);
      });
    });

    testWidgets('ESC 全屏 → 退全屏（阶梯第一段）', (tester) async {
      await withWindows(() async {
        PlayerHotkeyBridge.isWindowFullscreen = () => true;
        PlayerHotkeyBridge.exitWindowFullscreen = () => fullscreenExits++;
        PlayerHotkeyBridge.togglePlayPause = () => toggles++;
        await tester.pumpWidget(buildHost());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        expect(fullscreenExits, 1);
      });
    });

    testWidgets('ESC 房间播放 → 解散/离开确认（seq 递增）', (tester) async {
      await withWindows(() async {
        RoomExitRequest.attach();
        final before = RoomExitRequest.seq.value;
        await tester.pumpWidget(buildHost());
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        expect(RoomExitRequest.seq.value, before + 1);
      });
    });

    testWidgets('ESC 单人 → 所有 Flutter 页面返回', (tester) async {
      await withWindows(() async {
        await tester.pumpWidget(buildHost(
          child: Scaffold(
            body: Builder(builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const Scaffold(body: Text('page2')))),
                  child: const Text('go'),
                )),
          ),
        ));
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(find.text('page2'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('page2'), findsNothing, reason: 'ESC 弹栈返回上页');
      });
    });

    testWidgets('文本输入焦点时 ESC/Space 放行（打字不受影响）', (tester) async {
      await withWindows(() async {
        PlayerHotkeyBridge.togglePlayPause = () => toggles++;
        await tester.pumpWidget(buildHost(
          child: const Scaffold(body: TextField()),
        ));
        await tester.showKeyboard(find.byType(TextField));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        expect(toggles, 0, reason: '输入框聚焦时 Space 不触发暂停/播放');
        // home 仍在（ESC 没有 pop）
        expect(find.byType(TextField), findsOneWidget);
      });
    });
  });
}
