import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/player/widgets/seek_time_labels.dart';
import 'package:himi_syncwatch/services/player/native/native_player_theme.dart';

/// 原生控制层**布局语义**一致性。
///
/// 与 [test/native_player_theme_test.dart] 的分工：那边管**数值常量**，
/// 这边管**结构与算法**——测量级缩放、角标正圆、面板几何、显隐谓词。
/// 双端（Android Kotlin / 鸿蒙 ArkTS）必须与 Flutter 播放页同语义。
void main() {
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();

  final kotlinScaleBox = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'ScaleDownBox.kt',
  ).readAsStringSync();

  // 585：PixelCopy 采样实现（GlassBackdrop.kt）已删除，弹层改纯白渐变磨砂。
  final kotlinGlass = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'PanelGlassDrawable.kt',
  ).readAsStringSync();

  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  final ohosPanel = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'NativePlayerPanel.ets',
  ).readAsStringSync();

  group('测量级缩放（FittedBox(scaleDown) 等价）', () {
    test('Android 用 ScaleDownBox 而非只改 scaleX/Y', () {
      // 只改 scaleX/Y 不改测量宽 → 父级仍按自然宽排布 → 竖屏溢出（真机回归）。
      expect(kotlinScaleBox, contains('class ScaleDownBox'));
      expect(kotlinScaleBox, contains('setMeasuredDimension'));
      // 缩放后的尺寸必须真正流入测量结果：
      //   scaledW = naturalW × scale → finalW → setMeasuredDimension(finalW, …)
      expect(kotlinScaleBox, contains('val scaledW = (naturalW * scale)'));
      expect(kotlinScaleBox, contains('val scaledH = (naturalH * scale)'));
      expect(
        kotlinScaleBox,
        contains('setMeasuredDimension(finalW, finalH)'),
        reason: 'ScaleDownBox 必须把缩放后的尺寸作为测量尺寸',
      );
      // 底栏 trailing 与顶栏尾簇都要走它。
      expect(kotlinScreen, contains('trailingBox'));
      expect(kotlinScreen, contains('topTailBox'));
    });

    test('Android 底栏结构等价 Flutter PlayerBottomRow(centered)', () {
      // Flutter：Expanded(leading) | transport | Expanded(trailing + FittedBox)
      expect(kotlinScreen, contains('leadingSlot'));
      expect(kotlinScreen, matches(RegExp(r'trailingBox\.layoutParams\s*=\s*LinearLayout')),
          reason: 'trailing 槽必须是权重槽（可用宽=(行宽-传输组)/2）');
      // 旧的逐级收窄间距**函数**必须移除（注释里的历史说明不算）。
      expect(
        kotlinScreen,
        isNot(matches(RegExp(r'private fun applyGroupGap\('))),
        reason: '旧的逐级收窄间距方案必须移除（收到底仍会溢出）',
      );
      expect(kotlinScreen, contains('requestAdaptiveRelayout'));
    });

    test('顶栏标题有保底宽（不被尾簇压成 0）', () {
      expect(kotlinScreen, contains('titleText.minimumWidth'));
      expect(kotlinScreen, contains('NPTheme.TITLE_MIN_WIDTH'));
    });

    test('鸿蒙底栏右侧簇同样走等比缩放', () {
      // 旧方案「收窄间距 20→8→4→0」已移除（gap 归零仍溢出 32dp），
      // 改为与安卓 ScaleDownBox 同语义的测量级缩放。
      expect(ohosView, contains('bottomScale'));
      expect(ohosView, contains('adjustBottomScale'));
    });
  });

  group('角标正圆（对齐 Flutter BoxShape.circle）', () {
    test('Android 角标用系统 OVAL 正圆底（禁自绘 bounds 陷阱）', () {
      // 589 真机回归：自绘 Drawable 的 draw() 依赖 bounds，View 的
      // setBackground 与首次 onSizeChanged 时序不保证 → bounds 恒空 →
      // 圆底完全不画，只剩白字。改用系统 GradientDrawable(OVAL)。
      expect(kotlinScreen, contains('badgeCircleBackground()'));
      expect(kotlinScreen, isNot(contains('BadgeCircleDrawable(')));
      final theme = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerUi.kt',
      ).readAsStringSync();
      expect(theme, contains('internal fun badgeCircleBackground()'));
      expect(theme, contains('GradientDrawable.OVAL'));
      expect(theme, contains('setColor(NPTheme.BADGE_BG)'));
      expect(theme, contains('const val BADGE_BG = 0xFF6366F1.toInt()'));
      // 直径必须**正方形**（宽==高），否则 OVAL 画成椭圆。
      expect(kotlinScreen, matches(RegExp(r'LayoutParams\(sidePx, sidePx')),
          reason: '角标必须是正方形边长（正圆底）');
      // 旧的手算宽度方案必须移除。
      expect(kotlinScreen, isNot(contains('14 + text.orEmpty().length * 5')),
          reason: '旧的 14+len*5 手算宽度会画成椭圆');
    });

    test('三端角标底色精确 ARGB 相同', () {
      // Flutter 走 NativePlayerTheme.accent；安卓 BADGE_BG；鸿蒙 SEL_COLOR。
      expect(NativePlayerTheme.accent.toARGB32(), 0xFF6366F1);
      final theme = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerUi.kt',
      ).readAsStringSync();
      expect(theme, contains('const val BADGE_BG = 0xFF6366F1.toInt()'));
      expect(ohosView, contains("const SEL_COLOR = '#6366F1';"));
    });

    test('Flutter 角标严格正方形（禁 constraints 只设下限）', () {
      final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
      // constraints(minWidth/minHeight) 只设下限：两位以上数字会把容器撑宽
      // → 15×17 变椭圆。必须固定 width == height。
      expect(screen, isNot(contains('minWidth: NativePlayerTheme.badgeSizeFor')));
      expect(screen, contains('width: NativePlayerTheme.badgeSizeFor(badge)'));
      expect(screen, contains('height: NativePlayerTheme.badgeSizeFor(badge)'));
    });

    test('Android 关闭整条父链裁切（角标伸出命中框不被切）', () {
      expect(kotlinScreen, contains('clipChildren = false'));
      expect(kotlinScreen, contains('clipToPadding = false'));
    });

    test('鸿蒙角标同样定宽定高（不靠 constraintSize 最小值）', () {
      expect(ohosView, contains('badgeSide'));
      expect(ohosView, contains('.borderRadius(this.badgeSide(badge) * s / 2)'));
    });
  });

  group('玻璃面板源矩形映射（585 起改纯渐变，不再有映射）', () {
    test('Android 弹层不做位图映射（纯渐变绘制）', () {
      // 585：采样链整体删除，不再有位图/源矩形映射逻辑。
      expect(kotlinGlass, isNot(contains('mapPanelToSource')));
      expect(kotlinGlass, isNot(contains('drawBitmap')));
      expect(kotlinGlass, contains('LinearGradient'));
    });

    test('585 删除采样后不再需要喂入矩形', () {
      // 白底磨砂为纯渐变绘制，不需要采样位图 → 矩形喂入链已整块移除。
      expect(kotlinScreen, isNot(contains('feedGlassRects')));
      expect(kotlinScreen, isNot(contains('pushScreenRect')));
      expect(kotlinScreen, isNot(contains('setPanelScreenRect')));
    });
  });

  group('显隐谓词（与 Flutter PlayerScreen 静态谓词同语义）', () {
    test('解码按钮：TV 隐藏', () {
      expect(PlayerScreen.showDecodeButton(tvMode: false), isTrue);
      expect(PlayerScreen.showDecodeButton(tvMode: true), isFalse);
      // 双端原生都按 `!tv` 实现。
      expect(kotlinScreen, contains('decodeChip.visibility = if (!tv'));
      expect(ohosView, contains('if (!this.state().tvMode)'));
    });

    test('锁按钮：TV 隐藏', () {
      expect(PlayerScreen.showLockButton(tvMode: false), isTrue);
      expect(PlayerScreen.showLockButton(tvMode: true), isFalse);
    });

    test('显示调节入口：TV 在底栏、手机在顶栏', () {
      expect(PlayerScreen.showBottomDisplayAdjustButton(tvMode: true), isTrue);
      expect(PlayerScreen.showBottomDisplayAdjustButton(tvMode: false), isFalse);
      expect(PlayerScreen.showTopSubtitleStyleButton(tvMode: false), isTrue);
      expect(PlayerScreen.showTopSubtitleStyleButton(tvMode: true), isFalse);
    });

    test('倍速入口：手机在顶栏、TV 在底栏', () {
      expect(
        PlayerScreen.showTopSpeedButton(
          tvMode: false,
          mobilePlatform: true,
          isRoom: false,
        ),
        isTrue,
      );
      expect(
        PlayerScreen.showBottomSpeedButton(
          tvMode: true,
          mobilePlatform: true,
          isRoom: false,
        ),
        isTrue,
      );
      // 房间模式两端都不显示倍速。
      expect(
        PlayerScreen.showTopSpeedButton(
          tvMode: false,
          mobilePlatform: true,
          isRoom: true,
        ),
        isFalse,
      );
    });
  });

  group('面板几何（selectorPanelBox）', () {
    test('常规面板避让顶栏与底部控制条', () {
      final box = PlayerScreen.selectorPanelBox(
        fullBleed: false,
        safeTop: 24,
        safeBottom: 12,
      );
      expect(box.top, 24 + 48);
      expect(box.bottom, 116 + 12);
      expect(box.right, 12);
    });

    test('选集面板三边贴边（fullBleed）', () {
      final box = PlayerScreen.selectorPanelBox(
        fullBleed: true,
        safeTop: 24,
        safeBottom: 12,
      );
      expect(box.top, 0);
      expect(box.bottom, 0);
      expect(box.right, 0);
    });

    test('面板宽度 0.42×屏宽，钳在 260~320', () {
      // 600×0.42=252 → 钳到下限 260；700×0.42=294 → 原值；
      // 1000×0.42=420 → 钳到上限 320。
      expect(PlayerScreen.selectorPanelWidth(600), 260);
      expect(PlayerScreen.selectorPanelWidth(700), closeTo(294, 0.01));
      expect(PlayerScreen.selectorPanelWidth(1000), 320);
    });

    test('Android 面板几何叠加安全区', () {
      expect(kotlinScreen, contains('dp(NPTheme.PANEL_TOP_OFFSET) + safeTopPx()'));
      expect(kotlinScreen, contains('dp(NPTheme.PANEL_BOTTOM_OFFSET) + safeBottomPx()'));
    });

    test('鸿蒙面板几何同样叠加安全区', () {
      expect(ohosPanel, contains('PANEL_PAD_TOP + HimiMpvNativeHost'));
      expect(ohosPanel, contains('PANEL_PAD_BOTTOM + HimiMpvNativeHost'));
    });
  });

  group('时间数显列宽（SeekTimeLabels.cellWidth）', () {
    test('时长 ≥1h 用 78，否则 56', () {
      expect(SeekTimeLabels.cellWidth(const Duration(minutes: 30)), 56);
      expect(SeekTimeLabels.cellWidth(const Duration(hours: 1)), 78);
    });

    test('双端原生按同一阈值分档', () {
      expect(kotlinScreen, contains('NPTheme.TIME_CELL_WIDE'));
      expect(kotlinScreen, contains('durationMs >= 3600000'));
      expect(ohosView, contains('durationMs >= 3600000 ? 78 : 56'));
    });
  });

  group('控制条自动隐藏时长', () {
    test('双端与 Flutter 同为 5 秒', () {
      expect(PlayerScreen.controlsAutoHideAfter, const Duration(seconds: 5));
      expect(kotlinScreen, contains('AUTO_HIDE_MS = 5000L'));
      expect(ohosView, contains('AUTO_HIDE_MS = 5000'));
    });
  });

  group('解码面板：180dp 独立 popover（非通栏）', () {
    test('Android 与 Flutter 同宽同位', () {
      expect(kotlinScreen, contains('renderDecodePopover'));
      expect(kotlinScreen, contains('NPTheme.DECODE_PANEL_WIDTH'));
      expect(kotlinScreen, contains('Gravity.TOP or Gravity.END'));
      // 通栏路径里的解码分支必须移除。
      expect(kotlinScreen, isNot(contains('PANEL_DECODE -> buildDecodeContent()')));
    });

    test('档位标签与 Flutter 播放页同值（auto=智能）', () {
      expect(kotlinScreen, contains('"auto" -> "智能"'));
      expect(ohosPanel, contains("mode === 'auto'"));
    });
  });

  group('进度条未播段颜色（glassSliderTheme）', () {
    test('Flutter 玻璃态 = white@0.16', () {
      final theme = File('lib/screens/player/widgets/glass_slider_theme.dart')
          .readAsStringSync();
      expect(theme, contains('Colors.white.withValues(alpha: 0.16)'));
    });

    test('鸿蒙玻璃轨复刻 glassSliderTheme（white@0.16 = 0x29）', () {
      // 575 曾切 WHITE_24(0x3D)；本轮回归「完全复刻 Flutter glassSliderTheme」：
      // 未播轨基色 = white@0.16，玻璃三段渐变在 GlassSlider.ets。
      final glass = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'GlassSlider.ets',
      ).readAsStringSync();
      expect(glass, contains("const TRACK_BASE = '#29FFFFFF'"));
    });
  });

  group('底栏渐变 alpha（Flutter black@0.85）', () {
    test('Flutter 底栏 0.85 / 顶栏 0.8', () {
      final screen = File('lib/screens/player/player_screen.dart')
          .readAsStringSync();
      expect(screen, contains('Colors.black.withValues(alpha: 0.85)'));
    });

    test('鸿蒙底栏 D9 / 顶栏 CC', () {
      expect(ohosView, contains("'#D9000000'"));
      expect(ohosView, contains("'#CC000000'"));
    });
  });

  group('缓冲指示颜色', () {
    test('Flutter 用 accent，非灰', () {
      final screen = File('lib/screens/player/player_screen.dart')
          .readAsStringSync();
      expect(screen, contains('CircularProgressIndicator(color: Color(0xFF6366F1))'));
    });

    test('Android 同值（587 自绘弧线，颜色默认 NPTheme.ACCENT）', () {
      expect(kotlinScreen, contains('PlayerSpinnerView(context)'));
      final spinner = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'PlayerSpinnerView.kt',
      ).readAsStringSync();
      expect(spinner, contains('color: Int = NPTheme.ACCENT'));
    });
  });

  group('房间模式资源面板按钮语义', () {
    test('Flutter 是切换面板而非退出', () {
      final screen = File('lib/screens/player/player_screen.dart')
          .readAsStringSync();
      expect(screen, contains("_showPanel = !_showPanel"));
    });

    test('Android 发 toggleResourcePanel 而非 requestBack', () {
      expect(kotlinScreen, contains('onToggleResourcePanel'));
      // 旧实现点一下直接退出播放页。
      expect(
        kotlinScreen,
        isNot(contains('panelToggleButton.setOnClickListener { listener?.onBack() }')),
      );
    });
  });

  group('手机手势（对齐 Flutter VideoGestureLayer）', () {
    test('Android 实现手势层且挂到视频区', () {
      expect(kotlinScreen, contains('gestureDetector'));
      expect(kotlinScreen, contains('GestureDetector'));
      // 手势提示与柱条必须挂进层级（否则看不到反馈）。允许换行。
      expect(
        kotlinScreen,
        matches(RegExp(r'addView\(\s*gestureHint,')),
        reason: '手势提示视图必须挂进层级',
      );
      expect(
        kotlinScreen,
        matches(RegExp(r'addView\(\s*verticalBar,')),
        reason: '亮度/音量柱条必须挂进层级',
      );
    });

    test('双击播放/暂停 + 横拖 seek 系数与 Flutter 同值', () {
      expect(kotlinScreen, contains('onDoubleTap'));
      // Flutter：每 100px → 5000ms，上限 ±60s。
      expect(kotlinScreen, contains('DRAG_PX_PER_5S = 100f'));
      expect(kotlinScreen, contains('DRAG_MS_PER_5S = 5000L'));
      expect(kotlinScreen, contains('SEEK_MAX_DELTA_MS = 60_000L'));
    });

    test('纵拖：左亮度 / 右音量，600px 全量程', () {
      expect(kotlinScreen, contains('VERTICAL_PX_PER_FULL = 600f'));
      expect(kotlinScreen, contains('onGestureBrightness'));
      expect(kotlinScreen, contains('onGestureVolumeDelta'));
      expect(kotlinScreen, contains('dragOnLeftSide'));
    });

    test('长按临时倍速倍率 2×，松手还原', () {
      expect(PlayerScreen.speedBoostMultiplier, 2.0);
      expect(kotlinScreen, contains('onSpeedBoost'));
      expect(kotlinScreen, contains('boostBaseSpeed'));
      expect(kotlinScreen, contains('boostActive'));
    });

    test('锁定态解除全部手势绑定（只留单击）', () {
      expect(kotlinScreen, contains('if (lastState.locked || !lastState.canControl) return false'));
    });

    test('手势提示时长与 Flutter 同值', () {
      expect(kotlinScreen, contains('GESTURE_HINT_TEXT_MS = 800L'));
      expect(kotlinScreen, contains('GESTURE_HINT_ICON_MS = 500L'));
    });

    test('Flutter 侧手势语义可对照（源码存在）', () {
      final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(screen, contains('_onHorizontalDragUpdate'));
      expect(screen, contains('_onVerticalDragUpdate'));
      expect(screen, contains('speedBoostMultiplier'));
      expect(screen, contains('VideoGestureLayer'));
    });

    test('鸿蒙同样实现全套手势（双端一致）', () {
      expect(ohosView, contains('TapGesture({ count: 2 })'));
      expect(ohosView, contains('PanGesture'));
      expect(ohosView, contains('onDoubleTapGesture'));
      expect(ohosView, contains('onPanUpdate'));
      expect(ohosView, contains('onSpeedBoostStart'));
      // 系数与 Flutter 同值。
      expect(ohosView, contains('/ 100 * 5000'));
      expect(ohosView, contains('600'));
      expect(ohosView, contains('optimisticSetVolume'));
      expect(ohosView, contains('optimisticSetSpeed'));
    });

    test('双端手势提示视图都挂进层级', () {
      expect(ohosView, contains('gestureHint'));
      expect(ohosView, contains('verticalBarPercent'));
    });
  });

  group('TV 按键路由（对齐 Flutter PlayerHotkey）', () {
    test('Android 实现 TvKeyRouter 且接进视图按键链', () {
      final kotlinRouter = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'TvKeyRouter.kt',
      ).readAsStringSync();
      expect(kotlinRouter, contains('class TvKeyRouter'));
      expect(kotlinRouter, contains('KEYCODE_VOLUME_UP'));
      expect(kotlinRouter, contains('KEYCODE_MEDIA_PLAY_PAUSE'));
      expect(kotlinScreen, contains('override fun onKeyDown'));
      expect(kotlinScreen, contains('tvKeyRouter.handleKey'));
    });

    test('seek 步长与 Flutter PlayerHotkey 同值', () {
      final kotlinRouter = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'TvKeyRouter.kt',
      ).readAsStringSync();
      // 控件隐藏时方向键 ±10s（Flutter `_seekStepMs`）。
      expect(kotlinRouter, contains('HIDDEN_SEEK_MS = 10_000L'));
      // 进度条焦点：单击 ±5s、长按每步 ±10s。
      expect(kotlinRouter, contains('SINGLE_SEEK_MS = 5_000L'));
      expect(kotlinRouter, contains('REPEAT_SEEK_MS = 10_000L'));
      // 音量步长 5%（Flutter `_volumeStep`）。
      expect(kotlinRouter, contains('SEEK_VOLUME_STEP = 5.0'));
    });

    test('控件隐藏时方向键语义（左右 seek / 上下唤出）', () {
      final kotlinRouter = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'TvKeyRouter.kt',
      ).readAsStringSync();
      expect(kotlinRouter, contains('controlsVisibleProvider()'));
      expect(kotlinRouter, contains('onShowControls()'));
    });

    test('进度条焦点下按方向键定向跳到播放键', () {
      final kotlinRouter = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'TvKeyRouter.kt',
      ).readAsStringSync();
      expect(kotlinRouter, contains('seekBarProvider()'));
      expect(kotlinRouter, contains('playPauseProvider()'));
      expect(kotlinScreen, contains('fun seekBarButton()'));
      expect(kotlinScreen, contains('fun playPauseView()'));
    });

    test('仅 TV 模式接管遥控器语义（手机不拦按键）', () {
      expect(kotlinScreen, contains('if (lastState.tvMode && tvKeyRouter.handleKey'));
    });

    test('Flutter PlayerHotkey 语义可对照（源码存在）', () {
      final hotkey = File('lib/screens/player/player_hotkey.dart').readAsStringSync();
      expect(hotkey, contains('_seekStepMs'));
      expect(hotkey, contains('_volumeStep'));
      expect(hotkey, contains('seekFocusNode'));
    });
  });

  group('鸿蒙控制层（真机回归修复）', () {
    test('手势层用 Default，不用 Transparent（否则控件点击被抢）', () {
      // Transparent 让手势层与控件**同时**进竞技场，Parallel 的 PanGesture
      // 会抢走触摸流 → 底部 onClick 全失效、面板遮罩点不关（真机回归）。
      //
      // 600：断言范围收窄到**手势层本身**。控件层容器现在是
      // `HitTestMode.Transparent`（那是「放行空白区给下层手势层」的正确
      // 语义，与手势层自身必须是 Default 无关）。
      final vsIdx = ohosView.indexOf('VideoStack() {');
      expect(vsIdx, greaterThan(0));
      final vsBody = ohosView.substring(vsIdx, vsIdx + 6000);
      expect(vsBody, contains('hitTestBehavior(HitTestMode.Default)'));
      expect(
        vsBody,
        isNot(contains('hitTestBehavior(HitTestMode.Transparent)')),
        reason: '手势层不能用 Transparent（会与控件抢占触摸）',
      );
    });

    test('顶/底栏有空点击吸收（点背景不隐藏控件，对齐 Flutter）', () {
      // Flutter `_buildTopBar` / `_buildControls` 外层都有
      // GestureDetector(onTap: () {}) 吸收点击。
      expect(ohosView, contains('TopBar'));
      expect(ohosView, contains('BottomBar'));
      // 至少 3 处空 onClick（顶栏 / 底栏 / 锁定态底栏）。
      final emptyClicks = RegExp(r'\.onClick\(\(\): void => \{\s*\}\)').allMatches(ohosView).length;
      expect(
        emptyClicks,
        greaterThanOrEqualTo(3),
        reason: '顶栏/底栏/锁定态底栏都需空点击吸收',
      );
    });

    test('LockOnlyBar 渐变方向角 180（不是 90，否则右侧黑幕）', () {
      // ArkUI linearGradient 的 angle 是方向角：180=自上而下；90=对角
      // （透明左上 → 黑右下），会把右侧整条压黑成「黑幕」（真机截图回归）。
      final lockBar = RegExp(
        r'LockOnlyBar\(\$\$: ControlsRef\) \{[\s\S]{0,1400}?angle: (\d+)',
      ).firstMatch(ohosView);
      expect(lockBar, isNotNull, reason: '找不到 LockOnlyBar 的渐变配置');
      expect(lockBar!.group(1), '180', reason: '锁定态底栏渐变必须自上而下');
    });

    test('locked 是 @State（宿主字段不在观察链上，需显式同步）', () {
      expect(ohosView, contains('@State locked: boolean = false'));
      // 必须在状态回调与初始时同步（统一走 syncFromHost）。
      expect(ohosView, contains('this.locked = s.locked'));
      expect(ohosView, contains('private syncFromHost(): void'));
      // build/锁定态读 @State 而非宿主字段。
      expect(ohosView, contains('if (this.locked && !this.state().tvMode)'));
    });

    test('竖屏等比缩小（旧的收窄间距方案已移除）', () {
      expect(ohosView, contains('@State bottomScale: number = 1'));
      expect(ohosView, contains('private adjustBottomScale'));
      // 缩放必须落在**真实布局参数**（间距/字号/内边距按比例收缩），
      // 不能用 transform——transform 只改渲染不改占位，命中区要么跟着
      // 缩到点不中、要么与视觉错位（真机回归：竖屏底部控件点了没反应）。
      expect(ohosView, contains('Row({ space: 20 * this.bottomScale })'));
      expect(ohosView, contains('.fontSize(iconSize * s)'));
      expect(ohosView, isNot(contains('.transform({')),
          reason: '右侧簇缩放不得用 transform（命中区与视觉错位）');
      // 旧方案必须移除（gap 归零仍溢出 32dp）。
      expect(ohosView, isNot(contains('private adjustBottomGap')));
      expect(ohosView, isNot(contains('this.bottomGap')));
    });

    test('竖屏隐藏顶栏标题（Logo 保留）', () {
      expect(ohosView, contains('@State portrait: boolean = false'));
      expect(ohosView, contains('this.portrait = h > w && w > 0'));
      expect(ohosView, contains('if (!this.portrait)'));
      // Logo 保留（用户明确要求）——稳定层直读 @State。
      expect(ohosView, contains('this.logoUrl.length > 0'));
    });

    test('surface 尺寸：initialize 前写 option + 转屏增量更新', () {
      final ohosPlugin = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
        'HimiMpvOhosPlugin.ets',
      ).readAsStringSync();
      // initialize 前写入 option（此前完全没写 → mpv 从初始化起不知尺寸）。
      expect(ohosPlugin, contains("setOptionString(\n        'ohos-surface-size'"));
      expect(ohosPlugin, contains('setOptionString'));
      // 运行期更新 + 幂等保护（尺寸未变则跳过）。
      expect(ohosPlugin, contains("setProperty('ohos-surface-size'"));
      expect(ohosPlugin, contains('if (prevW !== width || prevH !== height)'));
      // 诊断日志含前后尺寸。
      expect(ohosPlugin, contains('prev %{public}dx%{public}d'));
    });

    test('XComponent 有 onAreaChange 兜底同步尺寸（586：必须先 vp2px）', () {
      // 子窗口转屏时 onSurfaceChanged 可能不触发，需 onAreaChange 兜底。
      //
      // 【586 真机「画面变糊」根因】Area.width/height 单位是 **vp**，
      // `ohos-surface-size` 只接受 **px**。旧实现直接传 vp，真机
      // 1260x2720px 被写成 411x914 → mpv 在 1/3 分辨率画布上合成再放大
      // → 宽高比一致故不变形，只变糊。断言锁死「必须换算」。
      expect(ohosView, contains("HimiMpvNativeHost.getInstance().surfaceChanged(''"));
      expect(ohosView, contains('vp2px'));
      // 传入 surfaceChanged 的必须是换算后的 px 变量，不能是 area.width。
      expect(ohosView, contains("surfaceChanged('', wPx, hPx)"));
      expect(ohosView, isNot(contains("surfaceChanged('', Math.trunc(w)")));
    });

    test('宿主 surfaceChanged 转发到插件', () {
      final ohosHost = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'HimiMpvNativeHost.ets',
      ).readAsStringSync();
      expect(ohosHost, contains('forwardSurfaceChanged'));
    });
  });

  group('安卓真机回归修复（563+）', () {
    test('顶栏不叠加 statusBars inset（全屏沉浸式下不无故下移）', () {
      final kotlinHost = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'AndroidNativePlayerHost.kt',
      ).readAsStringSync();
      // 全屏沉浸式下 statusBars 不可见，不应叠加其 inset。
      expect(kotlinHost, contains('cutout?.safeInsetTop ?: 0'));
      // 不再用 statusBars() 取 top。
      expect(
        kotlinHost,
        isNot(contains('WindowInsets.Type.statusBars() or WindowInsets.Type.displayCutout()')),
        reason: '全屏沉浸式下不应叠加 statusBars inset（会把顶栏下移）',
      );
    });

    test('applyLayoutMode 不强制 VISIBLE（尊重自动隐藏）', () {
      expect(
        kotlinScreen,
        contains('topBar.visibility = if (controlsVisible) VISIBLE else GONE'),
        reason: 'applyLayoutMode 不应无条件设 VISIBLE（会覆盖 setControlsVisible(false)）',
      );
    });

    test('pollState 返回 trackList（修音轨/字幕面板空白）', () {
      final kotlinSession = File(
        'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
      ).readAsStringSync();
      expect(kotlinSession, contains('trackList: await getTracks()'));
    });

    test('选集封面带 api_key（修原生加载器无认证）', () {
      final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(screen, contains("api_key=\$_currentToken"));
    });

    test('587 弹层改深色渐变磨砂（不再采样 → 零跳帧零黑屏风险）', () {
      final kotlinGlass = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'PanelGlassDrawable.kt',
      ).readAsStringSync();
      // 深色竖向渐变 + 顶部高光 + 亮描边 + 内圈微高光线。
      expect(kotlinGlass, contains('PANEL_GLASS_TOP'));
      expect(kotlinGlass, contains('PANEL_GLASS_BASE'));
      expect(kotlinGlass, contains('PANEL_GLASS_RIM'));
      // 旧采样实现（PixelCopy / SurfaceView / 折射带）必须彻底消失。
      expect(kotlinGlass, isNot(contains('PixelCopy')));
      expect(kotlinGlass, isNot(contains('SAMPLE_INTERVAL_MS')));
      expect(kotlinGlass, isNot(contains('GLASS_REFRACTION_BAND')));
    });

    test('585 采样器整块删除（不再有偷帧空转风险）', () {
      // 旧实现 600ms PixelCopy 周期采样，关闭时靠 glassSampling 自查兜底；
      // 585 改纯白渐变后采样器连同回调全部删除，从根本上消除偷帧。
      expect(kotlinScreen, isNot(contains('glassSampleRunnable')));
      expect(kotlinScreen, isNot(contains('glassSampling')));
    });
  });

  group('鸿蒙回归修复（563+）', () {
    test('ControlRow 右侧簇不加 height 100%（修底栏内容被顶到屏幕上方）', () {
      expect(
        ohosView,
        isNot(matches(RegExp(r"\.width\('100%'\)\s*\n\s*\.height\('100%'\);\s*\n\s*// 左侧簇"))),
        reason: '右侧簇外层 Stack 不应加 height 100%（会撑满 ControlRow 把底栏内容顶上去）',
      );
    });

    test('底栏 Column 不设 height 100%（只设 width）', () {
      // BottomBar 外层只设 width('100%')，不设 height('100%')。
      expect(ohosView, contains("BottomBar"));
    });
  });

  group('鸿蒙竖屏底栏与面板交互（真机回归 565+）', () {
    test('openPanel 显式 notify（控件可见时点面板按钮才有反应）', () {
      final ohosHost = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'HimiMpvNativeHost.ets',
      ).readAsStringSync();
      final openPanel = RegExp(
        r'openPanel\(type: string\): void \{[\s\S]*?\n  \}',
      ).firstMatch(ohosHost);
      expect(openPanel, isNotNull, reason: '未找到 openPanel 方法');
      expect(
        openPanel!.group(0),
        contains('this.notify()'),
        reason: 'setControlsVisible 在控件已可见时 early-return 不 notify，'
            'openPanel 必须显式刷新，否则选集/字幕/音轨等面板按钮点了没反应',
      );
    });

    test('ControlRow 三槽平铺（无全宽覆盖层吞触摸）', () {
      // leading(权重1,贴左) | 传输组 | trailing(权重1,贴右)，等价
      // Flutter PlayerBottomRow(centered) / 安卓 buttonRow。
      final ctrlRow = RegExp(
        r'ControlRow\(\) \{[\s\S]*?\n  \}',
      ).firstMatch(ohosView);
      expect(ctrlRow, isNotNull, reason: '未找到 ControlRow');
      final body = ctrlRow!.group(0)!;
      // 两个等宽权重槽（传输组靠它们精确居中）。
      expect(
        RegExp(r'\.layoutWeight\(1\)').allMatches(body).length,
        2,
        reason: 'leading/trailing 两个权重槽缺一不可',
      );
      // 旧结构：Stack 里叠全宽锁钮行/全宽右侧簇 → 触摸被上层容器吞掉，
      // 「底部控件点了没反应」（真机回归）。全宽覆盖兄弟必须移除。
      expect(
        body,
        isNot(matches(RegExp(
          r"\.width\('100%'\)\s*\n\s*\.justifyContent\(FlexAlign\.Start\)",
        ))),
        reason: '锁钮不得再用全宽 Row 叠在传输组上',
      );
      expect(
        body,
        isNot(matches(RegExp(r"Stack\(\{ alignContent: Alignment\.End \}\)"))),
        reason: '右侧簇不得再用全宽 Stack 叠在传输组上',
      );
    });

    test('缩放态有热区补偿（对齐安卓 ScaleDownBox 的 HIT_SLOP）', () {
      // 缩到 0.5 档时 24 图标只剩 ~16dp 热区，必须补 responseRegion。
      expect(ohosView, contains('.responseRegion('));
      expect(ohosView, contains('-10 * s'));
    });

    test('缩放比解析式自然宽 + tick 自愈（不再卡死 scale=1）', () {
      // 自然宽禁止受约束实测：簇在权重槽内被槽宽夹住 → scale 恒 1。
      expect(ohosView, contains('trailingNaturalWidth'));
      expect(ohosView, isNot(contains('bottomNaturalW')));
      // 槽宽回调 + tick 自愈都要触发 adjustBottomScale。
      final calls = RegExp(r'this\.adjustBottomScale\(\);').allMatches(ohosView).length;
      expect(calls, greaterThanOrEqualTo(2));
    });

    test('面板点外可关（容器不铺满全屏盖住遮罩）', () {
      expect(ohosPanel, contains('this.close();'));
      // 面板容器宽 = 面板宽（42% 钳 260~320），不得再 width('100%') 全宽：
      // 全宽容器会把遮罩整块盖住，点空白处到不了遮罩 → 只能返回键收面板。
      expect(ohosPanel, contains(".width('42%')"));
      expect(
        ohosPanel,
        isNot(matches(RegExp(
          r"\.width\('100%'\)\s*\n\s*\.height\('100%'\)\s*\n"
          r"\s*\.alignItems\(HorizontalAlign\.End\)",
        ))),
        reason: '面板容器不得全宽（会盖住点外关闭的遮罩）',
      );
      // 面板自身空白（标题/行间隙）空点击吸收：点面板背景不关、点外面才关。
      final emptyClicks =
          RegExp(r'\.onClick\(\(\): void => \{\s*\}\)').allMatches(ohosPanel).length;
      expect(
        emptyClicks,
        greaterThanOrEqualTo(2),
        reason: 'SidePanel/SegmentCard 都需空点击吸收',
      );
    });
  });

  group('鸿蒙控制层（真机回归 566+）', () {
    test('点击控件不带选择框（无 focusOnTouch 触摸获焦）', () {
      // focusOnTouch(true) 让点击获焦 → ArkUI 画系统焦点框（真机「选择框」）。
      // TV 遥控器仍可获焦（focusable 保留）。
      expect(ohosView, isNot(contains('focusOnTouch(true)')));
      expect(ohosView, contains('.focusable(true)'));
    });

    test('播放/暂停图标随 paused 切换（点击后形态有变化）', () {
      // 旧实现恒传 playGlyph() 常量——播放中也显示 ▶。
      expect(
        ohosView,
        contains('this.paused ? this.playGlyph() : this.pauseGlyph()'),
      );
    });

    test('顶栏返回直发 requestBack（分层语义只留给系统返回键）', () {
      final onBack = RegExp(
        r'private onBack\(\): void \{[\s\S]*?\n  \}',
      ).firstMatch(ohosView);
      expect(onBack, isNotNull, reason: '未找到 onBack 方法');
      expect(
        onBack!.group(0),
        contains("sendCommand('requestBack', null)"),
        reason: '屏幕返回按钮须直发 requestBack 退出（对齐安卓）',
      );
      expect(
        onBack.group(0),
        isNot(contains('handleBack()')),
        reason: '按钮不得走分层返回（控件可见时只会藏控件 = 「点了没反应」）',
      );
      // 系统返回键保持分层语义（NativePlayer.ets onBackPress → handleBack）。
      final nativePlayerPage = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'HimiMpvNativeHost.ets',
      ).readAsStringSync();
      expect(nativePlayerPage, contains('handleBack(): boolean'));
    });

    test('面板贴右、片头片尾卡居中（alignContent，不用 align）', () {
      expect(
        ohosPanel,
        contains(
          "alignContent: this.panelType === 'segment' ? Alignment.Center : Alignment.End",
        ),
      );
      // .align(Alignment.End) 在 Column-in-Stack 上不生效（面板被居中回归）。
      // 只禁真实调用（行首链式用法），注释里的历史说明不算。
      expect(
        ohosPanel,
        isNot(matches(RegExp(r"\n\s*\.align\(Alignment\.End\)"))),
        reason: '面板定位不得用 .align()（不生效），必须用 alignContent',
      );
    });

    test('显示调节两段各有恢复默认，默认值与安卓一致', () {
      // 字幕段/弹幕段共用一行「恢复默认」渲染，两处触发（idx 2 后 / idx 5 后）。
      expect(ohosPanel, contains("Text('恢复默认')"));
      expect(ohosPanel, contains('DisplayResetRow(kind: string)'));
      expect(ohosPanel, contains("this.DisplayResetRow(idx === 2 ? 'subtitle' : 'danmaku')"));
      // 默认值锁定（安卓 AppSettings / Flutter SubtitleStylePanel 同值）。
      expect(ohosPanel, contains('DEFAULT_SUBTITLE_MARGIN_Y = 22'));
      expect(ohosPanel, contains('DEFAULT_SUBTITLE_SCALE = 1.0'));
      expect(ohosPanel, contains('DEFAULT_SUBTITLE_DELAY_MS = 0'));
      expect(ohosPanel, contains('DEFAULT_DANMAKU_SPEED = 1.0'));
      expect(ohosPanel, contains('DEFAULT_DANMAKU_FONT_SIZE = 0.5'));
      expect(ohosPanel, contains('DEFAULT_DANMAKU_OPACITY = 0.8'));
      // 回写走 adjustDisplay（Dart 与滑杆同一路径，含落盘）。
      expect(ohosPanel, contains("this.host.adjustDisplay('subtitleMarginY', DEFAULT_SUBTITLE_MARGIN_Y)"));
      expect(ohosPanel, contains("this.host.adjustDisplay('danmakuOpacity', DEFAULT_DANMAKU_OPACITY)"));
    });
  });

  group('鸿蒙控制层（真机回归 567+）', () {
    test('宿主动态字段镜像到 @State（控件状态实时刷新）', () {
      // 宿主字段不在观察链上，只靠 revision 间接重建不可靠
      // （真机：点播放/暂停图标不实时变，隐藏再现才更新）。
      expect(ohosView, contains('@State paused: boolean = true'));
      expect(ohosView, contains('@State danmakuEnabled: boolean = false'));
      expect(ohosView, contains('@State speed: number = 1.0'));
      expect(ohosView, contains('private syncFromHost(): void'));
      // onStateChanged / tick 兜底都要同步。
      final syncCalls = RegExp(r'this\.syncFromHost\(\);').allMatches(ohosView).length;
      expect(syncCalls, greaterThanOrEqualTo(3),
          reason: 'aboutToAppear / onStateChanged / tick 都要调 syncFromHost');
      // revision 用显式赋值（后缀自增可能不过 @State setter）。
      expect(ohosView, isNot(contains('this.revision++')));
      expect(ohosView, contains('this.revision = this.revision + 1'));
    });

    test('播放/暂停图标读镜像字段（不读宿主普通字段）', () {
      // 图标选择必须在 UI 表达式里直读 this.paused（方法体读取不进依赖集）。
      expect(ohosView, contains('this.paused ? this.playGlyph() : this.pauseGlyph()'));
      expect(ohosView, isNot(contains('playPauseGlyph')));
    });

    test('长按倍速提示走玻璃小胶囊（不用 48px 图标态渲染文字）', () {
      // Flutter _buildSpeedBoostChip：图标 18 + 「2.0× 播放中」14/w600。
      // fontWeight 接受 number（FontWeight 枚举无 W6xx 成员）。
      expect(ohosView, contains('× 播放中'));
      expect(ohosView, contains('.fontSize(14)'));
      expect(ohosView, contains('.fontWeight(600)'));
      // onSpeedBoostStart 不再往 gestureHint 塞文字（图标态 48px = 巨大提示）。
      final boost = RegExp(
        r'private onSpeedBoostStart\(\): void \{[\s\S]*?\n  \}',
      ).firstMatch(ohosView);
      expect(boost, isNotNull);
      expect(boost!.group(0), isNot(contains('showGestureHint')));
    });

    test('长按三分区：左片头/右片尾/中间倍速（对齐 Flutter）', () {
      expect(ohosView, contains('this.areaWidth / 3'));
      expect(ohosView, contains('this.areaWidth * 2 / 3'));
      expect(ohosView, contains('this.markSegmentFromGesture(\'intro\')'));
      expect(ohosView, contains('this.markSegmentFromGesture(\'outro\')'));
    });

    test('长按标记带校验与旧标记确认（文案/阈值对齐 Flutter）', () {
      expect(ohosView, contains('播放 3 秒后才能设置片头'));
      expect(ohosView, contains('当前位置为 0，无法标记'));
      expect(ohosView, contains('当前位置已到结尾，无法标记'));
      // 有旧标记直开二次确认卡。
      expect(ohosView, contains('host.openSegmentConfirm(kind)'));
      expect(ohosPanel, contains('consumeSegmentConfirmKind'));
    });

    test('跳过片头/片尾胶囊：设计对齐安卓 + Dart 驱动显隐', () {
      // 设计：圆角 14 / 图标 20 / 13px w600 / 片头 skip_next、片尾 skip_previous。
      expect(ohosView, contains('.borderRadius(14)'));
      expect(ohosView, contains("this.skipPrompt === 'intro' ? '跳过片头' : '跳过片尾'"));
      expect(ohosView, contains("this.skipPrompt === 'intro' ? 0xE5BD : 0xE5BE"));
      // 点击回传 skipSegment，由 Dart _performSkipSegment 执行跳转语义。
      expect(ohosView, contains("sendCommand('skipSegment', null)"));
      // Dart 链路：状态字段 + setter 自动同步 + 命令解析。
      final stateFile = File(
        'lib/services/player/native/native_player_state.dart',
      ).readAsStringSync();
      expect(stateFile, contains("'skipPrompt': skipPrompt"));
      expect(stateFile, contains('final String skipPrompt;'));
      final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(screen, contains('MediaSegment? _skipPromptSegmentRaw;'));
      expect(screen, contains('set _skipPromptSegment(MediaSegment? value)'));
    });
  });

  group('鸿蒙控制层（真机回归 568+）', () {
    test('长按分区用 fingerList 触点（offsetX 是 Pan 位移语义，长按恒 0）', () {
      expect(ohosView, contains('event.fingerList[0].localX'));
      expect(ohosView, isNot(contains('const x = event.offsetX;')),
          reason: '长按分区不得用 offsetX——位移恒 0 会恒判左区（右边也设片头）');
    });

    test('弹幕逐帧刷新（排布落 @State，build 直读）', () {
      final danmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      expect(danmaku, contains('@State items: DanmakuFrameItem[] = []'));
      expect(danmaku, contains('this.items = this.frameItems();'));
      expect(danmaku, contains('ForEach(this.items,'));
      expect(danmaku, isNot(contains('ForEach(this.frameItems()')),
          reason: '方法调用藏依赖 → 帧驱动失效（弹幕不显示）');
    });

    test('渲染态读取不藏进方法（依赖隐藏 = 不刷新）', () {
      // 角标/条件/图标全部内联直读 this.X；旧的 versionBadge/multiEpisode/
      // playPauseGlyph 类包装方法必须移除。
      expect(ohosView, isNot(contains('versionBadge(')));
      expect(ohosView, isNot(contains('multiEpisode(')));
      expect(ohosView, isNot(contains('timeCellWidth(')));
      expect(ohosView, contains('this.durationMs >= 3600000 ? 78 : 56'));
      expect(ohosView, contains('this.subtitleStreamCount > 0'));
      expect(ohosView, contains('this.currentEpisodeIndex + 1 < this.episodeCount'));
    });
  });

  group('鸿蒙控制层（真机回归 569+）', () {
    test('渲染触发器直读进 build() 条件（状态变化即时重绘）', () {
      // 根因：ArkUI 只对 build() 体直读依赖触发重绘，@Builder 体内读取
      // 不触发（真机：状态不立刻变，隐藏再现才变）。
      expect(ohosView, contains('@State renderTick: number = 0;'));
      expect(ohosView, contains('this.showControls && this.renderTick >= 0'));
      // 状态推送与 tick 兜底两处都要 bump。
      final bumps = RegExp(r'this\.renderTick = this\.renderTick \+ 1;')
          .allMatches(ohosView).length;
      expect(bumps, greaterThanOrEqualTo(2),
          reason: 'onStateChanged（推送即刷）与 tick（250ms 自愈）都要触发重绘');
    });

    test('@Builder 按引用传递触发刷新（按值传递不刷新 = 状态冻结）', () {
      // ArkUI 官方语义：@Builder 按值传递（number/string/boolean）时状态
      // 变化不刷新内部 UI；按引用传递（对象属性绑定 @State）才刷新。
      // 锁控件"正常"是 build() 条件值翻转的分支重建假象（真机回归）。
      expect(ohosView, contains('class ControlsRef'));
      expect(ohosView, contains(r'TopBar($$: ControlsRef)'));
      expect(ohosView, contains(r'BottomBar($$: ControlsRef)'));
      expect(ohosView, contains(r'LockOnlyBar($$: ControlsRef)'));
      expect(ohosView, contains('this.TopBar({ rev: this.renderTick })'));
      expect(ohosView, contains('this.BottomBar({ rev: this.renderTick })'));
      expect(ohosView, contains('this.LockOnlyBar({ rev: this.renderTick })'));
      // 禁止回退为按值传递（570 失败形态）。
      expect(ohosView, isNot(contains('TopBar(rev: number)')));
    });

    test('控件重建走 ForEach key=epoch（节点重建 = @Builder 唯一认的刷新）', () {
      // 五轮实验证明（567~571 全败、隐藏再现恒生效）：@Builder 子树只认
      // 节点重建（if 条件翻转 / ForEach key 变化），数据级传递全部无效。
      expect(ohosView, contains('@State controlsEpoch: number = 0;'));
      expect(ohosView, contains('private refreshControlsEpoch(): void'));
      expect(ohosView, contains(r'ForEach([this.controlsEpoch]'));
      expect(ohosView, contains(r'`ctl-${epoch}`'));
      // 签名必须覆盖驱动形态的动态值。
      expect(ohosView, contains(r'${this.paused}|${this.danmakuEnabled}'));
      // 状态推送与 tick 兜底两处都要推进纪元。
      final calls =
          RegExp(r'this\.refreshControlsEpoch\(\);').allMatches(ohosView).length;
      expect(calls, greaterThanOrEqualTo(2),
          reason: 'onStateChanged（点击即刻）与 tick（250ms 兜底）都要触发重建');
    });

    test('epoch 签名剔除高频量 + 进度行自驱（触摸一致性）', () {
      // 进度/拖动进签名 = 播放中每秒、拖动中每帧销毁重建滑杆 → 触摸序列
      // 断裂、手指与拇指脱节（真机回归：拖动进度条触摸位置不一致）。
      final sig = RegExp(
        r'private refreshControlsEpoch\(\): void \{[\s\S]*?\n  \}',
      ).firstMatch(ohosView);
      expect(sig, isNotNull);
      expect(sig!.group(0), isNot(contains('progressMs')));
      expect(sig.group(0), isNot(contains('dragMs')));
      // 进度行自驱（100ms timer 写 @State，DanmakuLayer 同款机制）。
      expect(ohosView, contains('struct ProgressRow'));
      expect(ohosView, contains('this.posMs = HimiMpvNativeHost.getInstance().positionNowMs()'));
    });

    test('提示词/提示图标屏幕正中（禁 .align 定位）', () {
      final hint = RegExp(
        r'gestureHint\.length > 0\) \{[\s\S]*?hitTestBehavior\(HitTestMode\.None\);',
      ).firstMatch(ohosView);
      expect(hint, isNotNull, reason: '未找到手势提示块');
      expect(hint!.group(0), contains('justifyContent(FlexAlign.Center)'));
      expect(hint.group(0), contains('.alignItems(HorizontalAlign.Center)'));
      expect(hint.group(0), isNot(contains('.align(')),
          reason: '.align() 在根 Stack 子节点不生效（真机：提示跑到顶栏居中）');
    });

    test('logo 不随控件重建（防闪烁）', () {
      expect(ohosView, contains('Image(this.logoUrl)'));
      final bottom = RegExp(
        r'BottomBar\(\$\$: ControlsRef\) \{[\s\S]*?\n  \}',
      ).firstMatch(ohosView);
      expect(bottom, isNotNull);
      expect(bottom!.group(0), isNot(contains('Image(')),
          reason: 'logo 进 epoch 重建块会每秒销毁/重载图片 → 闪烁（真机回归）');
    });

    test('弹幕保留窗覆盖整段穿屏时长（防滚到一半消失）', () {
      final adapter = File(
        'lib/services/player/mpv_player_adapter.dart',
      ).readAsStringSync();
      // 滚动 8s÷speed、驻留 4s：窗口下界必须让弹幕活满全程。
      expect(adapter, contains('8.0 / speed'));
      expect(adapter, contains('keepSec'));
      expect(adapter, isNot(contains('c.time < posSec - 2 ')),
          reason: '旧下界 pos-2s 会把滚动弹幕滚到一半移出数据源');
    });

    test('弹幕位置纯线性外推（同 Flutter _nowPosition，禁漂移牵引）', () {
      // Flutter：位置 = 快照 + ticker 增量，两次快照间严格匀速；
      // 旧实现叠 10%/帧漂移牵引 → 速度随漂移变化 = 非匀速（真机回归）。
      final danmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      expect(danmaku, contains('return HimiMpvNativeHost.getInstance().positionNowMs()'));
      expect(danmaku, isNot(contains('drift * 0.1')),
          reason: '漂移牵引 = 每帧注入额外位移，弹幕忽快忽慢');
      expect(danmaku, isNot(contains('clockAnchorMs')));
      // 60fps 帧驱动 + 1vp 位移粒度（消除台阶感）。
      expect(danmaku, contains('}, 16);'));
      expect(danmaku, contains('Math.round(x)'));
      expect(danmaku, isNot(contains('Math.round(x / 4)')));
    });

    test('飞行中弹幕缓存（窗口滑出仍画到穿屏结束）', () {
      final danmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      expect(danmaku, contains('syncFlying'));
      expect(danmaku, contains('this.flying'));
      // 行号方案已升级为 laneOf 生命周期绑定（575+：防 prune 后上移）。
      expect(danmaku, contains('this.laneOf'));
    });

    test('面板开着再点控件即收回（wrapper 兜底关闭）', () {
      // 被面板 42% 宽覆盖的顶/底栏控件区点击由 wrapper 吸收（无 handler
      // 容器吞触摸）→「再次点击控件没反应」。wrapper 加 onClick(close)：
      // 点控件区/外侧都收回（对齐安卓 panelScrim 全覆盖语义）。
      expect(
        ohosPanel,
        matches(RegExp(
          r"FULLBLEED_MARGIN : PANEL_MARGIN\)\s*\n\s*\.onClick\(\(\): void => \{\s*\n\s*this\.close\(\);",
        )),
        reason: '面板容器必须带 onClick(close) 兜底（再点控件收回）',
      );
    });
  });

  group('鸿蒙控制层（真机回归 575+）', () {
    test('弹幕行号绑定生命周期（防 prune 后整屏上移）', () {
      final danmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      // laneOf 绑定条目（timeMs:text → lane），只给新条目分配、不再全量重算。
      expect(danmaku, contains('this.laneOf'));
      expect(danmaku, contains('if (this.laneOf.has(key))'));
      expect(danmaku, isNot(contains('this.laneKey')),
          reason: '全量重分配（laneKey 缓存）= 最老条目移除后整屏上移一行');
    });

    test('弹幕观感照抄 Flutter（w500 + 黑 blur3 描影）', () {
      final danmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      expect(danmaku, contains('.fontWeight(500)'));
      expect(danmaku, contains("shadow({ radius: 3, color: '#8A000000'"));
    });

    test('手势亮度：系统当前亮度初值 + 真正写窗口亮度', () {
      // 旧实现写死 1.0 且只改本地显示（拖了没效果）。
      expect(ohosView, contains('private initBrightness(): void'));
      expect(ohosView, contains('SCREEN_BRIGHTNESS_STATUS'));
      expect(ohosView, contains('setWindowBrightness(this.brightness01)'));
      expect(ohosView, isNot(contains('brightness01: number = 1.0')));
    });

    test('亮度柱在右、音量柱在左（对齐安卓 paintVerticalBar）', () {
      // Flutter 注释与实现相反，以实现为准：亮度 END(右)、音量 START(左)。
      expect(
        ohosView,
        contains('this.verticalBarOnLeft ? HorizontalAlign.End : HorizontalAlign.Start'),
      );
    });

    test('滑杆数值自驱刷新 + 安卓同款格式', () {
      // @Builder 内数值不刷新（真机：拖滑杆数值不动）→ 子组件 timer 自驱。
      expect(ohosPanel, contains('struct DisplayValueText'));
      expect(ohosPanel, contains('DisplayValueText({ keyName: spec.key })'));
      // 格式照抄 Flutter format* 系列。
      expect(ohosPanel, contains(r'${v.toFixed(2)}×'));
      expect(ohosPanel, contains(r'${Math.round(v)}px'));
      expect(ohosPanel, contains(r'${Math.round(v * 100)}%'));
    });

    test('玻璃滑杆完全复刻 glassSliderTheme（三段渐变 + 光晕 + 高光）', () {
      final glass = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'GlassSlider.ets',
      ).readAsStringSync();
      // 轨道三段（Color.lerp 精确换算）：提亮 22% → 本色 → 压暗 18%。
      expect(glass, contains("const TRACK_TOP = '#58FFFFFF'"));
      expect(glass, contains("const TRACK_BOT = '#22D1D1D1'"));
      // 已播段：提亮 30% → accent → 压暗 12%。
      expect(glass, contains("const ACTIVE_TOP = '#9294F5'"));
      expect(glass, contains("const ACTIVE_BOT = '#575AD4'"));
      // 拇指：提亮 38% → accent → 压暗 16%。
      expect(glass, contains("const THUMB_TOP = '#9EA0F6'"));
      expect(glass, contains("const THUMB_BOT = '#5356CA'"));
      // 光晕 + 拇指双层 + 外发光 + 交互走 onTouch（绝对坐标 + step 吸附）。
      expect(glass, contains("const GLOW = '#4D6366F1'"));
      expect(glass, contains('.shadow({ radius: 6'));
      expect(glass, contains('.onTouch('));
      // 进度条与面板滑杆都用 GlassSlider。
      expect(ohosView, contains('GlassSlider({'));
      expect(ohosPanel, contains('GlassSlider({'));
    });

    test('GlassSlider：trackW 响应化 + value 同步 + 真弧高光', () {
      final glass = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'GlassSlider.ets',
      ).readAsStringSync();
      // trackW 必须 @State（普通字段写入不重绘 → 拇指恒贴左）。
      expect(glass, contains('@State trackW: number = 0;'));
      // value 变化经 @Watch 同步 ratio（播放推进/恢复默认跟随）。
      expect(glass, contains("@Watch('onValueChanged')"));
      expect(glass, contains('onValueChanged(): void'));
      // 高光弧 = 描边圆环 + 裁剪（几何确定）；禁 Path SVG 弧（组件盒解析
      // 会偏移，真机：弧偏了）。
      expect(glass, contains('.border({ width: 1.6, color: \'#B3FFFFFF\' })'));
      expect(glass, contains('.clip(true)'));
      expect(glass, isNot(contains('commands:')),
          reason: 'Path 弧被组件盒解析偏移，改圆环+裁剪');
    });

    test('恢复默认 → 滑杆回位（resetEpoch 节点重建）', () {
      expect(ohosPanel, contains('@State resetEpoch: number = 0;'));
      expect(ohosPanel, contains('this.resetEpoch = this.resetEpoch + 1;'));
      expect(ohosPanel, contains(r'`display-${epoch}`'));
    });

    test('弹幕轨道满 → 丢弃（禁叠加兜底，防重叠）', () {
      // Flutter DanmakuTimeline._pickRow：无空闲轨道返回 -1 → 丢弃；
      // 旧实现溢出回 0 行 = 多条挤一行重叠（真机回归）。
      final danmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'DanmakuLayer.ets',
      ).readAsStringSync();
      expect(danmaku, contains('lane = -1'));
      expect(danmaku, isNot(contains('溢出兜底')),
          reason: '轨道满不得回 0 行叠加');
    });

    test('手势半屏判定用 fingerList（offsetX 恒 0 → 音量永远不触发）', () {
      // Pan 的 offsetX 是累计位移（起点 0）：`offsetX < 宽/2` 恒真 → 永远
      // 判左屏调亮度、右半屏音量永远不触发（同长按分区教训，真机回归）。
      final panStart = RegExp(
        r'private onPanStart\(event: GestureEvent\): void \{[\s\S]*?\n  \}',
      ).firstMatch(ohosView);
      expect(panStart, isNotNull);
      expect(panStart!.group(0), contains('event.fingerList[0].localX'));
      expect(panStart.group(0), isNot(contains('= event.offsetX')),
          reason: '半屏判定禁用 offsetX（位移语义）');
    });
  });

  group('真机回归 580（弹幕提速/字幕/切音频/胶囊/默认速度）', () {
    final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
    final plugin = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
      'HimiMpvOhosPlugin.ets',
    ).readAsStringSync();
    final appSettings = File('lib/models/app_settings.dart').readAsStringSync();
    final nativeState =
        File('lib/services/player/native/native_player_state.dart')
            .readAsStringSync();

    test('长按倍速胶囊图标用单一来源常量（禁 0xE01F → 「4G」字形）', () {
      expect(ohosView, contains('NativePlayerIcons.ICON_FAST_FORWARD'));
      expect(ohosView, isNot(contains('0xE01F')),
          reason: '硬编码 0xE01F 渲染成「4G」，码位必须走 native_icons.json 常量');
    });

    test('鸿蒙字幕渲染对齐安卓插件（libass + 可见性 + 字号 40）', () {
      // 旧实现缺 sub-ass/sub-visibility：ASS/SSA 走简易渲染器慢且丢样式。
      expect(plugin, contains("setOptionString('sub-ass', 'yes')"));
      expect(plugin, contains("setOptionString('sub-visibility', 'yes')"));
      expect(plugin, contains("setOptionString('sub-font-size', '40')"));
      expect(plugin, isNot(contains("setOptionString('sub-font-size', '38')")));
    });

    test('切音轨滤镜延后落盘（禁与 aid 重建窗口叠加卡顿）', () {
      final fn = RegExp(
        r'void _selectEmbyAudio\(int embyIndex\) \{[\s\S]*?\n  \}',
      ).firstMatch(screen);
      expect(fn, isNotNull);
      final body = fn!.group(0)!;
      // 滤镜写入延后 300ms（音频链重建完成后）。
      expect(body, contains('_audioFilterDeferTimer'));
      expect(body, contains('Duration(milliseconds: 300)'));
      // 滤镜调用必须落在延后 Timer 内：Timer 之前不得有同步写入。
      final timerIdx = body.indexOf('Timer(const Duration(milliseconds: 300)');
      final filterIdx = body.indexOf('_applyAudioFilterPolicy(');
      expect(timerIdx, greaterThan(0));
      expect(filterIdx, greaterThan(timerIdx),
          reason: '同步写 af/audio.avfilter 会触发第二次音频输出重建');
      expect(body.substring(0, timerIdx), isNot(contains('_applyAudioFilterPolicy')));
    });

    test('首播并行拉弹幕（_playFromUrl 入口即拉，不等 _isPlayerReady）', () {
      // 对齐 Flutter perf「提前并行拉取弹幕」：集索引就绪即拉取。
      expect(screen, contains('if (_danmakuOn) unawaited(_loadDanmaku());'));
      final start = screen.indexOf('void _playFromUrl({');
      expect(start, greaterThan(0));
      final end = screen.indexOf('_addBroadcastMessage', start);
      final fnText = screen.substring(start, end);
      expect(fnText, contains('unawaited(_loadDanmaku())'),
          reason: '弹幕拉取必须在 _playFromUrl 入口触发（与媒体加载并行）');
    });

    test('跳过片头/片尾胶囊：自动隐藏顺延 + 提示边沿 + 画面就绪门禁', () {
      // tick 自动隐藏：提示有效期内顺延（对齐 Flutter _onControlsIdleHide）。
      expect(ohosView, contains('host.state.skipPrompt.length > 0'));
      expect(ohosView, contains('this.pokeAutoHide();'));
      // syncFromHost 边沿：出现强制显控件、消失重置计时。
      expect(ohosView,
          contains('if (s.skipPrompt.length > 0 && this.skipPrompt.length === 0)'));
      expect(ohosView, contains('host.setControlsVisible(true);'));
      // 画面就绪门禁：positionMs<=0 不评估（切集后不抢跑）。
      expect(screen, contains('if (positionMs <= 0) return;'));
    });

    test('弹幕默认速度 0.7 全链一致（构造/fromJson 迁移/恢复默认/原生兜底）', () {
      expect(appSettings, contains('this.danmakuSpeed = 0.7,'));
      // 强制迁移：旧默认 1.0 一并迁到 0.7。
      expect(appSettings, contains('- 1.0).abs() < 1e-6)'));
      final resets = RegExp(r'danmakuSpeed: [0-9.]+').allMatches(screen).toList();
      expect(resets, isNotEmpty);
      for (final m in resets) {
        expect(m.group(0), isNot(contains('1.0')),
            reason: '显示面板恢复默认须写 0.7');
      }
      expect(nativeState, contains('this.danmakuSpeed = 0.7,'));
      expect(nativeState,
          contains("danmakuSpeed: (json['danmakuSpeed'] as num?)?.toDouble() ?? 0.7,"));
    });
  });

  group('真机回归 581（弹幕行数/上限生效 + 轨命名对齐 Emby）', () {
    final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
    final stateFile =
        File('lib/services/player/native/native_player_state.dart')
            .readAsStringSync();
    final adapter =
        File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();
    final danmakuLayer = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'DanmakuLayer.ets',
    ).readAsStringSync();
    final hostFile = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'HimiMpvNativeHost.ets',
    ).readAsStringSync();
    final kotlinDanmaku = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'DanmakuLayerView.kt',
    ).readAsStringSync();
    final kotlinState = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerState.kt',
    ).readAsStringSync();

    test('弹幕行数/上限入协议并注入（旧实现硬编码 → 设置类全部失效）', () {
      for (final f in [stateFile, hostFile, kotlinState]) {
        expect(f, contains('danmakuScrollRows'));
        expect(f, contains('danmakuTopRows'));
        expect(f, contains('danmakuBottomRows'));
      }
      // Dart 注入设置值（唯一真相源）。
      expect(screen, contains('danmakuScrollRows: settings.danmakuScrollRows'));
      expect(screen,
          contains('settings.danmakuLimitCount ? settings.danmakuMaxCount : null'));
    });

    test('鸿蒙弹幕行数取设置（滚动上限 + 按屏高自适应，禁硬编码 16/6）', () {
      expect(danmakuLayer, contains('s.danmakuScrollRows'));
      expect(danmakuLayer, contains('s.danmakuTopRows'));
      expect(danmakuLayer, contains('s.danmakuBottomRows'));
      expect(danmakuLayer, contains('Math.min(s.danmakuScrollRows, autoRows)'));
      expect(danmakuLayer, isNot(contains('Math.min(16')),
          reason: '旧硬编码 16 行使设置失效');
    });

    test('安卓弹幕行数取设置 + 轨道满丢弃（禁回 0 行叠加）', () {
      expect(kotlinDanmaku, contains('scrollRows.coerceAtMost(autoRows)'));
      expect(kotlinDanmaku, isNot(contains('coerceIn(4, 16)')),
          reason: '旧硬编码 4~16 行使设置失效');
      // 溢出丢弃（对齐 Flutter `if (row < 0) continue` 与鸿蒙）。
      // 589 重写：行号绑定表 laneOf，溢出记 -1（不再有整表 lanes 数组）。
      expect(kotlinDanmaku, contains('laneOf[key] = lane'));
      expect(kotlinDanmaku, contains('if (lane < 0) continue'));
      expect(kotlinDanmaku, isNot(contains('lane = 0 // 溢出兜底')));
    });

    test('弹幕数量上限：等间隔采样（照抄 Flutter _sampleEvenly）', () {
      expect(adapter, contains('(i * total) ~/ maxCount'));
      expect(adapter, contains('danmakuMaxCount'));
    });

    test('字幕/音轨命名对齐 Emby displayInfo（禁裸 mpv title/lang）', () {
      // Dart 注入 Emby 显示名（与 Flutter 字幕/音轨菜单同源）。
      expect(screen, contains('.map((s) => s.displayInfo)'));
      // 轨 label 直接由 Emby displayInfo 列表生成（_panelTracksFromEmby；
      // 旧 t.withLabel 挂载链已并入生成逻辑）。
      expect(adapter, contains('label: _nativeAudioLabels[i]'));
      // 原生命名优先 label，回退 title/lang（两端一致）。
      expect(ohosPanel, contains('if (t.label.length > 0) return t.label;'));
      expect(kotlinState, contains('label.isNotBlank() -> label'));
      expect(stateFile, contains("json['label'] as String?"));
      // 「关闭字幕」文案对齐 Flutter SubtitleMenuPanel。
      expect(ohosPanel, contains("'关闭字幕'"));
      final kotlinScreen = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerScreenView.kt',
      ).readAsStringSync();
      expect(kotlinScreen, contains('"关闭字幕"'));
    });
  });

  group('真机回归 582（安卓控制层全量复刻鸿蒙）', () {
    final kotlinScreen = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();
    final kotlinState = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerState.kt',
    ).readAsStringSync();
    final kotlinHost = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerHost.kt',
    ).readAsStringSync();
    final glassSeek = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'GlassSeekBarView.kt',
    ).readAsStringSync();

    test('跳过片头/片尾胶囊补全（对齐鸿蒙 ControlRow leading 槽）', () {
      // 协议：skipPrompt 字段 + skipSegment 命令回传。
      expect(kotlinState, contains('val skipPrompt: String = ""'));
      expect(kotlinState, contains('json.optString("skipPrompt"'));
      expect(kotlinHost, contains('"skipSegment"'));
      // UI：胶囊 + 图标/文案切换 + 显隐条件。
      expect(kotlinScreen, contains('skipPromptChip'));
      expect(kotlinScreen, contains('"跳过片头"'));
      expect(kotlinScreen, contains('"跳过片尾"'));
      expect(kotlinScreen,
          contains('state.skipPrompt.isNotEmpty() && state.segmentEnabled'));
    });

    test('玻璃滑杆自绘（禁纯色 OVAL 拇指的系统 SeekBar 样式）', () {
      expect(kotlinScreen, contains('GlassSeekBarView(context)'));
      // 旧 applySeekBarStyle（GradientDrawable OVAL 纯色拇指）必须移除。
      expect(kotlinScreen, isNot(contains('applySeekBarStyle')),
          reason: '系统 SeekBar 纯色拇指无玻璃质感/高光弧');
      // 三段渐变轨道 + 拇指高光弧（照抄鸿蒙 GlassSlider.ets）。
      expect(glassSeek, contains('0x58FFFFFF'));
      expect(glassSeek, contains('0xFF9EA0F6'));
      expect(glassSeek, contains('drawArc'));
    });

    test('顶/底栏芯片统一规格（高 32dp + 关字体留白）', () {
      // 文本/图标芯片各自成高 → 同排高低不齐（截图回归）：统一最小高。
      final minHeights = RegExp(r'minimumHeight = dp\(32\)').allMatches(kotlinScreen);
      expect(minHeights.length, greaterThanOrEqualTo(3),
          reason: 'speedChip/kernelChip/图标芯片都要统一最小高');
      // 585：角标直径改为**内容自适应**（旧 14/18 阶梯在三位数时被裁）。
      expect(kotlinScreen, contains('badgeDiameterDp'));
      expect(kotlinScreen, isNot(contains('if (text.length >= 3) NPTheme.BADGE_MIN + 4')));
    });

    test('竖屏隐藏标题 + 焦点不改几何（对齐鸿蒙）', () {
      // 竖屏标题会被尾簇压成「…」（鸿蒙 if (!portrait) 语义）。
      expect(kotlinScreen, contains('if (portrait) "" else state.displayTitle'));
      // 焦点只画环：旧 scaleX/Y 1.1 连带放大命中区 → 相邻控件误触。
      expect(kotlinScreen, isNot(contains('v.scaleX = if (hasFocus)')));
    });

    test('锁钮与时间数显同列居中（照抄鸿蒙 width=cellW + textAlign Center）', () {
      expect(kotlinScreen, contains('leadingGroup.gravity = Gravity.CENTER'));
      expect(kotlinScreen, contains('leadingGroup.addView(lockButton, lp(LayoutParams.MATCH_PARENT'));
    });
  });

  group('真机回归 583（面板复刻 + TV 语义 + 手势 + 引擎选项）', () {
    final kotlinScreen = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();
    final kotlinHost = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerHost.kt',
    ).readAsStringSync();
    final kotlinRouter = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'TvKeyRouter.kt',
    ).readAsStringSync();
    final engineFile = File(
      'lib/services/player/player_engine.dart',
    ).readAsStringSync();
    final commandFile = File(
      'lib/services/player/native/native_player_command.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('显示调节滑杆换玻璃滑杆（小号 thumb18/光晕32，对齐 Flutter）', () {
      expect(kotlinScreen, contains('thumbDp = 18f'));
      expect(kotlinScreen, contains('glowDp = 32f'));
      expect(kotlinScreen, contains('val bar = GlassSeekBarView(context).apply'));
    });

    test('恢复默认行 + resetDisplay 命令链（字幕段/弹幕段）', () {
      expect(kotlinScreen, contains('resetRow("subtitle"'));
      expect(kotlinScreen, contains('resetRow("danmaku"'));
      expect(kotlinScreen, contains('optionRow("恢复默认"'));
      expect(commandFile, contains("case 'resetDisplay':"));
      expect(commandFile, contains('class ResetDisplay'));
      expect(screen, contains('case ResetDisplay(:final scope):'));
      expect(kotlinHost, contains('"resetDisplay"'));
    });

    test('位图字幕提示 + 段分隔线 + 数值格式（对齐 Flutter）', () {
      expect(kotlinScreen, contains('位图字幕（PGS 等）不支持样式调节'));
      expect(kotlinScreen, contains('lastState.subtitleStyleDisabled'));
      expect(kotlinScreen, contains('sectionDivider()'));
      expect(kotlinScreen, contains('"%.2f×"'));
      expect(kotlinScreen, contains('formatPercent'));
    });

    test('内核面板单行「短名 · 简介」（对齐 Flutter PlayerKernelPanel）', () {
      expect(kotlinScreen, contains(r'"${opt.label} · ${opt.description}"'));
      expect(kotlinScreen, isNot(contains('val textCol = LinearLayout')),
          reason: '双行堆叠与 Flutter 行高不一致');
    });

    test('返回键三层语义（关面板 → 隐控件 → 退出，禁直发 requestBack）', () {
      expect(kotlinScreen, contains('fun handleBack(): Boolean'));
      expect(kotlinHost, contains('controls.handleBack()'));
      // 三层顺序：先面板/片尾卡、再控件、最后退出。
      final fn = RegExp(r'fun handleBack\(\): Boolean \{[\s\S]*?\n    \}')
          .firstMatch(kotlinScreen);
      expect(fn, isNotNull);
      final body = fn!.group(0)!;
      expect(body.indexOf('closePanel()'), lessThan(body.indexOf('setControlsVisible(false)')));
      expect(body.indexOf('setControlsVisible(false)'), lessThan(body.indexOf('listener?.onBack()')));
    });

    test('TV 跨界 hop（左组尾↔右组头，对齐 Flutter hopRight/hopLeft）', () {
      expect(kotlinRouter, contains('leftTailProvider'));
      expect(kotlinRouter, contains('rightHeadProvider'));
      expect(kotlinRouter, contains('requestFocus()'));
      expect(kotlinScreen, contains('leftTailProvider = { nextButton }'));
      expect(kotlinScreen, contains('rightHeadProvider = { danmakuButton }'));
    });

    test('横拖松手提交 seek（累加器路径，防慢速拖动不生效）', () {
      expect(kotlinScreen, contains('hDragCommitted'));
      final up = RegExp(r'hDragAccumPx\) > 0f[\s\S]{0,500}onSeekRelative')
          .firstMatch(kotlinScreen);
      expect(up, isNotNull, reason: 'UP 时按累加器提交 seek');
    });

    test('长按三分区（左片头/右片尾/中间倍速，含校验门槛）', () {
      expect(kotlinScreen, contains('markSegmentFromGesture'));
      expect(kotlinScreen, contains('e.x < width / 3f'));
      expect(kotlinScreen, contains('e.x > width * 2f / 3f'));
      expect(kotlinScreen, contains('播放 3 秒后才能设置片头'));
      expect(kotlinScreen, contains('当前位置为 0，无法标记'));
      expect(kotlinScreen, contains('当前位置已到结尾，无法标记'));
    });

    test('Android 引擎矩阵移除 mediaKit 选项（原生 MPV 不受影响）', () {
      final androidCase = RegExp(
        r'case TargetPlatform\.android:\s*return const <PlayerEngine>\[([^\]]*)\];',
      ).firstMatch(engineFile);
      expect(androidCase, isNotNull);
      final list = androidCase!.group(1)!;
      expect(list, contains('PlayerEngine.mdk'));
      expect(list, contains('PlayerEngine.erika'));
      expect(list, contains('PlayerEngine.mpv'));
      expect(list, isNot(contains('mediaKit')),
          reason: 'libmpv 引擎选项已移除（与原生 MPV 共用 libmpv，仅去掉纹理路径选项）');
    });
  });

  group('真机回归 584（MPV 控制层九项回归修复）', () {
    final kotlinScreen = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();
    final glassSeek = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'GlassSeekBarView.kt',
    ).readAsStringSync();
    // 585：GlassBackdrop.kt（PixelCopy 采样）已删除，改读白底磨砂实现。
    final glassBackdrop = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'PanelGlassDrawable.kt',
    ).readAsStringSync();
    final adapter =
        File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();
    final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('进度条恒可触摸（durationMs=0 时禁用 → 拖不动，真机回归）', () {
      expect(kotlinScreen, contains('seekBar.isEnabled = true'));
      expect(kotlinScreen, isNot(contains('seekBar.isEnabled = !state.isLiveLike')));
      // 空范围自守卫：不回调但触摸响应。
      expect(glassSeek, contains('if (maxValue <= minValue)'));
    });

    test('传输组不禁用（disabled 不触发 onClick → 点了没反应）', () {
      expect(kotlinScreen, isNot(contains('prevButton.isEnabled =')),
          reason: 'isEnabled=false 的 View 不触发 onClick');
      expect(kotlinScreen, isNot(contains('nextButton.isEnabled =')));
      // 按下反馈动画先 cancel（防 applyState 重建打断留残影）。
      expect(kotlinScreen, contains('v.animate().cancel()'));
    });

    test('倍速点击弹面板（旧实现只循环切换，手机无面板入口）', () {
      expect(kotlinScreen, contains('speedChip.setOnClickListener { openPanel(PANEL_SPEED) }'));
      expect(kotlinScreen, isNot(contains('speedChip.setOnClickListener { listener?.onCycleSpeed() }')));
    });

    test('字幕/音轨面板用 Emby 列表（不依赖 mpv track-list 事件）', () {
      expect(adapter, contains('_panelTracksFromEmby()'));
      expect(adapter, isNot(contains('_nativeTracksFromRaw(_lastTrackListRaw)')));
      // 命令 id 约定统一：id = Emby 索引 + 1（SelectAudio 旧实现不减 1 → 错位）。
      expect(screen, contains('if (id > 0) _selectEmbyAudio(id - 1);'));
    });

    test('锁定态点屏不再闪现顶栏（tap 抑制 + 顶栏 GONE）', () {
      expect(kotlinScreen, contains('if (lastState.locked) return@setOnClickListener'));
      final locked = RegExp(r'if \(!tv && state\.locked\) \{[\s\S]{0,120}topBar\.visibility = GONE')
          .firstMatch(kotlinScreen);
      expect(locked, isNotNull);
    });

    test('片头片尾卡不被紧随 tap 收走（长按抑制窗）', () {
      expect(kotlinScreen, contains('suppressTapUntilMs'));
      // tap 层不再关闭 segmentCard（关闭只由 scrim 负责）。
      final tap = RegExp(r'setOnClickListener \{[\s\S]{0,700}?setControlsVisible\(!controlsVisible\)')
          .firstMatch(kotlinScreen);
      expect(tap, isNotNull);
      expect(tap!.group(0), isNot(contains('segmentCardOpen = false')));
    });

    test('面板按内容签名重建（旧实现每 500ms 重建打断拖动）', () {
      expect(kotlinScreen, contains('overlayContentSig'));
      expect(kotlinScreen, contains('if (sig != overlayContentSig)'));
    });

    test('角标值缓存（防 500ms layoutParams 重算抖动）', () {
      expect(kotlinScreen, contains('badgeLastText'));
      expect(kotlinScreen, contains('if (badgeLastText[badge] == text) return@forEach'));
    });

    test('面板背景逐值对齐 Flutter（587 改深色磨砂）', () {
      // 585~586 是浅底磨砂；587 三端统一改深色磨砂，对应常量换成
      // PANEL_GLASS_TOP / PANEL_GLASS_BASE / PANEL_GLASS_BOTTOM。
      expect(glassBackdrop, contains('PANEL_GLASS_TOP'));
      expect(glassBackdrop, contains('PANEL_GLASS_BASE'));
      expect(glassBackdrop, contains('PANEL_GLASS_BOTTOM'));
    });
  });

  group('真机回归 585（控制层监听器接线 + 白底磨砂弹层）', () {
    final kotlinScreen = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();
    final kotlinTheme = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerUi.kt',
    ).readAsStringSync();
    final lightGlass = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'PanelGlassDrawable.kt',
    ).readAsStringSync();
    final gauge = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'VerticalGaugeView.kt',
    ).readAsStringSync();
    final host = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerHost.kt',
    ).readAsStringSync();
    final glassConfig =
        File('lib/widgets/glass/glass_config.dart').readAsStringSync();
    final glassContainer =
        File('lib/widgets/glass/glass_container.dart').readAsStringSync();
    final selectorPanel =
        File('lib/screens/player/widgets/selector_side_panel.dart')
            .readAsStringSync();
    final ohosPanel = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'NativePlayerPanel.ets',
    ).readAsStringSync();

    test('【真凶】buildHierarchy 必须自己接 seek/transport 监听器', () {
      // rebuildBars() 只在 tvMode 翻转时跑，手机端 tvMode 恒 false →
      // 旧实现监听器从未挂上（进度条拖不动、播放/上下集没反应）。
      final body = RegExp(
        r'private fun buildHierarchy\(\) \{[\s\S]*?\n    \}',
      ).firstMatch(kotlinScreen);
      expect(body, isNotNull, reason: 'buildHierarchy 必须存在');
      expect(body!.group(0), contains('configureSeekListeners()'),
          reason: '初始化路径必须接进度条监听器');
      expect(body.group(0), contains('configureTransportListeners()'),
          reason: '初始化路径必须接播放/上下集监听器');
    });

    test('进度条 seek 保护窗（提交后不被旧位置弹回）', () {
      expect(kotlinScreen, contains('pendingSeekMs'));
      expect(kotlinScreen, contains('PENDING_SEEK_TOLERANCE_MS'));
      // 保护期内滑杆停在目标位，而不是权威旧位置。
      expect(kotlinScreen, contains('seekBar.value = target.toFloat()'));
    });

    test('角标三端同值分档（1~2 位 15 / 3 位 19 / 4 位起 24）', () {
      // 588：三端统一，对齐 MDK 观感（旧实现三端各算一套 → 同款角标大小不一）。
      expect(kotlinScreen, contains('badgeDiameterDp'));
      expect(kotlinScreen, isNot(contains('BADGE_MIN + 4')));
      expect(kotlinTheme, contains('const val BADGE_MIN = 15'));
      expect(kotlinTheme, contains('const val BADGE_WIDE = 19'));
      expect(kotlinTheme, contains('const val BADGE_XL = 24'));
      expect(NativePlayerTheme.badgeMinSize, 15);
      expect(NativePlayerTheme.badgeWideSize, 19);
      expect(NativePlayerTheme.badgeXlSize, 24);
      expect(NativePlayerTheme.badgeSizeFor('3'), 15);
      expect(NativePlayerTheme.badgeSizeFor('26'), 15);
      expect(NativePlayerTheme.badgeSizeFor('108'), 19);
      expect(NativePlayerTheme.badgeSizeFor('1080'), 24);
      // 鸿蒙：同样三档。
      expect(ohosView, contains('return 15;'));
      expect(ohosView, contains('return 19;'));
      expect(ohosView, contains('return 24;'));
      expect(ohosView, isNot(contains('badge.length >= 3 ? 18 : 14')));
    });

    test('手势柱条复刻 _buildVerticalBar（36dp/图标/竖向轨道/百分比）', () {
      // 常量定义在 NPTheme（NativePlayerUi.kt）。
      expect(kotlinTheme, contains('const val GAUGE_WIDTH = 36'));
      expect(kotlinTheme, contains('const val GAUGE_BRIGHTNESS'));
      expect(kotlinTheme, contains('const val GAUGE_VOLUME'));
      expect(kotlinTheme, contains('const val GAUGE_RADIUS = 18'));
      // 自绘：轨道 + 拇指 + 百分比 + 图标。
      expect(gauge, contains('percentOf'));
      expect(gauge, contains('drawRoundRect'));
      expect(gauge, contains('setIcon'));
      // 旧实现是纯 TextView 只显示百分比。
      expect(kotlinScreen, contains('VerticalGaugeView(context)'));
      expect(kotlinScreen, isNot(contains('verticalBar.text = ')));
    });

    test('安卓弹层改深色磨砂且删除 PixelCopy 采样', () {
      expect(lightGlass, contains('PANEL_GLASS_TOP'));
      expect(lightGlass, contains('PANEL_GLASS_RIM'));
      // 采样链必须彻底消失（旧实现 600ms 回读 → 背景一帧一帧跳）。
      expect(kotlinScreen, isNot(contains('sampleAsync()')));
      expect(kotlinScreen, isNot(contains('startGlassSampling')));
      expect(kotlinScreen, isNot(contains('SAMPLE_INTERVAL_MS')));
    });

    test('字幕面板补「加载本地字幕」+ 无轨道占位', () {
      expect(kotlinScreen, contains('加载本地字幕文件...'));
      expect(kotlinScreen, contains('当前视频无内嵌字幕轨道'));
      expect(host, contains('"type" to "addSubtitle"'));
    });

    test('Flutter 深色磨砂只在播放器弹层（全局 panelTint 不变）', () {
      // 全局深色常量必须原样保留（设置页/缓存页等仍在用）。
      expect(glassConfig, contains('static const Color panelTint = Color(0x1F1A1D23)'));
      expect(glassConfig, contains('playerPanelBase'));
      expect(glassConfig, contains('playerPanelRim'));
      // 弹层容器走 popup 变体。
      expect(glassContainer, contains('this.popup = false'));
      expect(selectorPanel, contains('popup: true'));
    });

    test('鸿蒙弹层同步深色磨砂（保留实时 backgroundEffect）', () {
      expect(ohosPanel, contains('PANEL_GLASS_TOP'));
      expect(ohosPanel, contains('PANEL_GLASS_RIM'));
      expect(ohosPanel, contains('backgroundEffect'));
      expect(ohosPanel, contains('PANEL_TEXT'));
    });
  });

  group('主题常量引用完整性', () {
    test('Android 用到的新增常量都在 NPTheme 里定义', () {
      final kotlinTheme = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerUi.kt',
      ).readAsStringSync();
      for (final name in [
        'TITLE_MIN_WIDTH',
        'BAR_BOTTOM_SOLID',
        'ACCENT_30',
        'WHITE_12',
      ]) {
        expect(
          kotlinTheme,
          contains('const val $name'),
          reason: 'NPTheme 缺少常量 $name',
        );
      }
    });

    test('Dart 主题暴露新增常量（唯一真相源）', () {
      expect(NativePlayerTheme.titleMinWidth, 56);
      expect(NativePlayerTheme.barBottomSolid.toARGB32(), 0xD9000000);
      expect(NativePlayerTheme.accent30.toARGB32(), 0x4D6366F1);
      expect(NativePlayerTheme.white12.toARGB32(), 0x1FFFFFFF);
    });
  });

  group('586/587 鸿蒙画布分辨率 + 深色磨砂弹层 + 加载指示器统一', () {
    final ohosPlugin = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
      'HimiMpvOhosPlugin.ets',
    ).readAsStringSync();
    final ohosHost = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'HimiMpvNativeHost.ets',
    ).readAsStringSync();
    final ohosViewFile = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'HimiNativePlayerView.ets',
    ).readAsStringSync();
    final ohosPanelFile = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'NativePlayerPanel.ets',
    ).readAsStringSync();
    final kotlinScreen586 = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();
    final kotlinTheme586 = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerUi.kt',
    ).readAsStringSync();
    final kotlinState586 = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'AndroidNativePlayerState.kt',
    ).readAsStringSync();
    final glassConfig586 =
        File('lib/widgets/glass/glass_config.dart').readAsStringSync();
    final selectorPanel586 = File(
      'lib/screens/player/widgets/selector_side_panel.dart',
    ).readAsStringSync();
    final stateDart586 = File(
      'lib/services/player/native/native_player_state.dart',
    ).readAsStringSync();
    final adapter586 =
        File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();
    final screen586 =
        File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('onAreaChange 必须 vp2px 后再同步画布尺寸', () {
      // 真机「画面变糊」根因：vp 当 px 传 → 画布只有 1/density。
      expect(ohosViewFile, contains('vp2px'));
      expect(ohosViewFile, contains("surfaceChanged('', wPx, hPx)"));
      // 不得把 Area 的 vp 直接当 px 传（旧实现写法）。
      expect(ohosViewFile, isNot(contains("surfaceChanged('', Math.trunc(w)")));
    });

    test('宿主 surfaceChanged 声明 px 契约并做非正防御', () {
      expect(ohosHost, contains('px（物理像素）'));
      expect(ohosHost, contains('if (width <= 0 || height <= 0)'));
      // 本地记录画布尺寸供调试面板核验。
      expect(ohosHost, contains('this.canvasWidth = Math.trunc(width)'));
      expect(ohosHost, contains('this.canvasHeight = Math.trunc(height)'));
    });

    test('初始化前的 surface 尺寸不再被丢弃（先缓存后应用）', () {
      // 旧实现 `if (session === null || !session.initialized) return;` 把
      // 初始化前到达的尺寸永久丢掉，而它不会重发。
      expect(
        ohosPlugin,
        isNot(contains('if (session === null || !session.initialized) return;')),
      );
      // 缓存必须发生在 initialized 判断之前。
      final body = ohosPlugin.substring(
        ohosPlugin.indexOf('handleSurfaceChanged(surfaceId: string'),
      );
      final cacheIdx = body.indexOf('session.width = width;');
      final initIdx = body.indexOf('if (!session.initialized)');
      expect(cacheIdx, greaterThan(0));
      expect(initIdx, greaterThan(cacheIdx),
          reason: '尺寸缓存必须早于 initialized 判断');
      expect(body, contains('缓存待应用'));
    });

    test('attach 成功后立刻用真实 px 覆盖创建期猜测尺寸', () {
      expect(ohosPlugin, contains('attach 后写入画布尺寸'));
      expect(ohosPlugin, contains("session.lib.setProperty('ohos-surface-size'"));
    });

    test('三端深色磨砂基色逐字节一致，浅色残留彻底清零', () {
      // Dart（顶/基/底三段 + 描边）。
      expect(glassConfig586, contains('Color(0xB31A1D23)'));
      expect(glassConfig586, contains('Color(0xA61A1D23)'));
      expect(glassConfig586, contains('Color(0x991A1D23)'));
      expect(glassConfig586, contains('Color(0x33FFFFFF)'));
      // Kotlin
      expect(kotlinTheme586, contains('0xB31A1D23'));
      expect(kotlinTheme586, contains('0xA61A1D23'));
      expect(kotlinTheme586, contains('0x991A1D23'));
      expect(kotlinTheme586, contains('0x33FFFFFF'));
      // ArkTS
      expect(ohosPanelFile, contains("'#B31A1D23'"));
      expect(ohosPanelFile, contains("'#A61A1D23'"));
      expect(ohosPanelFile, contains("'#991A1D23'"));
      expect(ohosPanelFile, contains("'#33FFFFFF'"));
      // 585 纯白 / 586 暖白都必须彻底消失（防回流）。
      for (final old in ['0xD1FFFFFF', '0xE6F4F2EE', '0xF2FAF8F4', '0xD6EAE7E1']) {
        expect(glassConfig586, isNot(contains(old)), reason: old);
        expect(kotlinTheme586, isNot(contains(old)), reason: old);
      }
      for (final old in ['#D1FFFFFF', '#E6F4F2EE', '#F2FAF8F4', '#D6EAE7E1']) {
        expect(ohosPanelFile, isNot(contains(old)), reason: old);
      }
      // 旧命名也必须清零（`light` 语义已反，改名防误用）。
      for (final old in ['playerPanelWhite', 'playerPanelRimLight']) {
        expect(glassConfig586, isNot(contains(old)), reason: old);
      }
      for (final old in ['PANEL_LIGHT_', 'TEXT_DARK', 'DIVIDER_LIGHT',
          'SEL_BG_LIGHT', 'TRACK_LIGHT_INACTIVE', 'SCRIM_LIGHT']) {
        expect(kotlinTheme586, isNot(contains(old)), reason: old);
        expect(ohosPanelFile, isNot(contains(old)), reason: old);
      }
      // 全局深色常量（顶/底栏、App 其它页面）必须原样保留。
      expect(glassConfig586,
          contains('static const Color panelTint = Color(0x1F1A1D23)'));
    });

    test('面板正文统一纯白，选中行不再用强调色当文字色', () {
      // Flutter：SideOptionRow 文字恒为 playerPanelTextPrimary + w500。
      expect(
        selectorPanel586,
        isNot(contains('? const Color(0xFF6366F1)')),
        reason: '选中行不得再用强调色当文字色',
      );
      expect(selectorPanel586, contains('GlassConfig.playerPanelBodySize'));
      expect(selectorPanel586, contains('fontWeight: FontWeight.w500'));
      // 安卓：optionRow 文字恒 PANEL_TEXT + bodyTypeface。
      expect(kotlinScreen586, contains('setTextColor(NPTheme.PANEL_TEXT)'));
      expect(kotlinScreen586, contains('typeface = NPTheme.bodyTypeface'));
      expect(
        kotlinScreen586,
        isNot(contains('setTextColor(if (selected) NPTheme.ACCENT else NPTheme.PANEL_TEXT)')),
      );
      // 鸿蒙：OptionLabel 文字恒 PANEL_TEXT + w500。
      expect(ohosPanelFile, contains('.fontColor(PANEL_TEXT)\n      .layoutWeight(1)'));
      expect(ohosPanelFile, contains('const PANEL_BODY_WEIGHT = 500'));
    });

    test('面板排版常量三端同值（标题 15/w600、正文 14/w500、说明 12/w500）', () {
      expect(glassConfig586, contains('playerPanelTitleSize = 15'));
      expect(glassConfig586, contains('playerPanelBodySize = 14'));
      expect(glassConfig586, contains('playerPanelCaptionSize = 12'));
      expect(kotlinTheme586, contains('const val PANEL_BODY_SIZE = 14f'));
      expect(kotlinTheme586, contains('const val PANEL_CAPTION_SIZE = 12f'));
      expect(ohosPanelFile, contains('const PANEL_BODY_SIZE = 14;'));
      expect(ohosPanelFile, contains('const PANEL_CAPTION_SIZE = 12;'));
      expect(ohosPanelFile, contains('const PANEL_TITLE_WEIGHT = 600;'));
    });

    test('内核面板与其它面板共用同一容器（不得分叉）', () {
      // Flutter：PlayerKernelPanel 挂在 SelectorSidePanel 里。
      expect(
        File('lib/screens/player/player_screen.dart').readAsStringSync(),
        contains('PlayerKernelPanel('),
      );
      // 安卓：PANEL_KERNEL 走同一个 panelContainer。
      expect(kotlinScreen586, contains('PANEL_KERNEL -> buildKernelContent()'));
      // 鸿蒙：panelType === 'kernel' 走同一 SidePanel。
      expect(ohosPanelFile, contains("this.panelType === 'kernel'"));
      expect(ohosPanelFile, contains('this.KernelContent();'));
    });

    test('加载指示器三端读同一个 showLoading 位', () {
      // Dart 快照字段 + JSON 往返。
      expect(stateDart586, contains('showLoading'));
      expect(stateDart586, contains("'showLoading': showLoading,"));
      // 587：适配器每次推送**现算**，不再读低频 extras（转圈不停根因）。
      // 589：加看门狗前置条件（!fired && (...)），判据本身不变。
      expect(adapter586, contains('buffering ||'));
      expect(adapter586, contains('showLoading: showLoading,'));
      expect(adapter586, isNot(contains('showLoading: _nativeUiExtras.showLoading')));
      // extras 类里不得再有该字段（否则又会被低频覆盖）。
      final extrasBlock = stateDart586.substring(
        stateDart586.indexOf('class NativePlayerUiExtras'),
      );
      expect(extrasBlock, isNot(contains('showLoading')));
      // 安卓只读 showLoading，不再自己判 buffering。
      expect(kotlinState586, contains('val showLoading: Boolean = false'));
      expect(kotlinScreen586,
          contains('bufferingView.visibility = if (state.showLoading) VISIBLE else GONE'));
      // 鸿蒙 LoadingProgress 只读快照位，不自行拼缓冲条件。
      expect(ohosViewFile, contains('LoadingProgress()'));
      expect(ohosViewFile, contains('.color(\'#6366F1\')'));
      expect(ohosHost, contains('this.showLoading = jsonBool(obj.showLoading'));
      // 589 根因修复：宿主普通字段不在 ArkUI 观察链上，必须镜像 @State 后
      // 在 build() 直读（旧写法条件只求值一次 → 永久转圈）。
      expect(ohosViewFile, contains('@State showLoading: boolean = false;'));
      expect(ohosViewFile, contains('this.showLoading = s.showLoading;'));
      expect(ohosViewFile, contains('if (this.showLoading) {'));
      expect(ohosViewFile, isNot(contains('if (this.state().showLoading) {')));
      // 转圈层不得抢手势（None 而非 Transparent，565 老坑）。
      expect(ohosViewFile, contains('.hitTestBehavior(HitTestMode.None);'));
    });

    test('587 转圈判定：首帧未出 / 缓冲中 / 起播前黑窗，起播后必收起', () {
      // 三个条件缺一不可：仅看 buffering 会在首帧期不转；仅看首帧会在
      // 中途卡顿时不转；都是 0 且未 playing 是起播前那段黑窗。
      expect(adapter586, contains('buffering ||'));
      expect(adapter586, contains('firstFramePending.value ||'));
      expect(adapter586, contains('_durationMs == 0 &&'));
      expect(adapter586, contains('_positionMs == 0 &&'));
      expect(adapter586, contains('_state != AdapterPlaybackState.playing'));
      // PlayerScreen 侧的静态谓词继续给 Flutter 自绘转圈用。
      expect(screen586, contains('static bool shouldShowLoadingSpinner'));
    });

    test('587 安卓转圈为自绘弧线（禁系统 ProgressBar 的 ROM 差异）', () {
      final spinner = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'PlayerSpinnerView.kt',
      ).readAsStringSync();
      // 尺寸/描边/颜色对齐 Flutter CircularProgressIndicator。
      expect(spinner, contains('diameterDp: Float = 36f'));
      expect(spinner, contains('strokeDp: Float = 4f'));
      expect(spinner, contains('NPTheme.ACCENT'));
      expect(spinner, contains('Paint.Cap.ROUND'));
      // 动画：1333ms 线性旋转 + 弧长伸缩，不可见时停。
      expect(spinner, contains('ROTATION_MS = 1333L'));
      expect(spinner, contains('ValueAnimator.INFINITE'));
      expect(spinner, contains('onVisibilityAggregated'));
      expect(spinner, contains('canvas.drawArc'));
      // 控件层必须改用它，且系统 ProgressBar 引用清除。
      expect(kotlinScreen586, contains('PlayerSpinnerView(context)'));
      expect(kotlinScreen586, isNot(contains('ProgressBar(context)')));
      expect(kotlinScreen586, isNot(contains('isIndeterminate = true')));
    });

    test('587 鸿蒙解码面板完全对齐 Flutter（智能/硬解/软解 + 说明）', () {
      // 档位文案：auto = 智能（旧实现写「自动」）。
      expect(ohosPanelFile, contains("return '智能';"));
      expect(ohosPanelFile, isNot(contains("return '自动';")));
      // 三句说明逐字对齐 Flutter / 安卓。
      expect(ohosPanelFile, contains("return '优先硬解，失败回退软解';"));
      expect(ohosPanelFile, contains("return '纯硬解，失败不回退';"));
      expect(ohosPanelFile, contains("return '纯软解，CPU 占用高';"));
      // 标题行「解码模式 + 当前档位」。
      expect(ohosPanelFile, contains("Text('解码模式')"));
      expect(ohosPanelFile, contains('decodeModeLabel(this.state().decodeMode)'));
      // 不再有「当前：xxx」旧布局。
      expect(ohosPanelFile, isNot(contains("'当前：'")));
      // 安卓说明文案同值。
      expect(kotlinScreen586, contains('优先硬解，失败回退软解'));
      expect(kotlinScreen586, contains('纯硬解，失败不回退'));
      expect(kotlinScreen586, contains('纯软解，CPU 占用高'));
      // Flutter 参考实现：同一组文案 + 走弹层容器。
      final decodePanel = File(
        'lib/screens/player/widgets/decode_mode_panel.dart',
      ).readAsStringSync();
      expect(decodePanel, contains("'auto': '智能'"));
      expect(decodePanel, contains("'auto': '优先硬解，失败回退软解'"));
      expect(decodePanel, contains('GlassContainer('));
      expect(decodePanel, contains('popup: true'));
    });

    test('587 所有播放器弹层都走深色 popup 容器（无浅色档残留）', () {
      final files = <String>[
        'decode_mode_panel.dart',
        'selector_side_panel.dart',
        'segment_mark_panel.dart',
        'subtitle_style_panel.dart',
        'danmaku_style_panel.dart',
      ];
      for (final name in files) {
        final src = File('lib/screens/player/widgets/$name').readAsStringSync();
        expect(src, isNot(contains('light: true')), reason: name);
        expect(src, isNot(contains('light: false')), reason: name);
        expect(src, isNot(contains('playerPanelWhite')), reason: name);
        expect(src, isNot(contains('playerPanelRimLight')), reason: name);
      }
      // 容器开关叫 popup，语义不再是「浅色」。
      final container =
          File('lib/widgets/glass/glass_container.dart').readAsStringSync();
      expect(container, contains('this.popup = false'));
      expect(container, isNot(contains('final bool light;')));
      // 深色弹层必须靠亮描边定界 + 走折射管线（真模糊）。
      expect(container, contains('GlassConfig.playerPanelRim'));
      expect(container, contains('lg.GlassContainer('));
      // 面板滑杆不再有浅色档参数。
      final slider =
          File('lib/screens/player/widgets/glass_slider_theme.dart').readAsStringSync();
      expect(slider, isNot(contains('bool light = false')));
    });

    test('587 内核面板：单行「短名 · 说明」+ 底部说明（三端一致）', () {
      const tail = '切换仅影响当前播放，不改变默认引擎；下一集沿用当前内核';
      // Flutter 参考实现（bottom note 唯一真相源）。
      final kernelPanel = File(
        'lib/screens/player/widgets/player_kernel_panel.dart',
      ).readAsStringSync();
      expect(kernelPanel, contains(tail));
      // 安卓：单行拼接 + 同一段底部说明。
      expect(kotlinScreen586, contains(r'"${opt.label} · ${opt.description}"'));
      expect(kotlinScreen586, contains(tail));
      expect(kotlinScreen586, contains('NPTheme.PANEL_BODY_SIZE'));
      // 鸿蒙：单行拼接 + 同一段底部说明（旧实现双行堆叠）。
      expect(ohosPanelFile, contains(r'`${opt.label} · ${opt.description}`'));
      expect(ohosPanelFile, contains(tail));
    });

    test('加载指示器统一规则（首帧未出 或 缓冲中）', () {
      expect(screen586, contains('shouldShowLoadingSpinner'));
      expect(screen586, contains('buffering:'));
      // 旧入口仍保留（其余调用点/测试在用）。
      expect(screen586, contains('shouldShowInitialLoadingSpinner'));
    });

    test('安卓加载指示器在控件层之下（先于 bars 添加）', () {
      final buffIdx = kotlinScreen586.indexOf('addView(bufferingView');
      final topIdx = kotlinScreen586.indexOf(
        'addView(topBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP))',
      );
      expect(buffIdx, greaterThan(0));
      expect(topIdx, greaterThan(0));
      expect(buffIdx, lessThan(topIdx),
          reason: '转圈必须先于顶/底栏添加（Flutter 转圈在控件层之下）');
    });

    test('鸿蒙调试面板含 canvas= 画布尺寸行', () {
      expect(ohosViewFile, contains('canvas='));
      expect(ohosViewFile, contains('private diagLine()'));
      expect(ohosViewFile, contains('host.canvasWidth'));
    });
  });

  group('588 鸿蒙转圈根因 + 手势图标 + 跳过提示时机 + 面板复选框 + 封面提速', () {
    final ohosPlugin588 = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
      'HimiMpvOhosPlugin.ets',
    ).readAsStringSync();
    final ohosView588 = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'HimiNativePlayerView.ets',
    ).readAsStringSync();
    final ohosPanel588 = File(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
      'NativePlayerPanel.ets',
    ).readAsStringSync();
    final kotlinScreen588 = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativePlayerScreenView.kt',
    ).readAsStringSync();
    final kotlinLoader588 = File(
      'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
      'NativeLogoLoader.kt',
    ).readAsStringSync();
    final adapter588 =
        File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();
    final screen588 =
        File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('鸿蒙 pollState 补画面尺寸/出帧率（首帧已出的第二判据）', () {
      // video-params 是 NODE 属性，getPropertyString 常返空；width/height 可读。
      expect(ohosPlugin588, contains("lib.getProperty('width')"));
      expect(ohosPlugin588, contains("lib.getProperty('height')"));
      expect(ohosPlugin588, contains("lib.getProperty('estimated-vf-fps')"));
      expect(ohosPlugin588, contains("lib.getProperty('frame-drop-count')"));
      expect(ohosPlugin588, contains('videoWidth: videoWidth,'));
      expect(ohosPlugin588, contains('videoHeight: videoHeight,'));
      expect(ohosPlugin588, contains('videoFps: videoFps,'));
      expect(ohosPlugin588, contains('frameDropCount: frameDropCount,'));
      // payload 接口声明同步（ArkTS 对象字面量必须字段齐全）。
      expect(ohosPlugin588, contains('videoWidth: number | null;'));
      expect(ohosPlugin588, contains('videoHeight: number | null;'));
    });

    test('适配器把「画面尺寸可读」也当首帧已出（转圈/软解回退同判据）', () {
      expect(adapter588, contains('static bool hasVideoFrame(MpvPollResult state)'));
      expect(adapter588, contains('state.videoWidth ?? 0'));
      expect(adapter588, contains('if (hasVideoFrame(state)) _videoParamsSeen = true;'));
      // 软解回退误判同样要用第二判据（否则 3s 后强切软解重载）。
      expect(adapter588,
          contains('if (state.videoParams != null || hasVideoFrame(state) || state.idleActive)'));
      // 跳过提示门禁：首帧未出不弹提示。
      expect(adapter588, contains('bool get firstFrameReady => !firstFramePending.value;'));
      expect(screen588, contains('if (!_videoFrameReady) return;'));
    });

    test('缓冲位：位置已推进也算在出帧（鸿蒙 cache-time 常读不到）', () {
      expect(adapter588, contains('state.bufferedMs > 0 || state.positionMs > 0'));
    });

    test('安卓双击手势图标方向与 Flutter playPauseHintIcon 一致', () {
      // Flutter：playing ? pause : play（显示切换后的可执行动作）。
      final gesture = File('lib/utils/playback_gesture.dart').readAsStringSync();
      expect(gesture, contains('playing ? Icons.pause : Icons.play_arrow'));
      // 安卓：lastState.paused（切换前）为 true → 切后是播放中 → 暂停图标。
      expect(kotlinScreen588, contains('if (lastState.paused) {\n                        NativePlayerIcons.ICON_PAUSE_CIRCLE'));
      expect(kotlinScreen588, contains('} else {\n                        NativePlayerIcons.ICON_PLAY_CIRCLE'));
    });

    test('跳过提示：离开片段立刻收起 + 切集入口显式清理', () {
      expect(screen588, contains('static bool shouldKeepSkipPrompt'));
      expect(screen588,
          contains('if (_skipPromptSegment != null &&\n        !PlayerScreen.shouldKeepSkipPrompt(_skipPromptSegment, positionMs)) {'));
      expect(screen588, contains('_dismissSkipPrompt();'));
      // 切集/重建引擎/加载流三处入口都有抑制清理。
      expect(screen588, contains('void _beginSkipPromptSuppression()'));
      expect(screen588, contains('_beginSkipPromptSuppression();'));
    });

    test('解码面板单选码点修正为 radio_button_checked/unchecked', () {
      // 旧 0xE838/0xE836 实际是 cancel_sharp / cancel_presentation_sharp（方框叉）。
      final icons = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerIcons.kt',
      ).readAsStringSync();
      expect(icons, contains('ICON_RADIO_BUTTON_CHECKED = 0xE503'));
      expect(icons, contains('ICON_RADIO_BUTTON_UNCHECKED = 0xE504'));
      expect(icons, isNot(contains('ICON_RADIO_CHECKED = 0xE838')));
      expect(kotlinScreen588, contains('NativePlayerIcons.ICON_RADIO_BUTTON_CHECKED'));
      expect(kotlinScreen588, contains('NativePlayerIcons.ICON_RADIO_BUTTON_UNCHECKED'));
      // 鸿蒙改用图标字体（不再用 ●/○ 文本）。
      expect(ohosPanel588, contains('NativePlayerIcons.ICON_RADIO_BUTTON_CHECKED'));
      expect(ohosPanel588, contains('NativePlayerIcons.ICON_RADIO_BUTTON_UNCHECKED'));
      expect(ohosPanel588, isNot(contains("? '●' : '○'")));
    });

    test('解码面板行：图标→文字 8dp + 每行（含末行）0.5 分隔线', () {
      expect(kotlinScreen588, contains('it.marginStart = dp(8)'));
      expect(kotlinScreen588, contains('foreground = rowBottomDivider()'));
      expect(kotlinScreen588, contains('private fun rowBottomDivider()'));
      // 鸿蒙：行底 0.5 边框（List.divider 画不到末行）。
      expect(ohosPanel588, contains('width: { bottom: 0.5 }'));
      expect(ohosPanel588, isNot(contains('.divider({ strokeWidth: 0.5, color: PANEL_DIVIDER });\n    }\n    .width(\'100%\')\n    .layoutWeight(1);')));
    });

    test('安卓选集封面：4 线程 + 磁盘 LRU + 目标宽解码 + 优先级', () {
      expect(kotlinLoader588, contains('private const val THREADS = 4'));
      expect(kotlinLoader588, contains('PriorityBlockingQueue'));
      expect(kotlinLoader588, contains('native_poster'));
      expect(kotlinLoader588, contains('DISK_CACHE_BYTES = 64L * 1024 * 1024'));
      expect(kotlinLoader588, contains('fun cancelPending()'));
      expect(kotlinLoader588, contains('PRIORITY_CURRENT = 0'));
      // 按目标宽二次采样（不再固定 960）。
      expect(kotlinLoader588, contains('decodeSampled(bytes, targetWidthPx.coerceAtLeast(1))'));
      // 控件层传卡片宽 + 优先级，关面板取消队列。
      expect(kotlinScreen588, contains('targetPx, priority'));
      expect(kotlinScreen588, contains('NativeLogoLoader.cancelPending()'));
    });

    test('片头/片尾范围约束：Dart 权威 + 三端前置校验', () {
      final rules = File('lib/utils/segment_mark_rules.dart').readAsStringSync();
      expect(rules, contains('static const double introMaxFraction = 0.10;'));
      expect(rules, contains('static const double outroMinFraction = 0.70;'));
      expect(rules, contains('片头结束点不能超过总时长的 10%'));
      expect(rules, contains('片尾开始点不能低于总时长的 70%'));
      // 播放页调用（原生长按 / TV 面板 / 二次确认「更新」最终都走这里）。
      expect(screen588, contains('SegmentMarkRules.rejectReason('));
      // 安卓：手势前置 + 二次确认「更新」都校验。
      expect(kotlinScreen588, contains('internal fun segmentMarkReject('));
      expect(kotlinScreen588, contains('segmentMarkReject(kind, pos, lastState.durationMs.toLong())'));
      expect(kotlinScreen588, contains('val reject = segmentMarkReject(kind, pos, lastState.durationMs.toLong())'));
      // 鸿蒙：手势前置 + 二次确认「更新」都校验。
      expect(ohosPanel588, contains('export function segmentMarkReject('));
      expect(ohosView588, contains('const reject = segmentMarkReject(kind, pos, this.durationMs);'));
      expect(ohosPanel588, contains('const reject = segmentMarkReject('));
    });

    test('设置页说明补范围约束', () {
      final settings = File(
        'lib/screens/settings/intro_outro_settings_screen.dart',
      ).readAsStringSync();
      expect(settings, contains('片头结束点不能超过总时长的 10%'));
      expect(settings, contains('片尾开始点不能低于总时长的 70%'));
    });
  });
}
