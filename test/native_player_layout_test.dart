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

  final kotlinGlass = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'GlassBackdrop.kt',
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
    test('Android 用正圆 Drawable + 正方形边长', () {
      expect(kotlinScreen, contains('BadgeCircleDrawable'));
      // 必须是正方形（宽==高），否则 OVAL 会画成椭圆。
      expect(kotlinScreen, matches(RegExp(r'LayoutParams\(dp\(sideDp\), dp\(sideDp\)')),
          reason: '角标必须是正方形边长（正圆底）');
      // 旧的手算宽度方案必须移除。
      expect(kotlinScreen, isNot(contains('14 + text.orEmpty().length * 5')),
          reason: '旧的 14+len*5 手算宽度会画成椭圆');
    });

    test('Android 关闭整条父链裁切（角标伸出命中框不被切）', () {
      expect(kotlinScreen, contains('clipChildren = false'));
      expect(kotlinScreen, contains('clipToPadding = false'));
    });

    test('鸿蒙角标同样定宽定高（不靠 constraintSize 最小值）', () {
      expect(ohosView, contains('badgeSide'));
      expect(ohosView, contains('.borderRadius(this.badgeSide(badge) / 2)'));
    });
  });

  group('玻璃面板源矩形映射（不显示整段缩小视频）', () {
    test('Android 把面板屏幕矩形映射到位图源矩形', () {
      expect(kotlinGlass, contains('mapPanelToSource'));
      expect(kotlinGlass, contains('setPanelScreenRect'));
      // 旧实现整帧铺满：drawBitmap(bmp, null, rect) 必须消失。
      expect(kotlinGlass, isNot(contains('drawBitmap(bmp, null, rect, paint)')),
          reason: '整帧铺满会让面板显示「缩小版全视频」');
      expect(kotlinGlass, contains('drawBitmap(bmp, src, rect, paint)'));
    });

    test('宿主喂入面板屏幕矩形与 surface 尺寸', () {
      expect(kotlinScreen, contains('feedGlassRects'));
      expect(kotlinScreen, contains('pushScreenRect'));
      expect(kotlinScreen, contains('getLocationOnScreen'));
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

    test('鸿蒙同值 0x29', () {
      expect(ohosView, contains("trackColor('#29FFFFFF')"));
      expect(ohosPanel, contains("trackColor('#29FFFFFF')"));
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

    test('Android 同值', () {
      expect(kotlinScreen, contains('ColorStateList.valueOf(NPTheme.ACCENT)'));
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
      expect(ohosView, contains('hitTestBehavior(HitTestMode.Default)'));
      expect(
        ohosView,
        isNot(contains('hitTestBehavior(HitTestMode.Transparent)')),
        reason: '全屏手势层不能用 Transparent（会与控件抢占触摸）',
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
        r'LockOnlyBar\(\) \{[\s\S]{0,1400}?angle: (\d+)',
      ).firstMatch(ohosView);
      expect(lockBar, isNotNull, reason: '找不到 LockOnlyBar 的渐变配置');
      expect(lockBar!.group(1), '180', reason: '锁定态底栏渐变必须自上而下');
    });

    test('locked 是 @State（宿主字段不在观察链上，需显式同步）', () {
      expect(ohosView, contains('@State locked: boolean = false'));
      // 必须在状态回调与初始时同步。
      expect(ohosView, contains('this.locked = host.state.locked'));
      // build/锁定态读 @State 而非宿主字段。
      expect(ohosView, contains('if (this.locked && !this.state().tvMode)'));
    });

    test('竖屏等比缩小（旧的收窄间距方案已移除）', () {
      expect(ohosView, contains('@State bottomScale: number = 1'));
      expect(ohosView, contains('private adjustBottomScale'));
      // 用 transform 的 centerX/centerY 把缩放锚在右缘（本 SDK 无
      // transformOrigin 属性）。
      expect(ohosView, contains('scaleX: this.bottomScale'));
      expect(ohosView, contains("centerX: '100%'"));
      expect(ohosView, contains("centerY: '50%'"));
      // 旧方案必须移除（gap 归零仍溢出 32dp）。
      expect(ohosView, isNot(contains('private adjustBottomGap')));
      expect(ohosView, isNot(contains('this.bottomGap')));
    });

    test('竖屏隐藏顶栏标题（Logo 保留）', () {
      expect(ohosView, contains('@State portrait: boolean = false'));
      expect(ohosView, contains('this.portrait = h > w && w > 0'));
      expect(ohosView, contains('if (!this.portrait)'));
      // Logo 保留（用户明确要求）。
      expect(ohosView, contains('showLogo'));
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

    test('XComponent 有 onAreaChange 兜底同步尺寸', () {
      // 子窗口转屏时 onSurfaceChanged 可能不触发，需 onAreaChange 兜底。
      expect(ohosView, contains("HimiMpvNativeHost.getInstance().surfaceChanged(''"));
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

    test('玻璃采样节拍 600ms + 只采面板矩形（修面板区域视频卡顿）', () {
      final kotlinGlass = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'GlassBackdrop.kt',
      ).readAsStringSync();
      expect(kotlinGlass, contains('SAMPLE_INTERVAL_MS = 600L'));
      expect(kotlinGlass, contains('panelRect'));
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
}
