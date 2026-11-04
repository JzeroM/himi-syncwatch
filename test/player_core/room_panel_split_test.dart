import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 593：原生播放器与资源面板真双窗口分栏。
///
/// 根因：surface 窗宽度从未真正生效（`applyFullscreen` 的
/// `setLayout(MATCH_PARENT)` 覆盖了后续 `attributes.width` 修改），
/// 且控件层仍全屏 → 资源面板「盖」在视频上。
void main() {
  final host = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'AndroidNativePlayerHost.kt',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final flutterScreen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  group('安卓 surface 窗真正收窄', () {
    test('用 setLayout 而非只改 attributes.width', () {
      // 旧实现 `lp.width = targetW; w.attributes = lp` 会被之前
      // applyFullscreen 的 setLayout(MATCH_PARENT) 覆盖，实际仍全屏。
      // 594：竖屏收窄高度、横屏收窄宽度，故是 (targetW, targetH)。
      expect(host, contains('win.setLayout(targetW, targetH)'));
      // 注释里保留了旧写法说明，所以只断言**可执行代码**里没有该短路。
      final fnStart = host.indexOf('private fun applyVideoInsetRight(insetPx: Int) {');
      expect(fnStart, greaterThan(0));
      final fnBody = host.substring(fnStart, fnStart + 600);
      expect(fnBody, isNot(contains('if (lp.width == targetW) return')));
    });

    test('贴左对齐（面板占右侧）', () {
      expect(host, contains('gravity = android.view.Gravity.START or android.view.Gravity.TOP'));
    });

    test('每次重申（不因短路跳过）', () {
      expect(host, contains('不设短路'));
    });
  });

  group('安卓控件层分栏（applyVideoSplit）', () {
    test('存在分栏方法且被 renderRoomPanel 调用', () {
      expect(kotlinScreen, contains('private fun applyVideoSplit(insetPx: Int)'));
      expect(kotlinScreen, contains('applyVideoSplit(panelPx)'));
    });

    test('左区控件按 videoW 收窄', () {
      // 视频手势层 / 弹幕 / 顶栏 / 底栏 / 面板遮罩都要跟随。
      expect(kotlinScreen, contains('videoW = (screenW - panelSizePx).coerceAtLeast(1)'));
      // 594：竖屏要同时收窄高度，故 tapLayer / danmaku / panelScrim 多一个
      // `it.height = videoH` 赋值。
      expect(kotlinScreen, contains('it.width = videoW; it.height = videoH; tapLayer.layoutParams = it'));
      expect(kotlinScreen, contains('it.width = videoW; topBar.layoutParams = it'));
      expect(kotlinScreen, contains('it.width = videoW'));
      expect(kotlinScreen, contains('bottomBar.layoutParams = it'));
    });

    test('右区面板贴左区右缘（不再是 Gravity.END 贴屏幕右缘）', () {
      expect(kotlinScreen, contains('it.leftMargin = videoW'));
      expect(kotlinScreen, contains('it.width = panelSizePx'));
    });

    test('转屏/尺寸变化后重算分栏', () {
      expect(kotlinScreen, contains('if (lastVideoSplitInsetPx > 0)'));
      expect(kotlinScreen, contains('applyVideoSplit(prev)'));
    });

    test('幂等（同 inset 不重复应用）', () {
      expect(kotlinScreen, contains('if (insetPx == lastVideoSplitInsetPx) return'));
    });
  });

  group('鸿蒙 XComponent 分栏', () {
    test('layoutWeight 与 width 二选一（同时设会 width 优先）', () {
      expect(ohosView, contains(".width(this.roomPanelVisible() ? 'auto' : '100%')"));
      expect(ohosView, contains('.layoutWeight(this.roomPanelVisible() ? 1 : 0)'));
      // 旧写法 width('100%') + layoutWeight 同时存在 → layoutWeight 失效。
      expect(ohosView, isNot(contains(".layoutWeight(this.roomPanelVisible() ? 1 : 0)\n        .width('100%')")));
    });

    test('RoomPanel 按方向切 320vp / 100%（594）', () {
      expect(ohosView, contains(".width(this.portrait ? '100%' : ROOM_PANEL_WIDTH)"));
    });
  });

  group('Flutter 参考实现（分栏基准）', () {
    test('Row(Expanded(video), SizedBox(320))', () {
      expect(flutterScreen, contains('width: 320,'));
      expect(flutterScreen, contains('Expanded(flex: 3, child: _buildVideoArea())'));
    });
  });
}
