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
    expect(PlayerScreen.showBottomDisplayAdjustButton(tvMode: true), isTrue);
  });

  test('非 TV：显示调节入口在顶栏（底栏不显示）', () {
    expect(PlayerScreen.showTopSubtitleStyleButton(tvMode: false), isTrue);
    expect(PlayerScreen.showBottomDisplayAdjustButton(tvMode: false), isFalse);
  });

  // ---- 加载转圈期间强制显示控件（黑屏仍可返回） ----

  group('isLoadingMaskVisible（v1.1.238 黑屏加载仍显控件）', () {
    test('切集遮罩恒可见（无论进度/就绪）', () {
      expect(
        PlayerScreen.isLoadingMaskVisible(
            switchingMedia: true,
            durationMs: 5000,
            playerReady: true,
            startedOnce: true),
        isTrue,
      );
      expect(
        PlayerScreen.isLoadingMaskVisible(
            switchingMedia: true,
            durationMs: 0,
            playerReady: false,
            startedOnce: false),
        isTrue,
      );
    });

    test('首帧未出（就绪且时长 0）可见', () {
      expect(
        PlayerScreen.isLoadingMaskVisible(
            switchingMedia: false,
            durationMs: 0,
            playerReady: true,
            startedOnce: false),
        isTrue,
      );
    });

    test('正常播放（时长 > 0）不可见', () {
      expect(
        PlayerScreen.isLoadingMaskVisible(
            switchingMedia: false,
            durationMs: 1000,
            playerReady: true,
            startedOnce: true),
        isFalse,
      );
    });

    test('未就绪（选集页占位）不可见——占位无转圈遮罩', () {
      expect(
        PlayerScreen.isLoadingMaskVisible(
            switchingMedia: false,
            durationMs: 0,
            playerReady: false,
            startedOnce: false),
        isFalse,
      );
    });

    // v1.2.24：首播后重载（loaded 但 duration 暂报 0）不再把控件强留屏上
    //（避免叠着刚重建的视频层显示残缺，用户感知「控件自己冒出来」）。
    test('已起播后 duration 归零 → 不可见（重载窗口不再强显控件）', () {
      expect(
        PlayerScreen.isLoadingMaskVisible(
            switchingMedia: false,
            durationMs: 0,
            playerReady: true,
            startedOnce: true),
        isFalse,
      );
    });
  });

  // ---- 播完自动下一集（v1.1.239 位置兜底门控） ----

  group('shouldAutoNextEpisode（播完位置兜底判定）', () {
    test('播放中且进入结尾窗口（距时长 ≤500ms）→ 触发（无 end 引擎）', () {
      expect(
        PlayerScreen.shouldAutoNextEpisode(
            positionMs: 59500, durationMs: 60000, playing: true),
        isTrue,
      );
      expect(
        PlayerScreen.shouldAutoNextEpisode(
            positionMs: 60000, durationMs: 60000, playing: true),
        isTrue,
      );
    });

    test('距结尾 >500ms → 不触发', () {
      expect(
        PlayerScreen.shouldAutoNextEpisode(
            positionMs: 59000, durationMs: 60000, playing: true),
        isFalse,
      );
    });

    test('暂停中（非 playing）→ 不触发（用户主动暂停不切集）', () {
      expect(
        PlayerScreen.shouldAutoNextEpisode(
            positionMs: 60000, durationMs: 60000, playing: false),
        isFalse,
      );
    });

    test('时长未知（0）→ 不触发', () {
      expect(
        PlayerScreen.shouldAutoNextEpisode(
            positionMs: 0, durationMs: 0, playing: true),
        isFalse,
      );
    });

    test('引擎自报 end（mdk）→ 兜底恒不触发（v1.1.239 拖进度条误切集回归）', () {
      expect(
        PlayerScreen.shouldAutoNextEpisode(
          positionMs: 60000,
          durationMs: 60000,
          playing: true,
          engineEmitsEnd: true,
        ),
        isFalse,
        reason: 'mdk 拖到结尾窗口不判播完，等真实 MediaStatus.end',
      );
    });

    test('seek 冷却期内 → 不触发；冷却外恢复触发', () {
      expect(
        PlayerScreen.shouldAutoNextEpisode(
          positionMs: 60000,
          durationMs: 60000,
          playing: true,
          seekCooldownActive: true,
        ),
        isFalse,
      );
      expect(
        PlayerScreen.shouldAutoNextEpisode(
          positionMs: 60000,
          durationMs: 60000,
          playing: true,
          seekCooldownActive: false,
        ),
        isTrue,
      );
    });
  });

  // ---- mdk end 事件可信度门（v1.1.240 拖进度条误切集修复） ----

  group('shouldHandleEngineEnd（引擎 end 事件可信度判定）', () {
    test('真实播完（位置≈时长）→ 可信', () {
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: false, positionMs: 60000, durationMs: 60000),
        isTrue,
      );
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: false, positionMs: 59500, durationMs: 60000),
        isTrue,
        reason: '距结尾 ≤1s 仍视为真实播完（引擎时钟抖动容差）',
      );
    });

    test('seek/拖动进行中 → 忽略（mdk keyframe seek 误报 end）', () {
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: true, positionMs: 60000, durationMs: 60000),
        isFalse,
      );
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: true, positionMs: 30000, durationMs: 60000),
        isFalse,
      );
    });

    test('位置远离结尾（拖到中段的误报 end）→ 忽略', () {
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: false, positionMs: 30000, durationMs: 60000),
        isFalse,
      );
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: false, positionMs: 0, durationMs: 60000),
        isFalse,
      );
    });

    test('时长未就绪（0）无法校验 → 视作误报忽略', () {
      expect(
        PlayerScreen.shouldHandleEngineEnd(
            seekInProgress: false, positionMs: 0, durationMs: 0),
        isFalse,
      );
    });
  });

  // ---- 跳过片尾：有下一集切集，最后一集/电影到终点退出 ----

  group('shouldAdvanceAfterOutroSkip（片尾跳过决策）', () {
    test('剧集有下一集 → 直接切下一集', () {
      expect(
        PlayerScreen.shouldAdvanceAfterOutroSkip(
          hasEpisodeList: true,
          currentEpisodeIndex: 1,
          episodeCount: 3,
        ),
        isTrue,
      );
    });

    test('剧集最后一集 → 不切集，到片尾终点退出', () {
      expect(
        PlayerScreen.shouldAdvanceAfterOutroSkip(
          hasEpisodeList: true,
          currentEpisodeIndex: 2,
          episodeCount: 3,
        ),
        isFalse,
      );
    });

    test('电影/无剧集列表 → 不切集', () {
      expect(
        PlayerScreen.shouldAdvanceAfterOutroSkip(
          hasEpisodeList: false,
          currentEpisodeIndex: 0,
          episodeCount: 1,
        ),
        isFalse,
      );
      expect(
        PlayerScreen.shouldAdvanceAfterOutroSkip(
          hasEpisodeList: true,
          currentEpisodeIndex: 0,
          episodeCount: 1,
        ),
        isFalse,
      );
    });

    test('索引无效 → 不切集', () {
      expect(
        PlayerScreen.shouldAdvanceAfterOutroSkip(
          hasEpisodeList: true,
          currentEpisodeIndex: -1,
          episodeCount: 3,
        ),
        isFalse,
      );
    });
  });

  group('片头 3 秒门槛', () {
    test('前 3 秒不可设置片头', () {
      expect(PlayerScreen.canSetIntroAt(0), isFalse);
      expect(PlayerScreen.canSetIntroAt(2999), isFalse);
      expect(PlayerScreen.canSetIntroAt(3000), isTrue);
    });

    test('片头提示需本次起播满 3 秒', () {
      expect(
        PlayerScreen.shouldDelayIntroPrompt(
          playbackElapsedMs: 2999,
          insideIntro: true,
        ),
        isTrue,
      );
      expect(
        PlayerScreen.shouldDelayIntroPrompt(
          playbackElapsedMs: 3000,
          insideIntro: true,
        ),
        isFalse,
      );
      expect(
        PlayerScreen.shouldDelayIntroPrompt(
          playbackElapsedMs: 0,
          insideIntro: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowSeriesFinishedAfterOutroSkip（片尾退出提示判定）', () {
    test('剧集最后一集 → 提示所有剧集播放完毕', () {
      expect(
        PlayerScreen.shouldShowSeriesFinishedAfterOutroSkip(
          isSeries: true,
          hasNextEpisode: false,
        ),
        isTrue,
      );
    });

    test('电影 → 不提示所有剧集播放完毕', () {
      expect(
        PlayerScreen.shouldShowSeriesFinishedAfterOutroSkip(
          isSeries: false,
          hasNextEpisode: false,
        ),
        isFalse,
      );
    });

    test('有下一集 → 不提示完播，直接切集', () {
      expect(
        PlayerScreen.shouldShowSeriesFinishedAfterOutroSkip(
          isSeries: true,
          hasNextEpisode: true,
        ),
        isFalse,
      );
    });
  });
}
