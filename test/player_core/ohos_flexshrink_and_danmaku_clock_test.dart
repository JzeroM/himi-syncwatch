import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 611：鸿蒙头部 flexShrink + 占位层移进视频区 + 安卓弹幕单层插值。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();

  group('① 头部用 Flex + flexShrink（对齐安卓固定 LayoutParams）', () {
    test('头部容器是 Flex 而不是 Row', () {
      final idx = view.indexOf("Text('资源')");
      expect(idx, greaterThan(0));
      // 往前找最近的容器声明。
      final before = view.substring(idx - 900, idx);
      expect(before, contains('Flex({ direction: FlexDirection.Row'));
      expect(before, contains('ItemAlign.Center'));
    });

    test('标题 flexGrow(1) + flexShrink(1)（对齐安卓权重 1）', () {
      final idx = view.indexOf("Text('资源')");
      final body = view.substring(idx, idx + 800);
      // 612：flexGrow 吃掉剩余空间（把右侧控件推到最右）；
      // flexShrink 空间不足时压缩。等价安卓 LayoutParams(weight=1)。
      expect(body, contains('.flexGrow(1)'));
      expect(body, contains('.flexShrink(1)'));
      // 不再用 layoutWeight / Blank。
      expect(body, isNot(contains('layoutWeight')));
    });

    test('搜索按钮 flexShrink(0) + 固定 28×28', () {
      final idx = view.indexOf('ICON_SEARCH');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 600);
      expect(body, contains('.width(28)'));
      expect(body, contains('.height(28)'));
      expect(body, contains('.flexShrink(0)'));
    });

    test('人数胶囊 / 角色徽章 flexShrink(0)', () {
      final idx = view.indexOf("backgroundColor('#1FFFFFFF')");
      final body = view.substring(idx, idx + 600);
      expect(body, contains('.flexShrink(0)'));
      final roleIdx = view.indexOf("backgroundColor(this.roomIsHost ? SEL_COLOR : '#E53935')");
      final roleBody = view.substring(roleIdx, roleIdx + 400);
      expect(roleBody, contains('.flexShrink(0)'));
    });

    test('不再有 Blank()（607 方案已废弃）', () {
      final idx = view.indexOf("Text('资源')");
      final body = view.substring(idx, idx + 700);
      expect(body, isNot(contains('Blank();')));
    });

    test('安卓参考：固定 LayoutParams + 权重标题', () {
      expect(kotlinScreen, contains('LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)'));
      expect(kotlinScreen, contains('llp(dp(28), dp(28), 12)'));
    });

    test('注释记录 layoutWeight 与安卓权重语义不同', () {
      expect(view, contains('`layoutWeight` 与安卓 `LinearLayout` 权重语义不同'));
    });
  });

  group('② 占位层只在视频区（不再盖住资源面板）', () {
    test('占位层在 Flex 的视频子节点内（用 Stack 包住 VideoStack）', () {
      // 定位**分栏** Flex（含 direction 三元），不是头部那个 Flex。
      final flexIdx = view.indexOf('Flex({\n        direction: this.portrait ? FlexDirection.Column');
      expect(flexIdx, greaterThan(0));
      final body = view.substring(flexIdx, flexIdx + 2000);
      // 视频子节点用 Stack 包住 VideoStack + 占位层。
      expect(body, contains('Stack() {'));
      expect(body, contains('this.VideoStack();'));
      expect(body, contains('if (!this.playerReady) {'));
      // Stack 是 Flex 的弹性子节点。
      expect(body, contains('.layoutWeight(1);'));
    });

    test('占位层仍有黑底 + 文案 + 不抢手势', () {
      final idx = view.indexOf('if (!this.playerReady) {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 900);
      expect(body, contains('.backgroundColor(Color.Black)'));
      expect(body, contains('请从资源面板选择要播放的内容'));
      expect(body, contains('.hitTestBehavior(HitTestMode.None)'));
    });

    test('根 Stack 里不再有独立的占位层（只有 Flex 内那一处）', () {
      // 全文件只应出现一次 `if (!this.playerReady)`。
      expect(
        RegExp(r'if \(!this\.playerReady\) \{').allMatches(view).length,
        1,
      );
    });

    test('注释记录面板整块黑色的根因', () {
      expect(view, contains('资源面板变整块黑色'));
    });
  });

  group('③ 安卓弹幕单层插值（对齐 Flutter）', () {
    test('614 起 setClock 只传 paused（位置由 positionProvider 现算）', () {
      // 614 对齐鸿蒙：弹幕层不自维护锚点，直接读宿主插值时钟。
      expect(kotlinScreen, contains('danmakuLayer.setClock(state.paused)'));
      expect(
        kotlinScreen,
        isNot(contains('danmakuLayer.setClock(state.positionMs')),
      );
    });

    test('注释记录双重插值根因', () {
      expect(kotlinScreen, contains('两层插值叠加'));
    });

    test('Flutter 参考实现（_lastPosition + 增量）', () {
      final flutter = File('lib/screens/player/widgets/danmaku_overlay.dart').readAsStringSync();
      expect(flutter, contains('_lastPosition + (_elapsed - _alignElapsed)'));
    });

    test('弹幕层改为读 positionProvider（不再自维护锚点）', () {
      final danmaku = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/DanmakuLayerView.kt',
      ).readAsStringSync();
      expect(danmaku, contains('private fun currentPositionMs(): Long = positionProvider()'));
    });
  });
}
