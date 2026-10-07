import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_context_menu.dart';

import '../helpers/test_fakes.dart';

Widget _host(VoidCallback onAction) {
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
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showGlassContextMenu(
                context,
                anchor: const Rect.fromLTWH(80, 120, 100, 120),
                actions: [
                  GlassMenuAction(
                    icon: Icons.favorite_border,
                    label: '收藏',
                    onTap: onAction,
                  ),
                  GlassMenuAction(
                    icon: Icons.visibility_off_outlined,
                    label: '未观看',
                    onTap: () {},
                  ),
                  GlassMenuAction(
                    icon: Icons.visibility_outlined,
                    label: '已观看',
                    onTap: () {},
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('展示全部选项；点选项执行回调并关闭', (tester) async {
    var fired = 0;
    await tester.pumpWidget(_host(() => fired++));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('未观看'), findsOneWidget);
    expect(find.text('已观看'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();

    expect(fired, 1);
    expect(find.text('未观看'), findsNothing, reason: '选择后菜单关闭');
  });

  testWidgets('点外部关闭', (tester) async {
    await tester.pumpWidget(_host(() {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsNothing);
  });
}
