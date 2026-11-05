import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 596：底栏定位 / 当前集左边框 / 搜索条件 / 弹出面板宽度。
void main() {
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('底栏定位：不再用 MATCH_PARENT 撑满（跑到顶部根因）', () {
    test('安卓底栏高度保持 WRAP_CONTENT（597 竖屏分栏另有 TOP 定位）', () {
      // 595 把 height 设成 MATCH_PARENT（横屏）→ 底栏内部
      // LinearLayout.VERTICAL 撑满高度后内容从顶部排 → 进度条/控件跑到
      // 屏幕最上方与顶栏重叠（真机截图回归）。
      expect(kotlinScreen, contains('it.height = LayoutParams.WRAP_CONTENT'));
      expect(
        kotlinScreen,
        isNot(contains('it.height = if (portrait) videoH else LayoutParams.MATCH_PARENT')),
      );
    });

    test('注释说明根因', () {
      expect(kotlinScreen, contains('进度条/底栏跑到屏幕顶部'));
    });
  });

  group('当前集左边框：不占布局宽度', () {
    test('安卓用 foreground Drawable 而非独立 View', () {
      expect(kotlinScreen, contains('private fun leftAccentDivider()'));
      expect(kotlinScreen, contains('foreground = leftAccentDivider()'));
      // 旧实现用独立 View 占 3dp 宽（视觉多一条竖条 + 右推内容）。
      expect(
        kotlinScreen,
        isNot(contains('addView(\n                    View(context).apply { setBackgroundColor(NPTheme.ACCENT) },\n                    llp(dp(3), dp(44)),\n                )')),
      );
    });

    test('Drawable 只画左侧 3dp', () {
      expect(kotlinScreen, contains('(b.left + dp(3)).toFloat()'));
    });

    test('鸿蒙用 border 左 3vp（不占布局宽）', () {
      expect(ohosView, contains("width: { left: 3 }, color: SEL_COLOR"));
      // 旧实现的独立占位 Column 已删除。
      expect(ohosView, isNot(contains('Column()\n          .width(3)\n          .height(44)')));
    });
  });

  group('搜索控件：房主且暂停中才显示（Flutter state != playing）', () {
    test('安卓条件 isHost && paused', () {
      expect(kotlinScreen, contains('if (state.isHost && state.paused) VISIBLE else GONE'));
      // 595 写反的 `!paused` 已移除。
      expect(kotlinScreen, isNot(contains('if (state.isHost && !state.paused) VISIBLE')));
    });

    test('鸿蒙条件同步', () {
      expect(ohosView, contains('if (this.state().isHost && this.state().paused) {'));
      expect(ohosView, isNot(contains('if (this.state().isHost && !this.state().paused) {')));
    });

    test('Flutter 参考实现（state != playing）', () {
      final flutter = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(flutter, contains('_player.state != AdapterPlaybackState.playing'));
    });
  });

  group('弹出面板宽度不被分栏覆盖', () {
    test('applyVideoSplit 不改 panelContainer.width', () {
      // 595 在这里把 width 改成 videoW，与 renderOverlays 的
      // `lp(panelWidthDp(), MATCH_PARENT)` 冲突 → 面板撑满视频区，
      // 看起来「没显示」。
      final idx = kotlinScreen.indexOf('private fun applyVideoSplit(insetPx: Int) {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 4000);
      expect(body, isNot(contains('it.width = videoW; panelContainer.layoutParams = it')));
      // 但遮罩仍然要限制在视频区。
      expect(body, contains('panelScrim.layoutParams = it'));
    });

    test('panelWidthDp 按视频区宽计算（597 抽成 videoAreaWidth）', () {
      expect(kotlinScreen, contains('private fun videoAreaWidth(): Int {'));
      expect(kotlinScreen, contains('val available = videoAreaWidth()'));
      expect(kotlinScreen, contains('(w - lastVideoSplitInsetPx).coerceAtLeast(1)'));
      // 竖屏 inset 是面板**高度**，不能拿它减宽度（否则面板被算窄）。
      expect(kotlinScreen, contains('val portrait = h > w'));
    });
  });
}
