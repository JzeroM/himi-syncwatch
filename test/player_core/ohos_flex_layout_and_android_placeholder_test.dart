import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 610：鸿蒙 Flex 流式分栏 + 安卓占位层 + 选集面板贴右 + 弹幕尺寸重排。
void main() {
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final kotlinState = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'AndroidNativePlayerState.kt',
  ).readAsStringSync();
  final kotlinDanmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'DanmakuLayerView.kt',
  ).readAsStringSync();

  group('① 鸿蒙面板改 Flex 流式分栏（不再用 Stack 叠加定位）', () {
    test('build 用 Flex + direction 动态切方向', () {
      expect(ohosView, contains('Flex({'));
      expect(ohosView, contains('direction: this.portrait ? FlexDirection.Column : FlexDirection.Row'));
    });

    test('VideoStack 用 layoutWeight 弹性（不设 width 100%）', () {
      final idx = ohosView.indexOf('VideoStack() {');
      final end = ohosView.indexOf('  /** 房间资源面板槽', idx);
      final body = ohosView.substring(idx, end);
      // 625：`.layoutWeight(1)` 后紧跟 `.onAreaChange`（视频区实测），
      // 故不再断言以 `;` 结尾。
      expect(body, contains('.layoutWeight(1)'));
      // 不得同时设 width('100%')（会覆盖 layoutWeight）。
      expect(body, isNot(contains(".width(this.videoW > 0")));
    });

    test('RoomPanelSlot 不再用 Stack 叠加定位', () {
      final idx = ohosView.indexOf('RoomPanelSlot() {');
      final end = ohosView.indexOf('  build() {', idx);
      final body = ohosView.substring(idx, end);
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('Stack({')));
      expect(code, isNot(contains('alignContent')));
      expect(code, isNot(contains('margin(')));
    });

    test('RoomPanelSlot 是 Flex 的流式子节点（固定 320vp / 280vp）', () {
      final idx = ohosView.indexOf('RoomPanelSlot() {');
      final end = ohosView.indexOf('  build() {', idx);
      final body = ohosView.substring(idx, end);
      expect(body, contains(".width(this.portrait ? '100%' : ROOM_PANEL_WIDTH)"));
      expect(body, contains(".height(this.portrait ? ROOM_PANEL_HEIGHT : '100%')"));
    });

    test('注释记录 Stack 全屏容器导致面板跑到屏外', () {
      expect(ohosView, contains('面板整个消失'));
    });
  });

  group('② 安卓空态占位层（盖住 mpv 残留帧）', () {
    test('AndroidNativePlayerState 有 playerReady', () {
      expect(kotlinState, contains('val playerReady: Boolean = true,'));
      expect(kotlinState, contains('playerReady = json.optBoolean("playerReady", true),'));
    });

    test('placeholderView 存在且有不透明黑底', () {
      expect(kotlinScreen, contains('private val placeholderView = LinearLayout(context).apply {'));
      final idx = kotlinScreen.indexOf('private val placeholderView');
      final body = kotlinScreen.substring(idx, idx + 1400);
      expect(body, contains('setBackgroundColor(Color.BLACK)'));
      expect(body, contains('请从资源面板选择要播放的内容'));
      expect(body, contains('ICON_PLAY_CIRCLE'));
    });

    test('占位层加在 bufferingView 之前（z-order 低于转圈）', () {
      final phIdx = kotlinScreen.indexOf('addView(placeholderView');
      final bufIdx = kotlinScreen.indexOf('addView(bufferingView');
      expect(phIdx, greaterThan(0));
      expect(bufIdx, greaterThan(phIdx));
    });

    test('显隐由 playerReady 驱动', () {
      expect(
        kotlinScreen,
        contains('placeholderView.visibility = if (!state.playerReady) VISIBLE else GONE'),
      );
    });
  });

  group('③ 安卓选集面板贴右（fullBleed 不再贴左）', () {
    test('panelLeftMarginPx 不再对 fullBleed 直接 return 0', () {
      final idx = kotlinScreen.indexOf('private fun panelLeftMarginPx');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 900);
      // 只检查代码行（注释里会引用旧写法说明根因）。
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('if (fullBleed) return 0')));
      expect(body, contains('val rightPad = if (fullBleed) 0 else dp(NPTheme.PANEL_RIGHT)'));
      expect(body, contains('videoAreaWidth() - panelW - rightPad'));
    });

    test('Flutter 参考：fullBleed 时 right 0（贴右无间距）', () {
      final flutter = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(flutter, contains('? (top: 0.0, bottom: 0.0, right: 0.0)'));
    });
  });

  group('④ 安卓弹幕 onSizeChanged 只在容量变化时重排', () {
    test('按 autoRows 判断（不是任何尺寸变化都清）', () {
      final idx = kotlinDanmaku.indexOf('override fun onSizeChanged');
      expect(idx, greaterThan(0));
      final body = kotlinDanmaku.substring(idx, idx + 1200);
      expect(body, contains('lastAutoRows'));
      expect(body, contains('if (newAuto == lastAutoRows) return'));
      expect(body, contains('if (h <= 0) return'));
    });

    test('注释记录抽搐根因', () {
      expect(kotlinDanmaku, contains('只有一行 + 前后抽搐'));
    });
  });
}
