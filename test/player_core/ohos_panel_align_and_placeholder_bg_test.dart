import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 608：鸿蒙面板定位改 Stack 对齐 + 缩放宽度补 panelToggle + 占位层黑底。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('① 面板定位用 Stack alignContent（不再用 margin 反推）', () {
    test('610 起改用 Flex 流式分栏（Stack 叠加方案已废弃）', () {
      expect(view, contains('Flex({'));
      expect(view, contains('direction: this.portrait ? FlexDirection.Column : FlexDirection.Row'));
      final idx = view.indexOf('RoomPanelSlot() {');
      final end = view.indexOf('  build() {', idx);
      final body = view.substring(idx, end);
      expect(body, isNot(contains('Stack({')));
    });

    test('不再用 margin 推算面板位置', () {
      // `margin.left = videoW` 依赖 `areaWidth`，子窗口场景下可能偏大 →
      // 面板右缘被裁到屏外（头部三控件随之"消失"）。
      final idx = view.indexOf('RoomPanelSlot() {');
      final end = view.indexOf('  build() {', idx);
      final body = view.substring(idx, end);
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('margin(')));
      expect(code, isNot(contains('alignContent')));
    });

    test('610 起面板是流式子节点，不再需要 Transparent 放行', () {
      // 流式布局下 Flex 容器只占自身尺寸，视频区触摸天然不受影响。
      final idx = view.indexOf('Flex({\n        direction: this.portrait ? FlexDirection.Column');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 1200);
      expect(body, contains('.width('));
      expect(body, contains('.height('));
    });

    test('注释记录 areaWidth 反推的根因', () {
      expect(view, contains('面板右缘被'));
    });
  });

  group('② trailingNaturalWidth 补 panelToggle（否则缩放比偏大）', () {
    test('房间模式 blocks++', () {
      final idx = view.indexOf('private trailingNaturalWidth(): number {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 1200);
      expect(body, contains('if (this.state().isRoom) {'));
      expect(body, contains('blocks++;'));
    });

    test('注释记录按钮飞出屏幕根因', () {
      expect(view, contains('面板开关按钮飞出屏幕'));
    });

    test('其他 blocks 计算保持（不误加）', () {
      final idx = view.indexOf('private trailingNaturalWidth(): number {');
      final body = view.substring(idx, idx + 1200);
      // 弹幕恒 1 块；字幕+音轨恒 2 块。
      expect(body, contains('let blocks = 1;'));
      expect(body, contains('blocks += 2;'));
    });
  });

  group('③ 占位层有不透明黑底（盖住 mpv 残留帧）', () {
    test('占位层 backgroundColor(Color.Black)', () {
      final idx = view.indexOf('if (!this.playerReady) {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 1200);
      expect(body, contains('.backgroundColor(Color.Black)'));
    });

    test('仍保持不抢手势', () {
      final idx = view.indexOf('if (!this.playerReady) {');
      final body = view.substring(idx, idx + 1200);
      expect(body, contains('.hitTestBehavior(HitTestMode.None)'));
    });

    test('注释记录残留帧根因', () {
      expect(view, contains('仍残留最后一帧'));
    });
  });

  group('④ 607 的修复保持不回退', () {
    test('611 起头部改用 Flex + flexShrink', () {
      final idx = view.indexOf("Text('资源')");
      final body = view.substring(idx, idx + 700);
      expect(body, contains('.flexShrink(1)'));
    });

    test('播放图标仍有独立 onClick + Block', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      expect(body, contains('.hitTestBehavior(HitTestMode.Block)'));
      expect(body, contains('this.host().optimisticTogglePaused()'));
    });

    test('playerReady 链路仍在', () {
      expect(view, contains('@State playerReady: boolean = true;'));
      expect(view, contains('this.playerReady = s.playerReady;'));
    });

    test('全文件仍无 position / markAnchor / translate', () {
      expect(RegExp(r'^\s*\.position\(', multiLine: true).hasMatch(view), isFalse);
      expect(RegExp(r'^\s*\.markAnchor\(', multiLine: true).hasMatch(view), isFalse);
      expect(view, isNot(contains('.translate(')));
    });
  });
}
