import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  AppSettings initial = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(initial)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _glassSwitch(WidgetTester tester) {
  return find.descendant(
    of: find.ancestor(
      of: find.text('液态玻璃'),
      matching: find.byType(SwitchListTile),
    ),
    matching: find.byType(Switch),
  );
}

void main() {
  Future<void> _scrollToGlass(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('液态玻璃'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置页展示液态玻璃开关（默认开）', (tester) async {
    final container = await _pumpScreen(tester);
    await _scrollToGlass(tester);

    expect(find.text('液态玻璃'), findsOneWidget);
    expect(
      find.text('毛玻璃模糊与高光效果，低端设备可关闭以提升流畅度'),
      findsOneWidget,
    );
    expect(container.read(settingsProvider).glassUi, isTrue);
    expect(tester.widget<Switch>(_glassSwitch(tester)).value, isTrue);
  });

  testWidgets('切换开关后 glassUi 变为 false', (tester) async {
    final container = await _pumpScreen(tester);
    await _scrollToGlass(tester);

    await tester.tap(_glassSwitch(tester));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).glassUi, isFalse);
  });

  testWidgets('再次切换恢复开启', (tester) async {
    final container =
        await _pumpScreen(tester, initial: const AppSettings(glassUi: false));
    await _scrollToGlass(tester);

    expect(tester.widget<Switch>(_glassSwitch(tester)).value, isFalse);

    await tester.tap(_glassSwitch(tester));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).glassUi, isTrue);
  });

  testWidgets('展示主题色分节（标题+默认块+12色块+预览+三滑块）', (tester) async {
    final container = await _pumpScreen(tester);

    expect(find.text('主题色'), findsOneWidget);
    expect(find.byKey(const ValueKey('themeColorDefault')), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      expect(find.byKey(ValueKey('themeColorBlock_$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('themeColorPreview')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeHueSlider')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeSatSlider')), findsOneWidget);
    expect(find.byKey(const ValueKey('themeValSlider')), findsOneWidget);

    // 缺省：默认底色，选中默认块
    expect(container.read(settingsProvider).themeColor, isNull);
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('themeColorPreview')),
    );
    final box = preview.decoration as BoxDecoration;
    final gradient = box.gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    // 默认（accent null）时三段同色 = 应用底色
    expect(gradient.colors.toSet(), hasLength(1));
  });

  testWidgets('点击预设色块写入 themeColor', (tester) async {
    final container = await _pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('themeColorBlock_0')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).themeColor, equals(0xFF6366F1));

    // 预览变为主题色三段渐变（首段为压暗后的主题色）
    final preview = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('themeColorPreview')),
    );
    final gradient =
        (preview.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors, hasLength(3));
    expect(gradient.colors.toSet().length, 3);
  });

  testWidgets('初始选中色块后点击默认清空 themeColor', (tester) async {
    final container = await _pumpScreen(
      tester,
      initial: const AppSettings(themeColor: 0xFF22D3EE),
    );

    expect(container.read(settingsProvider).themeColor, equals(0xFF22D3EE));

    await tester.tap(find.byKey(const ValueKey('themeColorDefault')));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).themeColor, isNull);
  });

  testWidgets('拖动色相滑块写入主题色', (tester) async {
    final container = await _pumpScreen(tester);

    // 滑块初始已在视口内，直接拖动（ensureVisible 会把它顶到 AppBar 下被遮挡）
    final slider = find.byKey(const ValueKey('themeHueSlider'));
    expect(tester.getCenter(slider).dy, greaterThan(56));
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();

    final color = container.read(settingsProvider).themeColor;
    expect(color, isNotNull);
    expect(color, isNot(equals(0xFF6366F1)));
  });

  testWidgets('音频后端默认为 AudioTrack', (tester) async {
    final container = await _pumpScreen(tester);

    expect(find.text('音频后端'), findsOneWidget);
    expect(
      find.text('AudioTrack：兼容性最好的传统后端（默认）'),
      findsOneWidget,
    );
    expect(container.read(settingsProvider).audioRenderer, 'AudioTrack');
  });
}
