import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_hotkey.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

void main() {
  // ---- PlayerScreen.scheduleInitialControlsSetup ----

  testWidgets('TV+控件可见：启动隐藏计时并在 postFrame 落焦 seek 滑杆', (tester) async {
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    addTearDown(seek.dispose);
    var timerStarted = 0;

    await tester.pumpWidget(MaterialApp(
      home:
          Focus(focusNode: seek, child: const SizedBox(width: 10, height: 10)),
    ));
    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: true,
      controlsVisible: true,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump(); // 执行 postFrame 回调（requestFocus）
    await tester.pumpAndSettle();

    expect(timerStarted, 1, reason: '初进应启动自动隐藏计时');
    expect(seek.hasPrimaryFocus, isTrue, reason: '焦点应落 seek 滑杆');
  });

  testWidgets('非 TV：启动隐藏计时但不落焦', (tester) async {
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    final other = FocusNode(debugLabel: 'hotkey');
    addTearDown(seek.dispose);
    addTearDown(other.dispose);
    var timerStarted = 0;

    await tester.pumpWidget(MaterialApp(
      home: Focus(
        focusNode: other,
        autofocus: true,
        child: Focus(
            focusNode: seek, child: const SizedBox(width: 10, height: 10)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(other.hasPrimaryFocus, isTrue);

    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: false,
      controlsVisible: true,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(timerStarted, 1, reason: '非 TV 同样要启动 5 秒自动隐藏');
    expect(other.hasPrimaryFocus, isTrue, reason: '非 TV 保持热键层焦点（桌面键盘行为不变）');
    expect(seek.hasPrimaryFocus, isFalse);
  });

  testWidgets('TV+控件已隐藏：启动计时不落焦', (tester) async {
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    final other = FocusNode(debugLabel: 'hotkey');
    addTearDown(seek.dispose);
    addTearDown(other.dispose);
    var timerStarted = 0;

    await tester.pumpWidget(MaterialApp(
      home: Focus(
        focusNode: other,
        autofocus: true,
        child: Focus(
            focusNode: seek, child: const SizedBox(width: 10, height: 10)),
      ),
    ));
    await tester.pumpAndSettle();

    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: true,
      controlsVisible: false,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(timerStarted, 1);
    expect(seek.hasPrimaryFocus, isFalse, reason: '控件隐藏时无处落焦，焦点保持原处');
  });

  // ---- 落焦 seek 后热键冒泡语义仍有效 ----

  testWidgets('TV：落焦 seek 后音量键仍被热键层拦截、上键顺延隐藏计时', (tester) async {
    final hotkey = FocusNode(debugLabel: 'PlayerHotkey');
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    addTearDown(hotkey.dispose);
    addTearDown(seek.dispose);
    var timerStarted = 0;
    var volumeDelta = 0.0;
    var showControls = 0;

    await tester.pumpWidget(MaterialApp(
      home: PlayerHotkey(
        focusNode: hotkey,
        tvMode: true,
        controlsVisible: true,
        onTogglePlayPause: () {},
        onSeekRelative: (_) {},
        onVolumeDelta: (v) => volumeDelta += v,
        onShowControls: () => showControls++,
        child: Focus(
            focusNode: seek, child: const SizedBox(width: 10, height: 10)),
      ),
    ));
    await tester.pumpAndSettle();

    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: true,
      controlsVisible: true,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(seek.hasPrimaryFocus, isTrue,
        reason: '焦点在 seek（postFrame 覆盖 PlayerHotkey autofocus）');

    // 音量键从 seek 冒泡经过热键层 → 被拦截并回调
    await simulateKeyDownEvent(LogicalKeyboardKey.audioVolumeUp);
    await simulateKeyUpEvent(LogicalKeyboardKey.audioVolumeUp);
    expect(volumeDelta, 5.0, reason: '热键层拦截音量键（±5% 步进）');

    // 控件可见：上键仅顺延隐藏计时（onShowControls），不打断焦点
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(showControls, 1);
    expect(seek.hasPrimaryFocus, isTrue);
    expect(timerStarted, 1);
  });

  // ---- 守卫重试：控制条在 _isPlayerReady 后才构建 ----

  testWidgets('TV：seek 未挂树（控件未就绪）时逐帧重试，控件出现后落焦', (tester) async {
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    final other = FocusNode(debugLabel: 'hotkey');
    addTearDown(seek.dispose);
    addTearDown(other.dispose);
    var timerStarted = 0;

    // 首帧：控制条未构建（seek 未挂树）
    await tester.pumpWidget(MaterialApp(
      home: Focus(focusNode: other, autofocus: true, child: const SizedBox()),
    ));
    await tester.pumpAndSettle();
    expect(other.hasPrimaryFocus, isTrue);

    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: true,
      controlsVisible: true,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
      shouldRetry: () => true,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump(); // attempt1：未附着 → 注册下一帧重试
    expect(seek.hasPrimaryFocus, isFalse, reason: '控件未就绪不能落焦');

    // 控件就绪：seek 挂树
    await tester.pumpWidget(MaterialApp(
      home: Focus(
        focusNode: other,
        autofocus: true,
        child: Focus(focusNode: seek, child: const SizedBox()),
      ),
    ));
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump(); // attempt2：附着 → requestFocus
    await tester.pumpAndSettle();

    expect(seek.hasPrimaryFocus, isTrue, reason: '重试后控件就绪落焦');
    expect(timerStarted, 1, reason: '隐藏计时只启动一次');
  });

  testWidgets('shouldRetry 返回 false 时放弃重试（控件隐藏/页面销毁）', (tester) async {
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    addTearDown(seek.dispose);
    var timerStarted = 0;

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: true,
      controlsVisible: true,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
      shouldRetry: () => false,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump(); // attempt1：未附着 → shouldRetry false → 放弃

    // 后续控件就绪也不再落焦
    await tester.pumpWidget(MaterialApp(
      home: Focus(focusNode: seek, child: const SizedBox()),
    ));
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(seek.hasPrimaryFocus, isFalse, reason: '已放弃重试');
    expect(timerStarted, 1);
  });

  testWidgets('达到 maxAttempts 上限后停止重试', (tester) async {
    final seek = FocusNode(debugLabel: 'PlayerSeekSlider');
    addTearDown(seek.dispose);
    var timerStarted = 0;

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: true,
      controlsVisible: true,
      seekNode: seek,
      onStartHideTimer: () => timerStarted++,
      shouldRetry: () => true,
      maxAttempts: 1,
    );
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump(); // attempt1：未附着 → attempts=1 达上限 → 停止

    await tester.pumpWidget(MaterialApp(
      home: Focus(focusNode: seek, child: const SizedBox()),
    ));
    WidgetsBinding.instance.scheduleFrame();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(seek.hasPrimaryFocus, isFalse, reason: '上限后不再重试');
    expect(timerStarted, 1);
  });

  // ---- 「显示调节」入口位置：TV 底栏 / 非 TV 顶栏 ----

  test('TV：显示调节入口在底部控制条（顶栏隐藏）', () {
    expect(PlayerScreen.showTopSubtitleStyleButton(tvMode: true), isFalse);
    expect(
        PlayerScreen.showBottomDisplayAdjustButton(tvMode: true), isTrue);
  });

  test('非 TV：显示调节入口在顶栏（底栏不显示）', () {
    expect(PlayerScreen.showTopSubtitleStyleButton(tvMode: false), isTrue);
    expect(
        PlayerScreen.showBottomDisplayAdjustButton(tvMode: false), isFalse);
  });
}
