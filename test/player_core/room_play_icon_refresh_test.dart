import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 598：资源行播放/暂停图标就地刷新 + 鸿蒙 597 回归回滚。
void main() {
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final ohosPanel = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'NativePlayerPanel.ets',
  ).readAsStringSync();
  final flutterScreen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  group('① 鸿蒙 597 回归回滚（控件全部消失）', () {
    test('鸿蒙不含 .translate（全项目首次使用，叠在 position/markAnchor 上跑位）', () {
      // 597 在已有 `position({y:'100%'}) + markAnchor({y:'100%'})` 的节点上
      // 又加 `.translate({y:-280})`：布局与绘制两套坐标系打架 → 底栏被推到
      // 屏幕外，顶栏/底栏全部消失（真机「一进入就消失」）。
      expect(ohosView, isNot(contains('.translate(')));
      expect(ohosView, isNot(contains('translate({')));
    });

    test('鸿蒙不含 bottomInset 传参', () {
      expect(ohosView, isNot(contains('bottomInset:')));
    });

    test('鸿蒙面板不含 @Prop bottomInset 与对应 padding', () {
      expect(ohosPanel, isNot(contains('@Prop bottomInset')));
      expect(ohosPanel, isNot(contains('this.bottomInset')));
    });

    test('600 已改为流式布局：不再有 position + markAnchor', () {
      // 598 时这里是「回滚到 596 的 position + markAnchor」；600 起控件层
      // 改为 Column + Blank 流式布局，百分比定位全部移除（那类定位与任何
      // 附加属性叠加都会跑位，597 的 .translate 就是这么把控件推出屏外的）。
      expect(
        RegExp(r'^\s*\.position\(', multiLine: true).hasMatch(ohosView),
        isFalse,
      );
      expect(
        RegExp(r'^\s*\.markAnchor\(', multiLine: true).hasMatch(ohosView),
        isFalse,
      );
    });

    test('控件层靠 Blank 弹性推底（替代百分比定位）', () {
      expect(ohosView, contains('Blank();'));
    });
  });

  group('② 安卓资源行图标：就地刷新，不重建列表', () {
    test('登记表存在且类型正确', () {
      expect(
        kotlinScreen,
        contains('private val roomPlayIcons = mutableListOf<Pair<TextView, Boolean>>()'),
      );
    });

    test('buildRoomPanelList 开头清空登记表', () {
      final idx = kotlinScreen.indexOf(
          'private fun buildRoomPanelList(state: AndroidNativePlayerState) {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 300);
      expect(body, contains('roomPanelList.removeAllViews()'));
      expect(body, contains('roomPlayIcons.clear()'));
    });

    test('建图标时登记「视图 → 是否当前集」', () {
      expect(kotlinScreen, contains('roomPlayIcons.add(playIcon to ep.isPlaying)'));
    });

    test('renderRoomPanel 每次都调用 refreshRoomPlayIcons', () {
      final idx = kotlinScreen.indexOf('private fun renderRoomPanel() {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 5000);
      expect(body, contains('refreshRoomPlayIcons(state)'));
    });

    test('图标条件 = 当前集 且 未暂停（对齐 Flutter）', () {
      expect(kotlinScreen, contains('val text = if (isCurrent && !state.paused) {'));
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_PAUSE_CIRCLE'));
      expect(kotlinScreen, contains('NativePlayerIcons.ICON_PLAY_CIRCLE'));
    });

    test('颜色只看是否当前集（与 Flutter 一致，不看 paused）', () {
      // Flutter: `color: isPlaying ? accent : white54`
      expect(
        kotlinScreen,
        contains('val color = if (isCurrent) NPTheme.ACCENT else NPTheme.WHITE_54'),
      );
    });

    test('不把 paused 加进列表签名（避免整表重建）', () {
      final idx = kotlinScreen.indexOf('val sig = buildString {');
      expect(idx, greaterThan(0));
      final body = kotlinScreen.substring(idx, idx + 600);
      expect(body, contains('append(state.isHost)'));
      expect(body, contains('append(e.isPlaying)'));
      // paused 只能出现在 refreshRoomPlayIcons 里，不能进签名。
      expect(body, isNot(contains('paused')));
    });

    test('签名含 isHost（房主↔观众切换要重建列表）', () {
      expect(kotlinScreen, contains("append(state.isHost).append('|')"));
    });
  });

  group('③ Flutter 参考实现（三端语义一致）', () {
    test('Flutter 图标条件 isPlaying && isPlayingNow', () {
      expect(flutterScreen, contains('isPlaying && isPlayingNow'));
      expect(flutterScreen, contains('? Icons.pause_circle'));
      expect(flutterScreen, contains(': Icons.play_circle'));
    });

    test('Flutter 颜色只看 isPlaying', () {
      expect(
        flutterScreen,
        contains('color:\n                          isPlaying ? const Color(0xFF6366F1) : Colors.white54'),
      );
    });
  });
}
