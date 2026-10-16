import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/hover_scroll_row.dart';

Widget _host({int count = 20, double rowWidth = 300, double? anchor}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: rowWidth,
            height: 120,
            child: HoverScrollRow(
              height: 120,
              arrowAnchorHeight: anchor,
              itemCount: count,
              itemBuilder: (context, index) => SizedBox(
                width: 100,
                height: 110,
                child: ColoredBox(
                  color: Colors.blue,
                  child: Text('item$index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<TestGesture> _hover(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(find.byType(HoverScrollRow)));
  await tester.pump();
  return gesture;
}

const _left = ValueKey('scrollArrowLeft');
const _right = ValueKey('scrollArrowRight');

void main() {
  testWidgets('未悬停 → 无箭头', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.byKey(_left), findsNothing);
    expect(find.byKey(_right), findsNothing);
  });

  testWidgets('悬停在最左 → 只显示右箭头', (tester) async {
    await tester.pumpWidget(_host());
    await _hover(tester);
    expect(find.byKey(_left), findsNothing);
    expect(find.byKey(_right), findsOneWidget);
  });

  testWidgets('悬停中间 → 两边都显示；点箭头可滚动', (tester) async {
    await tester.pumpWidget(_host());
    await _hover(tester);

    await tester.tap(find.byKey(_right));
    await tester.pumpAndSettle();

    expect(find.byKey(_left), findsOneWidget);
    expect(find.byKey(_right), findsOneWidget);
  });

  testWidgets('滚到最右 → 只显示左箭头', (tester) async {
    await tester.pumpWidget(_host());
    await _hover(tester);

    for (var i = 0; i < 12; i++) {
      final right = find.byKey(_right);
      if (right.evaluate().isEmpty) break;
      await tester.tap(right);
      await tester.pumpAndSettle();
    }

    expect(find.byKey(_left), findsOneWidget);
    expect(find.byKey(_right), findsNothing);
  });

  testWidgets('内容不足一屏 → 悬停也不显示箭头', (tester) async {
    await tester.pumpWidget(_host(count: 2));
    await _hover(tester);
    expect(find.byKey(_left), findsNothing);
    expect(find.byKey(_right), findsNothing);
  });

  testWidgets('移出后箭头隐藏', (tester) async {
    await tester.pumpWidget(_host());
    final gesture = await _hover(tester);
    expect(find.byKey(_right), findsOneWidget);

    await gesture.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(find.byKey(_left), findsNothing);
    expect(find.byKey(_right), findsNothing);
  });

  testWidgets('外部 controller：复用且由持有者管理（箭头驱动其滚动）', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 120,
            child: HoverScrollRow(
              height: 120,
              controller: controller,
              itemCount: 20,
              itemBuilder: (context, index) => SizedBox(
                width: 100,
                height: 110,
                child: ColoredBox(
                  color: Colors.blue,
                  child: Text('item$index'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(controller.hasClients, isTrue, reason: '外部 controller 应被接入');
    await _hover(tester);
    expect(find.byKey(_right), findsOneWidget);

    final before = controller.offset;
    await tester.tap(find.byKey(_right));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(before),
        reason: '点箭头应通过外部 controller 滚动');
  });

  testWidgets('不传 arrowAnchorHeight → 箭头垂直居中于整行', (tester) async {
    await tester.pumpWidget(_host());
    await _hover(tester);

    final rowTop = tester.getTopLeft(find.byType(HoverScrollRow)).dy;
    final arrowCenter = tester.getCenter(find.byKey(_right)).dy;
    expect(arrowCenter - rowTop, closeTo(60, 0.5),
        reason: '默认锚定行高 120 → 中心 60');
  });

  testWidgets('传 arrowAnchorHeight → 箭头垂直居中于图区', (tester) async {
    await tester.pumpWidget(_host(anchor: 80));
    await _hover(tester);

    final rowTop = tester.getTopLeft(find.byType(HoverScrollRow)).dy;
    final arrowCenter = tester.getCenter(find.byKey(_right)).dy;
    expect(arrowCenter - rowTop, closeTo(40, 0.5),
        reason: '图区高 80 → 箭头中心 40（不再偏低到行中心 60）');
  });
}
