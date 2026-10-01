import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_hotkey.dart';

void main() {
  int toggled = 0;
  int escaped = 0;
  int showControls = 0;

  int seekMs = 0;
  double volumeDelta = 0;

  Widget wrap({
    VoidCallback? onEscape,
    bool tvMode = false,
    bool controlsVisible = true,
    VoidCallback? onShowControls,
    FocusNode? focusNode,
  }) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: PlayerHotkey(
          onTogglePlayPause: () => toggled++,
          onEscape: onEscape,
          tvMode: tvMode,
          controlsVisible: controlsVisible,
          onSeekRelative: (ms) => seekMs += ms,
          onVolumeDelta: (v) => volumeDelta += v,
          onShowControls: onShowControls,
          focusNode: focusNode,
          child: const SizedBox(width: 100, height: 100),
        ),
      );

  setUp(() {
    toggled = 0;
    escaped = 0;
    showControls = 0;
    seekMs = 0;
    volumeDelta = 0;
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

  testWidgets('TV：中键 Enter 暂停/播放', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.enter);
      await simulateKeyUpEvent(LogicalKeyboardKey.enter);
      expect(toggled, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：媒体键 mediaPlayPause 暂停/播放', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.mediaPlayPause);
      await simulateKeyUpEvent(LogicalKeyboardKey.mediaPlayPause);
      expect(toggled, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：非 TV 模式 Enter 不触发', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: false));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.enter);
      await simulateKeyUpEvent(LogicalKeyboardKey.enter);
      expect(toggled, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：控制条隐藏时左右键 seek ±10 秒', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true, controlsVisible: false));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 10000);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      expect(seekMs, 0, reason: '+10s 后 -10s 回到 0');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：控制条可见时方向键不拦截（让位焦点导航）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true, controlsVisible: true));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 0);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowUp);
      expect(volumeDelta, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：控制条隐藏时上下键 ±5% 音量', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true, controlsVisible: false));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowUp);
      expect(volumeDelta, 5);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(volumeDelta, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：中键与媒体键暂停播放同时唤出控制条', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        wrap(tvMode: true, onShowControls: () => showControls++),
      );
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.enter);
      await simulateKeyUpEvent(LogicalKeyboardKey.enter);
      expect(toggled, 1);
      expect(showControls, 1);

      await simulateKeyDownEvent(LogicalKeyboardKey.mediaPlayPause);
      await simulateKeyUpEvent(LogicalKeyboardKey.mediaPlayPause);
      expect(toggled, 2);
      expect(showControls, 2);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('非 TV 模式中键不唤出控制条', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        wrap(tvMode: false, onShowControls: () => showControls++),
      );
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.enter);
      await simulateKeyUpEvent(LogicalKeyboardKey.enter);
      expect(toggled, 0);
      expect(showControls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('外部 focusNode 由调用方管理（卸载不重复释放）', (tester) async {
    final node = FocusNode(debugLabel: 'externalHotkey');
    await tester.pumpWidget(wrap(tvMode: true, focusNode: node));
    await tester.pump();

    // 卸载：组件不得 dispose 外部传入节点
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 调用方手动释放：若组件已释放会抛 double-dispose
    node.dispose();
    expect(tester.takeException(), isNull);
  });
}
