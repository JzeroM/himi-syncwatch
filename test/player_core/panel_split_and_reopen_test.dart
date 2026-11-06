import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 597：弹出面板贴视频区 / 竖屏底栏 / 搜索后重开原生 UI / 锁定态底栏常显。
void main() {
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();

  group('① 弹出面板贴视频区右缘（不再被资源面板盖住）', () {
    test('panelContainer 用 START + leftMargin，不用 END', () {
      // 旧实现 `Gravity.END + marginEnd`：父级是根 FrameLayout（全屏宽），
      // 分栏后面板贴在「全屏右缘」→ 正好被资源面板盖住；遮罩盖住视频区
      // → 用户只看到「视频区变黑、面板不见」。
      final idx = kotlinScreen.indexOf('private fun renderOverlays() {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 12000);
      // 构造用 `lp(panelW, panelH, Gravity.START or Gravity.TOP)`。
      expect(body, contains('Gravity.START or Gravity.TOP,'));
      expect(body, contains('it.leftMargin = panelLeftMarginPx(panelW, fullBleed)'));
      expect(body, isNot(contains('it.gravity = Gravity.END or Gravity.TOP')));
      expect(body, isNot(contains('it.marginEnd = if (fullBleed) 0')));
    });

    test('panelLeftMarginPx = 视频区宽 - 面板宽 - 12dp', () {
      expect(kotlinScreen, contains('private fun panelLeftMarginPx(panelW: Int, fullBleed: Boolean): Int'));
      // 610：fullBleed 时 rightPad=0（贴右无间距）。
      expect(
        kotlinScreen,
        contains('return (videoAreaWidth() - panelW - rightPad).coerceAtLeast(0)'),
      );
    });

    test('面板高度限制在视频区内（不再 MATCH_PARENT 到屏幕底）', () {
      // 竖屏分栏时资源面板占底部 280dp，MATCH_PARENT 会让面板压到面板上。
      expect(kotlinScreen, contains('val panelH = (videoAreaHeight() - panelTop - panelBottom).coerceAtLeast(1)'));
    });

    test('applyVideoSplit 同步面板 leftMargin（不动 END 定位）', () {
      final idx = kotlinScreen.indexOf('private fun applyVideoSplit(insetPx: Int) {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 8000);
      expect(body, contains('it.leftMargin = (videoW - panelW - dp(NPTheme.PANEL_RIGHT)).coerceAtLeast(0)'));
      expect(body, contains('it.height = (videoH - it.topMargin - it.bottomMargin).coerceAtLeast(1)'));
    });

    test('解码 popover 同样贴视频区右缘', () {
      // 旧实现 `Gravity.TOP or Gravity.END + marginEnd` 也会被资源面板盖住。
      expect(kotlinScreen, contains('private fun renderDecodePopover() {'));
      final idx = kotlinScreen.indexOf('private fun renderDecodePopover() {');
      final body = kotlinScreen.substring(idx, idx + 1200);
      expect(body, contains('it.gravity = Gravity.START or Gravity.TOP'));
      expect(body, contains('panelLeftMarginPx(dp(NPTheme.DECODE_PANEL_WIDTH), false)'));
      expect(body, isNot(contains('Gravity.TOP or Gravity.END')));
    });

    test('片头片尾卡在视频区内居中（不再相对全屏 CENTER）', () {
      expect(kotlinScreen, contains('private fun positionVideoCenteredCard(v: View)'));
      expect(kotlinScreen, contains('positionVideoCenteredCard(segmentCard)'));
      expect(kotlinScreen, contains('val videoH = videoAreaHeight()'));
      // 旧实现 `Gravity.CENTER` 相对根 FrameLayout（全屏）。
      expect(
        kotlinScreen,
        isNot(contains('segmentCard.layoutParams = lp(dp(NPTheme.SEGMENT_CARD_WIDTH), LayoutParams.WRAP_CONTENT, Gravity.CENTER)')),
      );
    });
  });

  group('② 竖屏底栏贴视频区底缘（不再被资源面板盖住）', () {
    test('竖屏分栏用 TOP + topMargin = videoH - 底栏高', () {
      expect(kotlinScreen, contains('val portraitSplit = portrait && panelSizePx > 0'));
      expect(
        kotlinScreen,
        contains('it.topMargin = (videoH - dp(BOTTOM_BAR_ESTIMATED_HEIGHT)).coerceAtLeast(0)'),
      );
      expect(kotlinScreen, contains('const val BOTTOM_BAR_ESTIMATED_HEIGHT = 100'));
    });

    test('布局完成后用实测高度修正 topMargin', () {
      expect(kotlinScreen, contains('val barH = bottomBar.height'));
      expect(kotlinScreen, contains('val target = (videoH - barH).coerceAtLeast(0)'));
    });

    test('未分栏时仍走 Gravity.BOTTOM（不多此一举）', () {
      final idx = kotlinScreen.indexOf('val portraitSplit = portrait && panelSizePx > 0');
      final body = kotlinScreen.substring(idx, idx + 900);
      expect(body, contains('it.gravity = Gravity.START or Gravity.BOTTOM'));
    });

    test('注释记录根因', () {
      expect(kotlinScreen, contains('竖屏进度条和底栏没有'));
    });
  });

  group('③ 搜索后重开原生 UI（黑屏根因）', () {
    test('适配器提供 reopenNativeUi()', () {
      expect(adapter, contains('Future<void> reopenNativeUi() async {'));
      expect(adapter, contains('_openNativeUiIfNeeded(waitForPlatformViewTeardown: true)'));
      // 已开着时只补推一次状态，不重复开窗。
      expect(adapter, contains('_pushNativeUiState(immediate: true);'));
    });

    test('重开前等待平台视图卸载（避免两个 SurfaceView 抢绑定）', () {
      expect(adapter, contains('bool waitForPlatformViewTeardown = false,'));
      expect(adapter, contains('await Future<void>.delayed(const Duration(milliseconds: 250));'));
    });

    test('603：搜索流程改用 suspend/resume（不再 close + reopen）', () {
      // 597 用 closeNativeUi + reopenNativeUi 修黑屏，但那是**销毁后重建**
      // ——要重新绑定 surface，有「两个 SurfaceView 抢绑定」风险。
      // 603 改为 suspend（只隐藏）→ 搜索页 → resume，session 原封不动，
      // 零黑屏。
      final idx = screen.indexOf(
          'Future<void> _openRoomResourceSearchFromNative() async {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 3000);
      expect(body, contains('await mpv.suspendNativeUi();'));
      expect(body, contains('await resume.resumeNativeUi();'));
      expect(body, isNot(contains('await mpv.closeNativeUi();')));
      expect(body, isNot(contains('reopenNativeUi()')));
    });

    test('失败不抛给 UI（只记日志）', () {
      final idx = screen.indexOf("LogService().log('mpv', '搜索返回恢复原生 UI 失败");
      expect(idx, greaterThan(0));
    });
  });

  group('④ 锁定态底栏常显（锁控件不再消失）', () {
    test('锁定分支强制 bottomBar VISIBLE', () {
      final idx = kotlinScreen.indexOf('if (!tv && state.locked) {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 1500);
      expect(body, contains('bottomBar.visibility = VISIBLE'));
    });

    test('setControlsVisible 在锁定态不藏底栏、不排自动隐藏', () {
      final idx = kotlinScreen.indexOf('private fun setControlsVisible(visible: Boolean) {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 900);
      expect(body, contains('if (!lastState.tvMode && lastState.locked) {'));
      expect(body, contains('bottomBar.visibility = VISIBLE'));
      // 自动隐藏计时器在锁定态直接 return（否则 5s 后又藏掉锁钮）。
      final autoIdx = kotlinScreen.indexOf('private fun scheduleAutoHide() {');
      final autoBody = kotlinScreen.substring(autoIdx, autoIdx + 500);
      expect(autoBody, contains('if (!lastState.tvMode && lastState.locked) return'));
    });

    test('注释记录根因', () {
      expect(kotlinScreen, contains('锁定态切资源后锁控件消失'));
    });
  });

  group('⑤ 鸿蒙同步（面板/底栏/锁控件）', () {
    test('鸿蒙面板贴视频区（分栏容器内），不靠 Stack 全屏定位', () {
      // 鸿蒙侧面板在分栏容器内（Row/Column 的第二子项），天然只在视频区，
      // 不需要安卓那套 leftMargin 换算；此处确认结构仍在。
      expect(ohosView, contains('this.RoomPanelSlot();'));
      // 610：方向定位改由 Flex 的 direction 体现（面板是流式子节点）。
      expect(ohosView, contains('FlexDirection.Column : FlexDirection.Row'));
    });

    test('鸿蒙锁定态只出 LockOnlyBar（底栏壳走 else 分支）', () {
      expect(ohosView, contains('if (this.locked && !this.state().tvMode) {'));
      expect(ohosView, contains('this.LockOnlyBar({ rev: this.renderTick });'));
    });
  });
}
