import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

import '../helpers/test_fakes.dart';

void main() {
  test('settingsFadeRoute 使用淡入淡出路由（PageRouteBuilder）', () {
    final route = settingsFadeRoute<void>((_) => const SizedBox());
    expect(route, isA<PageRouteBuilder<void>>());
  });

  testWidgets('SettingsPageBackground 渲染主题色三段渐变且不透明', (tester) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) =>
              FakeSettingsNotifier(const AppSettings(themeColor: 0xFF6366F1)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const SettingsPageBackground(
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.widget<DecoratedBox>(find.descendant(
      of: find.byType(SettingsPageBackground),
      matching: find.byType(DecoratedBox),
    ));
    final gradient =
        (box.decoration as BoxDecoration).gradient as LinearGradient?;
    expect(gradient, isNotNull);
    expect(gradient!.colors, hasLength(3), reason: '主题色三段渐变');
  });
}
