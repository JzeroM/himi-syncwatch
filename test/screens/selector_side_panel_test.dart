import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/speed_menu_panel.dart';

import '../helpers/test_fakes.dart';

Widget _host(Widget child, {double height = 400, double width = 300}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('SelectorSidePanel 右侧玻璃浮层', () {
    testWidgets('标题渲染', (tester) async {
      await tester.pumpWidget(_host(const SelectorSidePanel(
        title: '字幕',
        child: SizedBox.shrink(),
      )));
      expect(find.text('字幕'), findsOneWidget);
    });

    testWidgets('音轨/倍速标题可切换（不同实例渲染各自标题）', (tester) async {
      await tester.pumpWidget(_host(const SelectorSidePanel(
        title: '倍速',
        child: SizedBox.shrink(),
      )));
      expect(find.text('倍速'), findsOneWidget);
      expect(find.text('字幕'), findsNothing);
    });

    testWidgets('选项行选中右侧对勾、未选中无对勾', (tester) async {
      await tester.pumpWidget(_host(SelectorSidePanel(
        title: '音轨',
        child: Column(
          children: [
            SideOptionRow(label: '国语', selected: true, onTap: () {}),
            SideOptionRow(label: '英语', selected: false, onTap: () {}),
          ],
        ),
      )));
      // 对勾行 = 国语行内
      final checks = find.byIcon(Icons.check);
      expect(checks, findsOneWidget);
      final row = tester.widget<Row>(
        find.ancestor(
          of: find.byIcon(Icons.check),
          matching: find.byType(Row),
        ),
      );
      expect(row.children.first, isA<Expanded>());
    });

    testWidgets('点选项行触发回调', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(SelectorSidePanel(
        title: '字幕',
        child: Column(
          children: [
            SideOptionRow(
              label: '关闭字幕',
              selected: false,
              onTap: () => tapped = true,
            ),
          ],
        ),
      )));
      await tester.tap(find.text('关闭字幕'));
      expect(tapped, isTrue);
    });

    testWidgets('倍速面板矮容器下 8 档可滚动到达（回归：Column 裁剪）', (tester) async {
      await tester.pumpWidget(_host(
        SelectorSidePanel(
          title: '倍速',
          child: SpeedMenuPanel(current: 1.0, onSelected: (_) {}),
        ),
        // 200px 高度只够显示约 4 档：剩余档位必须靠滚动可达
        height: 200,
      ));

      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(list.position.maxScrollExtent, greaterThan(0),
          reason: '内容高于面板必须可滚动');
      // ListView 懒构建：初始只有前几档在可视区
      expect(find.text('3.0x'), findsNothing);

      await tester.drag(find.text('0.5x'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('3.0x'), findsOneWidget, reason: '滚到底后 3.0x 构建并进入可视区');
      expect(tester.getRect(find.text('3.0x').last).bottom, lessThan(200),
          reason: '在面板可视范围内');
      expect(tester.takeException(), isNull);
    });

    testWidgets('mouse 拖动可滚（桌面端根因回归：默认拖动设备无 mouse）', (tester) async {
      await tester.pumpWidget(_host(
        SelectorSidePanel(
          title: '倍速',
          child: SpeedMenuPanel(current: 1.0, onSelected: (_) {}),
        ),
        height: 200,
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('0.5x')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -60));
      await gesture.moveBy(const Offset(0, -60));
      await gesture.moveBy(const Offset(0, -60));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0),
        reason: '鼠标按下拖动应滚动面板',
      );
    });
  });

  group('SpeedMenuPanel 行样式（右勾替代左 radio）', () {
    testWidgets('选中档右侧对勾，无 radio 图标', (tester) async {
      await tester.pumpWidget(_host(
        SelectorSidePanel(
          title: '倍速',
          child: SpeedMenuPanel(current: 1.5, onSelected: (_) {}),
        ),
      ));
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      // 8 档全部渲染
      for (final s in SpeedMenuPanel.speedOptions) {
        expect(find.text(SpeedMenuPanel.formatSpeedLabel(s)), findsOneWidget);
      }
    });
  });
}
