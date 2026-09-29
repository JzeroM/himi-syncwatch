import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

Future<void> _pumpNav(
  WidgetTester tester, {
  int initial = 0,
  required ValueChanged<int> onSelect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 800,
            child: ShellNavBar(currentIndex: initial, onSelect: onSelect),
          ),
        ),
      ),
    ),
  );
}

Positioned _blob(WidgetTester tester) {
  return tester.widget<Positioned>(
    find.ancestor(
      of: find.byKey(const ValueKey('navBlob')),
      matching: find.byType(Positioned),
    ),
  );
}

void main() {
  testWidgets('四格 icon+label 组在 60 高度内严格对齐且整体垂直居中', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final navBox = tester.renderObject<RenderBox>(find.byType(ShellNavBar));
    expect(navBox.size.height, 60);
    final navTop = navBox.localToGlobal(Offset.zero).dy;

    double centerY(Finder f) {
      final box = tester.renderObject<RenderBox>(f);
      final c = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
      return c.dy - navTop;
    }

    // 四格 icon 中线一致（修复 NavigationBar 选中/未选中错位问题）
    final iconCenters = [
      centerY(find.byIcon(Icons.home)),
      centerY(find.byIcon(Icons.dns_outlined)),
      centerY(find.byIcon(Icons.key_outlined)),
      centerY(find.byIcon(Icons.settings_outlined)),
    ];
    expect(iconCenters.toSet().length, 1);

    // 四格 label 中线一致
    final labelCenters = [
      centerY(find.text('首页')),
      centerY(find.text('Emby服务器')),
      centerY(find.text('声网配置')),
      centerY(find.text('设置')),
    ];
    expect(labelCenters.toSet().length, 1);

    // icon+label 组块整体垂直居中于 60 高
    final iconTop = tester
            .renderObject<RenderBox>(find.byIcon(Icons.home))
            .localToGlobal(Offset.zero)
            .dy -
        navTop;
    final labelBox = tester.renderObject<RenderBox>(find.text('首页'));
    final labelBottom = labelBox.localToGlobal(Offset.zero).dy +
        labelBox.size.height -
        navTop;
    expect((iconTop + labelBottom) / 2, closeTo(30, 1.0));
  });

  testWidgets('初始水珠位于首格中心', (tester) async {
    await _pumpNav(tester, onSelect: (_) {});

    final pos = _blob(tester);
    expect(pos.left, closeTo(0, 0.01));
    expect(pos.width, closeTo(200, 0.01));
  });

  testWidgets('点击切换标签，水珠平滑移到目标格中心', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(selected, 3);
    final pos = _blob(tester);
    expect(pos.left, closeTo(600, 0.5));
    expect(pos.width, closeTo(200, 0.5));
  });

  testWidgets('长按拖动水珠跟手并拉伸，松手落点才切换', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    // 长按第一格进入拖动
    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(selected, isNull); // 长按本身不切换

    // 拖到第二格：水珠中心跟手、宽度拉伸
    await gesture.moveTo(Offset(nav.left + 300, nav.center.dy));
    await tester.pump();

    final dragging = _blob(tester);
    expect(dragging.left, closeTo(300 - dragging.width! / 2, 1));
    expect(dragging.width, greaterThan(200));
    expect(selected, isNull); // 拖动中途不切换（松手落点才切）

    // 拖到第三格中部松手 → 落点切换
    await gesture.moveTo(Offset(nav.left + 490, nav.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, 2);

    // 水珠回弹到第三格中心（left = 0.625*800 - 200/2 = 400）并收窄
    final settled = _blob(tester);
    expect(settled.left, closeTo(400, 0.5));
    expect(settled.width, closeTo(200, 0.5));
  });

  testWidgets('长按拖动后松手在原格，不切换', (tester) async {
    int? selected;
    await _pumpNav(tester, onSelect: (i) => selected = i);
    final nav = tester.getRect(find.byType(ShellNavBar));

    final gesture = await tester.startGesture(
      Offset(nav.left + 100, nav.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(Offset(nav.left + 140, nav.center.dy));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(selected, isNull);
    final settled = _blob(tester);
    expect(settled.left, closeTo(0, 0.5));
    expect(settled.width, closeTo(200, 0.5));
  });
}
