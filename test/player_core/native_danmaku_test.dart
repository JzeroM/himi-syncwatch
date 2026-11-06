import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/player/widgets/danmaku_overlay.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_timeline.dart';
import 'package:himi_syncwatch/services/player/mpv_player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

/// 原生弹幕（安卓 / 鸿蒙）与 Flutter（MDK）语义一致性 + 竖屏标题隐藏。
///
/// 589：安卓 `DanmakuLayerView` 重写（行号绑定生命周期、飞行缓存、倍速
/// 外推、顶底冲突检测、测量缓存、尺寸变化重排等），语义逐条对齐 Flutter
/// `DanmakuOverlay` + `DanmakuTimeline`。
void main() {
  final kotlinDanmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'DanmakuLayerView.kt',
  ).readAsStringSync();
  final ohosDanmaku = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/DanmakuLayer.ets',
  ).readAsStringSync();
  final adapter =
      File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();
  final stateDart =
      File('lib/services/player/native/native_player_state.dart')
          .readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('安卓弹幕：行号绑定生命周期（禁全量重分配）', () {
    test('laneOf 增量分配 + 三组独立冲突表', () {
      expect(kotlinDanmaku, contains('private val laneOf = HashMap<String, Int>()'));
      expect(kotlinDanmaku, contains('if (laneOf.containsKey(key)) continue'));
      expect(kotlinDanmaku, contains('private var scrollAvail'));
      expect(kotlinDanmaku, contains('private var topAvail'));
      expect(kotlinDanmaku, contains('private var bottomAvail'));
      // 旧实现的全量重分配（lanes = IntArray(n) { -1 }）必须消失。
      expect(kotlinDanmaku, isNot(contains('lanes = IntArray(n)')));
    });

    test('轨道满丢弃（-1），不回落 0 行叠加', () {
      expect(kotlinDanmaku, contains('laneOf[key] = lane'));
      expect(kotlinDanmaku, contains('if (lane < 0) continue'));
      expect(kotlinDanmaku, isNot(contains('lane = 0 // 溢出兜底')));
    });

    test('顶/底冲突检测（禁纯轮转 % n）', () {
      // 旧实现 `topRow = (topRow + 1) % topRowCount` 无冲突检测 → 同屏重叠。
      expect(kotlinDanmaku, isNot(contains('% topRowCount')));
      expect(kotlinDanmaku, isNot(contains('% bottomRowCount')));
      expect(kotlinDanmaku, contains('fixedMs + trackGapMs'));
    });
  });

  group('安卓弹幕：飞行缓存（防滚到一半消失）', () {
    test('flying 缓存 + 生命周期结束才释放行号', () {
      expect(kotlinDanmaku, contains('private var flying'));
      expect(kotlinDanmaku, contains('syncFlying'));
      expect(kotlinDanmaku, contains('laneOf.remove(keyOf(f))'));
      expect(kotlinDanmaku, contains('lifeSlackMs'));
    });
  });

  group('安卓弹幕：时钟（616 Choreographer 帧驱动 + 平滑收敛）', () {
    test('帧时间插值（对齐 Flutter Ticker）', () {
      // 616：位置 = 锚点 + 帧时间增量；快照刷新做平滑收敛（吸收 10%）。
      expect(kotlinDanmaku,
          contains('anchorPosMs + (frameElapsedMs() - anchorFrameMs) * playRate'));
      expect(kotlinDanmaku, contains('Choreographer'));
      expect(kotlinDanmaku, contains('anchorPosMs = projected + drift / 10.0'));
    });
  });

  group('安卓弹幕：几何与观感对齐 Flutter', () {
    test('底部弹幕用 (lane+1)（旧实现贴屏幕底缘）', () {
      expect(kotlinDanmaku, contains('(lane + 1) * rowH'));
      expect(kotlinDanmaku, isNot(contains('height - edgePad - lane * rowH')));
    });

    test('行容量扣上下边距（旧实现漏扣 → 末行出屏）', () {
      expect(kotlinDanmaku, contains('(screenH - 2 * edgePadPx) / rowH'));
    });

    test('固定弹幕淡入淡出（首尾 10%）', () {
      expect(kotlinDanmaku, contains('private fun fixedFade(progress: Double)'));
      expect(kotlinDanmaku, contains('progress < 0.1 -> progress / 0.1'));
      expect(kotlinDanmaku, contains('(1.0 - progress) / 0.1'));
    });

    test('w500 字重 + 黑 54% blur3 描影（禁粗描边）', () {
      expect(kotlinDanmaku, contains('Typeface.create("sans-serif-medium"'));
      expect(kotlinDanmaku, contains('setShadowLayer(3f * density'));
      expect(kotlinDanmaku, contains('0x8A000000'));
      // 旧的 strokePaint 粗描边必须消失。
      expect(kotlinDanmaku, isNot(contains('strokePaint')));
    });
  });

  group('安卓弹幕：性能与自愈', () {
    test('文本宽度测量缓存（旧实现每帧逐条 measureText）', () {
      expect(kotlinDanmaku, contains('private val measureCache'));
      expect(kotlinDanmaku, contains('private fun textWidth(text: String, fontSizePx: Float)'));
      expect(kotlinDanmaku, contains('measureCache.clear()'));
    });

    test('尺寸变化重排（转屏后行容量变化）', () {
      expect(kotlinDanmaku, contains('override fun onSizeChanged'));
      expect(kotlinDanmaku, contains('laneOf.clear()'));
    });

    test('无活跃弹幕不重绘（旧实现无条件 postInvalidate）', () {
      // 616：重绘由 Choreographer 帧回调驱动，无弹幕时停掉帧循环省电。
      expect(kotlinDanmaku, contains('if (!drewAny) stopFrameLoop()'));
      expect(kotlinDanmaku, contains('var drewAny = false'));
    });

    test('宽度估算逐字复刻 Flutter estimateTextWidth（CJK/全角 1.0、其余 0.55）', () {
      expect(kotlinDanmaku, contains('cp in 0x2E80..0xA4CF'));
      expect(kotlinDanmaku, contains('cp in 0xAC00..0xD7A3'));
      expect(kotlinDanmaku, contains('cp in 0xFF00..0xFF60'));
      expect(kotlinDanmaku, contains('units += if (isWide) 1.0 else 0.55'));
    });
  });

  group('三端弹幕常量一致（对齐 Flutter DanmakuOverlay/Timeline）', () {
    test('基准字号 25 / 行距 6 / 边距 8', () {
      expect(DanmakuOverlay.baseFontSize, 25);
      expect(DanmakuOverlay.rowGap, 6);
      expect(DanmakuOverlay.edgePadding, 8);
      expect(kotlinDanmaku, contains('private val baseFontSizeDp = 25f'));
      expect(kotlinDanmaku, contains('private val rowGapDp = 6f'));
      expect(kotlinDanmaku, contains('private val edgePadDp = 8f'));
      expect(ohosDanmaku, contains('const BASE_FONT_SIZE = 25;'));
      expect(ohosDanmaku, contains('const ROW_GAP = 6;'));
      expect(ohosDanmaku, contains('const EDGE_PAD = 8;'));
    });

    test('穿屏 8s / 驻留 4s / 轨道间隙 150ms', () {
      expect(DanmakuTimeline.scrollBaseSeconds, 8);
      expect(DanmakuTimeline.fixedSeconds, 4);
      expect(DanmakuTimeline.trackGapSeconds, 0.15);
      expect(kotlinDanmaku, contains('private val scrollBaseMs = 8000.0'));
      expect(kotlinDanmaku, contains('private val fixedMs = 4000.0'));
      expect(kotlinDanmaku, contains('private val trackGapMs = 150.0'));
      expect(ohosDanmaku, contains('const SCROLL_BASE_MS = 8000;'));
      expect(ohosDanmaku, contains('const FIXED_MS = 4000;'));
    });

    test('鸿蒙行容量变化也清行号表（589 转屏重排）', () {
      expect(ohosDanmaku, contains('this.laneOf.clear();'));
    });
  });

  group('弹幕屏蔽链进原生（589 补齐）', () {
    test('NativePlayerUiExtras 携带屏蔽字段', () {
      expect(stateDart, contains('this.danmakuBlockTop = false'));
      expect(stateDart, contains('this.danmakuBlockBottom = false'));
      expect(stateDart, contains('this.danmakuBlockWords = const <String>[]'));
      expect(stateDart, contains('final bool danmakuBlockTop;'));
      expect(stateDart, contains('final List<String> danmakuBlockWords;'));
    });

    test('PlayerScreen 注入设置值', () {
      expect(screen, contains('danmakuBlockTop: settings.danmakuBlockTop'));
      expect(screen, contains('danmakuBlockBottom: settings.danmakuBlockBottom'));
      expect(screen, contains('settings.danmakuBlockWords'));
    });

    test('_buildDanmakuWindow 按 DanmakuTimeline._filter 同序过滤', () {
      expect(adapter, contains('_nativeUiExtras.danmakuBlockTop'));
      expect(adapter, contains('_nativeUiExtras.danmakuBlockBottom'));
      expect(adapter, contains('_nativeUiExtras.danmakuBlockWords'));
      expect(adapter, contains('if (blockTop && c.mode == DanmakuMode.top)'));
      expect(adapter, contains('if (blockBottom && c.mode == DanmakuMode.bottom)'));
      expect(adapter, contains('if (word.isNotEmpty && c.text.contains(word))'));
    });

    test('窗口按 timeMs 升序（原生行分配必须时间序增量推进）', () {
      expect(adapter, contains('out.sort((a, b) => a.timeMs.compareTo(b.timeMs))'));
    });
  });

  group('弹幕屏蔽过滤语义（纯函数对照 Flutter _filter）', () {
    List<DanmakuComment> comments() => [
          const DanmakuComment(
              time: 1, mode: DanmakuMode.scroll, color: 0xFFFFFFFF, text: '滚动的'),
          const DanmakuComment(
              time: 2, mode: DanmakuMode.top, color: 0xFFFFFFFF, text: '顶部的'),
          const DanmakuComment(
              time: 3, mode: DanmakuMode.bottom, color: 0xFFFFFFFF, text: '底部的'),
          const DanmakuComment(
              time: 4, mode: DanmakuMode.scroll, color: 0xFFFFFFFF, text: '含屏蔽词的'),
        ];

    test('屏蔽顶部只留滚动+底部', () {
      final tl = DanmakuTimeline(
        comments: comments(),
        config: const DanmakuTimelineConfig(
          scrollRows: 10,
          topRows: 10,
          bottomRows: 10,
          blockTop: true,
        ),
        screenWidth: 1000,
      );
      final modes = tl.filtered.map((c) => c.mode).toList();
      expect(modes, isNot(contains(DanmakuMode.top)));
      expect(modes, contains(DanmakuMode.bottom));
    });

    test('屏蔽词子串匹配', () {
      final tl = DanmakuTimeline(
        comments: comments(),
        config: const DanmakuTimelineConfig(
          scrollRows: 10,
          topRows: 10,
          bottomRows: 10,
          blockWords: ['屏蔽'],
        ),
        screenWidth: 1000,
      );
      expect(tl.filtered.any((c) => c.text == '含屏蔽词的'), isFalse);
      expect(tl.filtered.length, 3);
    });
  });

  group('竖屏手机不显示顶栏标题（589）', () {
    test('showTopBarTitle 四象限', () {
      expect(
        PlayerScreen.showTopBarTitle(portrait: true, mobilePlatform: true),
        isFalse,
        reason: '竖屏手机必须隐藏标题（否则尾簇被挤出屏）',
      );
      expect(
        PlayerScreen.showTopBarTitle(portrait: false, mobilePlatform: true),
        isTrue,
      );
      expect(
        PlayerScreen.showTopBarTitle(portrait: true, mobilePlatform: false),
        isTrue,
        reason: 'TV/桌面竖屏（罕见）保留标题',
      );
      expect(
        PlayerScreen.showTopBarTitle(portrait: false, mobilePlatform: false),
        isTrue,
      );
    });

    test('Flutter 顶栏接入（MDK/Erika/media_kit 共用）', () {
      expect(screen, contains('PlayerScreen.showTopBarTitle('));
      expect(screen, contains('title: showTitle ? _currentEpisodeTitle : \'\''));
    });

    test('安卓 / 鸿蒙原生早已按 portrait 隐藏', () {
      expect(kotlinScreen, contains('titleText.text = if (portrait) "" else state.displayTitle'));
      expect(ohosView, contains('if (!this.portrait) {'));
    });
  });

  group('鸿蒙转圈（589 根因：必须读 @State）', () {
    test('showLoading 是 @State 且在 build() 直读', () {
      expect(ohosView, contains('@State showLoading: boolean = false;'));
      expect(ohosView, contains('this.showLoading = s.showLoading;'));
      expect(ohosView, contains('if (this.showLoading) {'));
      // 宿主的普通字段（不在 ArkUI 观察链上）不得直接进 build() 条件。
      expect(ohosView, isNot(contains('if (this.state().showLoading) {')));
    });

    test('Dart 侧 fps 判据 + 看门狗兜底', () {
      expect(adapter, contains('(state.videoFps ?? 0) > 0'));
      expect(adapter, contains('static const int loadingWatchdogMs = 3000;'));
      expect(adapter, contains('shouldFireLoadingWatchdog'));
      expect(adapter, contains('_loadingWatchdogFired = true'));
    });

    test('看门狗纯函数边界', () {
      expect(
        MpvPlayerAdapter.shouldFireLoadingWatchdog(
          state: AdapterPlaybackState.playing,
          positionMs: 2999,
        ),
        isFalse,
      );
      expect(
        MpvPlayerAdapter.shouldFireLoadingWatchdog(
          state: AdapterPlaybackState.playing,
          positionMs: 3000,
        ),
        isTrue,
      );
      expect(
        MpvPlayerAdapter.shouldFireLoadingWatchdog(
          state: AdapterPlaybackState.paused,
          positionMs: 60000,
        ),
        isFalse,
        reason: '暂停不触发（用户主动暂停时转圈应保持）',
      );
    });

    test('看门狗在新起播时复位', () {
      expect(adapter, contains('_loadingWatchdogFired = false;'));
    });
  });
}
