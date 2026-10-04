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
    bool provideVolume = true,
    FocusNode? seekFocusNode,
    FocusNode? playPauseFocusNode,
  }) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: PlayerHotkey(
          onTogglePlayPause: () => toggled++,
          onEscape: onEscape,
          tvMode: tvMode,
          controlsVisible: controlsVisible,
          onSeekRelative: (ms) => seekMs += ms,
          onVolumeDelta: provideVolume ? (v) => volumeDelta += v : null,
          onShowControls: onShowControls,
          focusNode: focusNode,
          seekFocusNode: seekFocusNode,
          playPauseFocusNode: playPauseFocusNode,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (seekFocusNode != null)
                Focus(
                    focusNode: seekFocusNode,
                    child: const SizedBox(width: 100, height: 100)),
              if (playPauseFocusNode != null)
                Focus(
                    focusNode: playPauseFocusNode,
                    child: const SizedBox(width: 100, height: 100)),
              if (seekFocusNode == null && playPauseFocusNode == null)
                const SizedBox(width: 100, height: 100),
            ],
          ),
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

  testWidgets('TV：控制条可见时方向键不拦截（让位焦点导航）并顺延自动隐藏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(
        tvMode: true,
        controlsVisible: true,
        onShowControls: () => showControls++,
      ));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 0, reason: '可见时左右键不 seek（焦点导航用）');
      expect(showControls, 1, reason: '可见时方向键顺延自动隐藏计时');

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowUp);
      expect(volumeDelta, 0, reason: '上下键不再调音量');
      expect(showControls, 2, reason: '上下键同样顺延自动隐藏计时');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：控制条隐藏时上下键唤出控制条（不再调音量）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(
        tvMode: true,
        controlsVisible: false,
        onShowControls: () => showControls++,
      ));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowUp);
      expect(showControls, 1, reason: '上键唤出控制条');
      expect(volumeDelta, 0, reason: '上下键音量语义已迁移到音量键');

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);
      expect(showControls, 2, reason: '下键同样唤出控制条');
      expect(volumeDelta, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：滑杆焦点按落键定向落到播放/暂停按钮', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seek = FocusNode(debugLabel: 'seek');
    final play = FocusNode(debugLabel: 'play');
    addTearDown(seek.dispose);
    addTearDown(play.dispose);
    try {
      await tester.pumpWidget(wrap(
        tvMode: true,
        controlsVisible: true,
        seekFocusNode: seek,
        playPauseFocusNode: play,
        onShowControls: () => showControls++,
      ));
      seek.requestFocus();
      await tester.pump();
      expect(seek.hasPrimaryFocus, isTrue, reason: '初始焦点在滑杆');

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(play.hasPrimaryFocus, isTrue,
          reason: '滑杆 Down 定向落到播放按钮（几何导航会落右侧组）');
      expect(showControls, 1, reason: '落焦点属于控件交互，顺延自动隐藏');
      expect(seekMs, 0, reason: 'Down 不触发 seek');
      expect(toggled, 0, reason: 'Down 不触发播放/暂停');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：焦点不在滑杆时 Down 不拦截（焦点导航照常）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seek = FocusNode(debugLabel: 'seek');
    final play = FocusNode(debugLabel: 'play');
    addTearDown(seek.dispose);
    addTearDown(play.dispose);
    try {
      await tester.pumpWidget(wrap(
        tvMode: true,
        controlsVisible: true,
        seekFocusNode: seek,
        playPauseFocusNode: play,
        onShowControls: () => showControls++,
      ));
      play.requestFocus();
      await tester.pump();
      expect(play.hasPrimaryFocus, isTrue);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(play.hasPrimaryFocus, isTrue,
          reason: '焦点已在播放按钮（非滑杆），Down 放行给焦点导航');
      expect(showControls, 1, reason: '可见时方向键仍顺延自动隐藏');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：音量键 audioVolumeUp/Down 调应用内音量（控制条可见也生效）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true, controlsVisible: true));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 5);

      await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeDown);
      expect(volumeDelta, 0, reason: '+5 后 -5 回到 0');
      expect(toggled, 0, reason: '音量键不应触发播放/暂停');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：控制条隐藏时音量键同样生效（不受显隐门控）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true, controlsVisible: false));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeDown);
      expect(volumeDelta, -5);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：PC 多媒体键 audioVolumeUp/Down 同样生效', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(wrap(tvMode: true));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 5);

      await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeDown);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeDown);
      expect(volumeDelta, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：音量键长按 KeyRepeatEvent 连续调节', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true));
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 5);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 10, reason: '长按 repeat 应连续加音量');
      await simulateKeyRepeatEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 15);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 15, reason: '松键停止');

      // 对照：其他热键长按仍不重复（空格在 Android 不生效，用中键验证）
      await simulateKeyDownEvent(LogicalKeyboardKey.enter);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.enter);
      await simulateKeyUpEvent(LogicalKeyboardKey.enter);
      expect(toggled, 1, reason: '中键长按只触发一次');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：无 onVolumeDelta 时音量键放行（返回未处理给系统）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: true, provideVolume: false));
      await tester.pump();

      final handled =
          await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(handled, isFalse, reason: '未提供回调应放行系统音量');
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(volumeDelta, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('非 TV 模式音量键不拦截（保持系统音量）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(wrap(tvMode: false));
      await tester.pump();

      final handled =
          await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
      expect(handled, isFalse);
      expect(volumeDelta, 0);
      await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
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

  testWidgets('TV：焦点在进度条时单击左右键 = 快进退 5 秒', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seekNode = FocusNode(debugLabel: 'seek');
    try {
      await tester.pumpWidget(
          wrap(tvMode: true, controlsVisible: true, seekFocusNode: seekNode));
      await tester.pump();
      seekNode.requestFocus();
      await tester.pump();
      expect(seekNode.hasPrimaryFocus, isTrue);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 5000);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      expect(seekMs, 0, reason: '+5s 后 -5s 回到 0');
    } finally {
      seekNode.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：焦点在进度条时长按左右键 = 每步 10 秒连续拖动', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seekNode = FocusNode(debugLabel: 'seek');
    try {
      await tester.pumpWidget(
          wrap(tvMode: true, controlsVisible: true, seekFocusNode: seekNode));
      await tester.pump();
      seekNode.requestFocus();
      await tester.pump();
      expect(seekNode.hasPrimaryFocus, isTrue);

      // 单击 +5s，随后两步长按各 +10s
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 25000);

      // 长按左键回退
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      expect(seekMs, 10000, reason: '25s -5s -10s = 10s');
    } finally {
      seekNode.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：焦点在进度条时 KeyUp 不触发 seek，且左右键顺延自动隐藏', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seekNode = FocusNode(debugLabel: 'seek');
    try {
      await tester.pumpWidget(wrap(
          tvMode: true,
          controlsVisible: true,
          seekFocusNode: seekNode,
          onShowControls: () => showControls++));
      await tester.pump();
      seekNode.requestFocus();
      await tester.pump();
      expect(seekNode.hasPrimaryFocus, isTrue);

      // 单击：seek + 顺延隐藏计时
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      expect(seekMs, -5000);
      expect(showControls, 1, reason: '操作进度条顺延自动隐藏');
      // KeyUp 放行，不重复 seek
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      expect(seekMs, -5000);
      expect(showControls, 1, reason: 'KeyUp 不触发任何回调');
    } finally {
      seekNode.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TV：焦点不在进度条时左右键语义不变（让位焦点导航）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final seekNode = FocusNode(debugLabel: 'seek');
    try {
      await tester.pumpWidget(wrap(
          tvMode: true,
          controlsVisible: true,
          seekFocusNode: seekNode,
          onShowControls: () => showControls++));
      await tester.pump();
      // 焦点留在热键层（autofocus），seekNode 未获焦
      expect(seekNode.hasPrimaryFocus, isFalse);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 0, reason: '焦点不在进度条不接管 seek');
      expect(showControls, 1, reason: '可见时左右键仍顺延自动隐藏');
    } finally {
      seekNode.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('非 TV：焦点在进度条时左右键不接管（不走 TV seek 语义）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final seekNode = FocusNode(debugLabel: 'seek');
    try {
      await tester.pumpWidget(wrap(tvMode: false, seekFocusNode: seekNode));
      await tester.pump();
      seekNode.requestFocus();
      await tester.pump();
      expect(seekNode.hasPrimaryFocus, isTrue);

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      expect(seekMs, 0, reason: '非 TV 模式不接管左右键');
    } finally {
      seekNode.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
