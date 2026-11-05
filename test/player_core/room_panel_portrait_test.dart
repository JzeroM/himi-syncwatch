import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 594：资源面板保留非空值 + 竖屏上下结构 + fit 后重同步 surface。
void main() {
  final playerScreen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final adapter =
      File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final kotlinHost = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'AndroidNativePlayerHost.kt',
  ).readAsStringSync();
  final kotlinTheme = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerUi.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('资源面板：保留上次非空值（一播放就空）', () {
    test('Dart 侧缓存字段 + 回退逻辑', () {
      expect(playerScreen, contains('_lastNonEmptyResourceGroups'));
      expect(playerScreen, contains('if (groups.isNotEmpty) {'));
      expect(playerScreen, contains('return _lastNonEmptyResourceGroups;'));
      expect(playerScreen, contains('void clearNativeResourceCache()'));
    });

    test('注释说明根因（起播重置窗口）', () {
      expect(playerScreen, contains('重置后、重建前'));
    });
  });

  group('竖屏上下结构', () {
    test('安卓 applyVideoSplit 有 portrait 分支', () {
      expect(kotlinScreen, contains('val portrait = screenH > screenW'));
      expect(kotlinScreen, contains('videoH = (screenH - panelSizePx).coerceAtLeast(1)'));
      expect(kotlinScreen, contains('videoW = (screenW - panelSizePx).coerceAtLeast(1)'));
    });

    test('竖屏面板贴视频区下缘、全宽 280dp', () {
      expect(kotlinScreen, contains('it.width = videoW\n                it.height = panelSizePx'));
      expect(kotlinScreen, contains('it.topMargin = videoH'));
      expect(kotlinTheme, contains('const val ROOM_PANEL_HEIGHT = 280'));
    });

    test('renderRoomPanel 按方向选 320 / 280', () {
      expect(kotlinScreen, contains('dp(NPTheme.ROOM_PANEL_HEIGHT)'));
      expect(kotlinScreen, contains('dp(NPTheme.ROOM_PANEL_WIDTH)'));
    });

    test('宿主 surface 窗按方向收窄', () {
      expect(kotlinHost, contains('val portrait = screenH > screenW'));
      expect(kotlinHost, contains('targetH = (screenH - inset).coerceAtLeast(1)'));
      expect(kotlinHost, contains('win.setLayout(targetW, targetH)'));
    });

    test('鸿蒙 if/else 双分支 + 面板 280vp（594）', () {
      // 不用 Flex({direction})：ArkTS 对三元表达式推断方向枚举报
      // arkts-no-any-unknown（构建实测）。改用 if/else 双分支。
      // 602：视频层移出分支后，竖屏/横屏只在 RoomPanelSlot 的 margin 上体现。
      expect(ohosView, contains('this.videoH > 0 ? this.videoH : 0'));
      expect(ohosView, contains('this.VideoStack();'));
      expect(ohosView, contains('this.RoomPanelSlot();'));
      expect(ohosView, contains('const ROOM_PANEL_HEIGHT = 280;'));
      expect(ohosView, contains(".height(this.portrait ? ROOM_PANEL_HEIGHT : '100%')"));
      expect(ohosView, isNot(contains('FlexDirection.Column')));
    });
  });

  group('全屏控件（fit）后重同步 surface', () {
    test('adapter 暴露 refreshSurfaceAfterFit', () {
      expect(adapter, contains('Future<void> refreshSurfaceAfterFit() async'));
      expect(adapter, contains('await _player?.refreshSurface();'));
    });

    test('_cycleVideoFit 调用它', () {
      expect(playerScreen, contains('mpv.refreshSurfaceAfterFit()'));
    });

    test('注释说明根因（尺寸异步生效）', () {
      expect(adapter, contains('setLayout'));
    });
  });

  group('Flutter 参考实现（竖屏基准）', () {
    test('Column(Expanded(video), SizedBox(280))', () {
      expect(playerScreen, contains('height: 280,'));
      expect(playerScreen, contains('Expanded(flex: 3, child: _buildVideoArea())'));
    });
  });
}
