import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';

import '../helpers/test_fakes.dart';

void main() {
  Widget wrap(AppSettings settings, Widget child) {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [child]),
          body: const SizedBox(),
        ),
      ),
    );
  }

  Finder focusFinder() => find.byWidgetPredicate(
      (w) => w is Focus && w.focusNode?.debugLabel == 'TvAppBarIconButton');

  AnimatedContainer ringOf(WidgetTester tester) => tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(TvAppBarIconButton),
        matching: find.byType(AnimatedContainer),
      ));

  testWidgets('非 TV：渲染普通 IconButton 且点击生效、无自定义焦点节点',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(
      const AppSettings(tvMode: false),
      TvAppBarIconButton(
        icon: Icons.refresh,
        tooltip: '刷新',
        onPressed: () => taps++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsOneWidget);
    expect(focusFinder(), findsNothing);

    await tester.tap(find.byType(IconButton));
    expect(taps, 1);
  });

  testWidgets('TV：聚焦出现圆形焦点环，Enter 触发 onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(
      const AppSettings(tvMode: true),
      TvAppBarIconButton(
        icon: Icons.refresh,
        tooltip: '刷新',
        onPressed: () => taps++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(focusFinder(), findsOneWidget);
    // 未聚焦：无焦点环
    expect(ringOf(tester).foregroundDecoration, isNull);

    final node = tester.widget<Focus>(focusFinder()).focusNode!;
    node.requestFocus();
    await tester.pumpAndSettle();

    final deco = ringOf(tester).foregroundDecoration as BoxDecoration?;
    expect(deco, isNotNull, reason: '聚焦应绘制焦点环');
    expect(deco!.shape, BoxShape.circle);
    expect((deco.border as Border).top.width, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('TV：onPressed 为空时 Enter 不触发且无响应', (tester) async {
    await tester.pumpWidget(wrap(
      const AppSettings(tvMode: true),
      const TvAppBarIconButton(icon: Icons.refresh, tooltip: '刷新'),
    ));
    await tester.pumpAndSettle();

    final node = tester.widget<Focus>(focusFinder()).focusNode!;
    node.requestFocus();
    await tester.pump();
    // 无异常即通过
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  });
}
