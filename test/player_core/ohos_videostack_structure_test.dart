import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 599：鸿蒙 VideoStack 单 Stack 重构（控件消失 + 点屏无反应根因）。
void main() {
  final ohosView = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  /// 取出 `VideoStack()` 这个 @Builder 的完整源码块。
  String videoStackBlock() {
    final start = ohosView.indexOf('  @Builder\n  VideoStack() {');
    expect(start, greaterThan(0), reason: '未找到 VideoStack @Builder');
    final end = ohosView.indexOf(
      '  /** 房间资源面板槽（593/594）：横屏右侧 320vp / 竖屏底部 280vp。 */',
      start,
    );
    expect(end, greaterThan(start));
    return ohosView.substring(start, end);
  }

  group('① VideoStack 只有一个顶层节点（Row 里不能有多个兄弟）', () {
    test('全文件仅一层手势层（590 的重复层已删）', () {
      // 590 引入时 Row 里已有一层手势、根 Stack 顶层又写一层完全等价的；
      // 594 把后者搬进 VideoStack → 同屏两个手势层抢触摸且被挤出屏外。
      expect(
        RegExp(r'GestureGroup\(GestureMode\.Parallel').allMatches(ohosView).length,
        1,
        reason: '只能保留一层手势层',
      );
    });

    test('全文件仅一个 XComponent', () {
      expect(RegExp(r'XComponent\(\{').allMatches(ohosView).length, 1);
    });

    test('VideoStack 内 XComponent 与手势层都在同一个 Stack 里', () {
      final block = videoStackBlock();
      // 顶层容器：Stack（不是裸的 XComponent + Column 平级）。
      expect(block, contains('Stack({ alignContent: Alignment.Top }) {'));
      final stackIdx = block.indexOf('Stack({ alignContent: Alignment.Top }) {');
      final xIdx = block.indexOf('XComponent({');
      final gestureIdx = block.indexOf('.gesture(');
      expect(xIdx, greaterThan(stackIdx));
      expect(gestureIdx, greaterThan(xIdx));
      // Stack 的收尾属性（分栏）必须在手势层之后。
      final layoutWeightIdx = block.indexOf('.layoutWeight(');
      expect(layoutWeightIdx, greaterThan(gestureIdx));
    });

    test('根 Stack 里没有第二个手势层', () {
      // VideoStack 之后到 build 结束不应再出现 `.gesture(` 挂全屏层。
      final vsEnd = ohosView.indexOf(
        '  /** 房间资源面板槽（593/594）：横屏右侧 320vp / 竖屏底部 280vp。 */',
      );
      final rest = ohosView.substring(vsEnd);
      expect(
        RegExp(r'GestureGroup\(GestureMode\.Parallel').allMatches(rest).length,
        0,
        reason: 'VideoStack 之外不得再有手势层',
      );
    });
  });

  group('② 分栏属性归属正确', () {
    test('layoutWeight / auto-width 挂在外层 Stack，不在 XComponent', () {
      final block = videoStackBlock();
      final xIdx = block.indexOf('XComponent({');
      // XComponent 的属性链到「手势层注释」为止（不含外层 Stack 的属性）。
      final xEnd = block.indexOf('// ── 手势层', xIdx);
      final xBody = block.substring(xIdx, xEnd);
      // 只检查**属性行**（注释里会提到 layoutWeight 这个词，不能误判）。
      final attrLines = xBody
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(attrLines, contains(".width('100%')"));
      expect(attrLines, contains(".height('100%')"));
      expect(attrLines, isNot(contains('layoutWeight')));
      expect(attrLines, isNot(contains("this.roomPanelVisible() ? 'auto'")));
      // 分栏属性出现在 XComponent 段之后（属于外层 Stack）。
      expect(block.lastIndexOf('.layoutWeight('), greaterThan(xEnd));
    });

    test('竖屏/横屏分支都调用同一个 VideoStack', () {
      expect(ohosView, contains('this.VideoStack();'));
      // 竖屏 Column 与横屏 Row 各调用一次（注释里的示例行不算）。
      final calls = ohosView
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('this.VideoStack();'))
          .length;
      expect(calls, 2);
    });
  });

  group('③ 586 画质回归防护（surface 尺寸仍按 vp2px）', () {
    test('onAreaChange 挂在 XComponent 自己身上', () {
      final block = videoStackBlock();
      final xIdx = block.indexOf('XComponent({');
      final gestureIdx = block.indexOf('Column()');
      final areaIdx = block.indexOf('.onAreaChange(', xIdx);
      // 必须在 XComponent 段内、手势层之前（挂外层 Stack 会拿到错误尺寸）。
      expect(areaIdx, greaterThan(xIdx));
      expect(areaIdx, lessThan(gestureIdx));
    });

    test('vpx 换算与 surfaceChanged 调用不变', () {
      final block = videoStackBlock();
      expect(block, contains('this.getUIContext().vp2px(wVp)'));
      expect(block, contains('this.getUIContext().vp2px(hVp)'));
      expect(block, contains("surfaceChanged('', wPx, hPx)"));
      expect(block, isNot(contains("surfaceChanged('', Math.trunc(w)")));
    });
  });

  group('④ 手势层命中语义不变', () {
    test('保留 hitTestBehavior(Default)', () {
      // Transparent 会与控件同时进入手势竞技场 → 控件 onClick 失效。
      expect(ohosView, contains('.hitTestBehavior(HitTestMode.Default);'));
    });

    test('四种手势齐全', () {
      final block = videoStackBlock();
      expect(block, contains('TapGesture({ count: 1 })'));
      expect(block, contains('TapGesture({ count: 2 })'));
      expect(block, contains('PanGesture({ direction: PanDirection.All })'));
      expect(block, contains('LongPressGesture({ repeat: false })'));
    });
  });

  group('⑤ 598 的鸿蒙回滚仍然保持', () {
    test('不含 .translate', () {
      expect(ohosView, isNot(contains('.translate(')));
    });

    test('不含 bottomInset', () {
      expect(ohosView, isNot(contains('bottomInset')));
    });
  });
}
