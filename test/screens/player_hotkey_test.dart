import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_hotkey.dart';

void main() {
  int toggled = 0;
  int escaped = 0;

  Widget wrap({VoidCallback? onEscape}) => Directionality(
        textDirection: TextDirection.ltr,
        child: PlayerHotkey(
          onTogglePlayPause: () => toggled++,
          onEscape: onEscape,
          child: const SizedBox(width: 100, height: 100),
        ),
      );

  setUp(() {
    toggled = 0;
    escaped = 0;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('Windows 空格触发播放/暂停', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      expect(toggled, 1);

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      expect(toggled, 2);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android 空格不触发（仅 Windows 生效）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      expect(toggled, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('长按重复事件（KeyRepeatEvent）不重复触发', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      expect(toggled, 1);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.space);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.space);
      expect(toggled, 1, reason: '长按空格只应触发一次');
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      expect(toggled, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('非热键按键被忽略', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.keyA);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(toggled, 0);
      expect(escaped, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ESC 触发 onEscape', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(wrap(onEscape: () => escaped++));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.escape);
      await simulateKeyUpEvent(LogicalKeyboardKey.escape);
      expect(escaped, 1);
      expect(toggled, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('onEscape 为 null 时 ESC 不触发任何回调', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.escape);
      await simulateKeyUpEvent(LogicalKeyboardKey.escape);
      expect(escaped, 0);
      expect(toggled, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
