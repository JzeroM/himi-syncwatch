import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/swipe_reveal_action.dart';

void main() {
  Widget wrap({
    required VoidCallback onAction,
    bool enabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: SwipeRevealAction(
              actionLabel: '取消配对',
              onAction: onAction,
              enabled: enabled,
              child: Container(
                height: 64,
                color: Colors.blue,
                alignment: Alignment.center,
                child: const Text('设备行'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('左滑露出操作区后可点按触发', (tester) async {
    var acted = 0;
    await tester.pumpWidget(wrap(onAction: () => acted++));

    await tester.drag(
        find.byType(SwipeRevealAction), const Offset(-200, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消配对'));
    await tester.pumpAndSettle();
    expect(acted, 1);
  });

  testWidgets('小幅拖动未过阈值回弹：操作区被前景遮挡不可点', (tester) async {
    var acted = 0;
    await tester.pumpWidget(wrap(onAction: () => acted++));

    await tester.drag(find.byType(SwipeRevealAction), const Offset(-8, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消配对'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(acted, 0, reason: '未过阈值回弹后操作区应被前景覆盖');
  });

  testWidgets('露出后点前景关闭：操作区再次被遮挡', (tester) async {
    var acted = 0;
    await tester.pumpWidget(wrap(onAction: () => acted++));

    await tester.drag(
        find.byType(SwipeRevealAction), const Offset(-200, 0));
    await tester.pumpAndSettle();

    // 点前景行 → 关闭
    await tester.tap(find.text('设备行'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消配对'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(acted, 0, reason: '关闭后操作区应再次被前景覆盖');
  });

  testWidgets('enabled=false 直接透传 child，无滑动行为', (tester) async {
    var acted = 0;
    await tester.pumpWidget(wrap(onAction: () => acted++, enabled: false));

    // 关闭时完全不渲染操作区
    expect(find.text('取消配对'), findsNothing);

    await tester.drag(
        find.byType(SwipeRevealAction), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(acted, 0);
  });
}
