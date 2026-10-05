import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/widgets/speed_menu_panel.dart';

import '../helpers/test_fakes.dart';

Widget _host(Widget child) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
    ],
  );
  addTearDown(container.dispose);
  // TvFocusable 是 ConsumerWidget（读 tvMode provider）
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('SpeedMenuPanel 档位', () {
    test('B 组 8 档：0.5~3.0', () {
      expect(SpeedMenuPanel.speedOptions, [
        0.5,
        0.75,
        1.0,
        1.25,
        1.5,
        2.0,
        2.5,
        3.0,
      ]);
    });

    test('formatSpeedLabel：1.0 → 1.0x；0.75 → 0.75x', () {
      expect(SpeedMenuPanel.formatSpeedLabel(1.0), '1.0x');
      expect(SpeedMenuPanel.formatSpeedLabel(0.75), '0.75x');
      expect(SpeedMenuPanel.formatSpeedLabel(3.0), '3.0x');
    });
  });

  group('SpeedMenuPanel 渲染', () {
    testWidgets('渲染全部 8 档文本', (tester) async {
      await tester.pumpWidget(_host(SpeedMenuPanel(
        current: 1.0,
        onSelected: (_) {},
      )));
      for (final s in SpeedMenuPanel.speedOptions) {
        expect(find.text(SpeedMenuPanel.formatSpeedLabel(s)), findsOneWidget);
      }
    });

    testWidgets('当前档高亮（仅一格 checked 且落在 1.5）', (tester) async {
      await tester.pumpWidget(_host(SpeedMenuPanel(
        current: 1.5,
        onSelected: (_) {},
      )));
      final checked = tester
          .widgetList<Icon>(find.byIcon(Icons.radio_button_checked))
          .toList();
      expect(checked, hasLength(1));
      final rows = find.descendant(
        of: find.byType(SpeedMenuPanel),
        matching: find.text('1.5x'),
      );
      expect(rows, findsOneWidget);
    });

    testWidgets('点档回调所选倍速', (tester) async {
      double? picked;
      await tester.pumpWidget(_host(SpeedMenuPanel(
        current: 1.0,
        onSelected: (v) => picked = v,
      )));
      await tester.tap(find.text('2.5x'));
      expect(picked, 2.5);
    });
  });
}
