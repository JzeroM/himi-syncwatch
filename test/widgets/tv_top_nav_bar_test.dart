import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/shell/tv_top_nav_bar.dart';

import '../helpers/test_fakes.dart';

Widget _host({int index = 0, ValueChanged<int>? onSelect}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TvTopNavBar(
          currentIndex: index,
          onSelect: onSelect ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('渲染标题与四个横排导航项', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('HIMI'), findsOneWidget);
    expect(find.text('同步观影'), findsOneWidget);
    for (final label in kShellNavLabels) {
      expect(find.text(label), findsOneWidget);
    }
    // 首页选中：实心图标显示、线框图标隐藏
    expect(find.byIcon(kShellNavSelectedIcons[0]), findsOneWidget);
    expect(find.byIcon(kShellNavIcons[0]), findsNothing);
  });

  testWidgets('点击导航项回调 onSelect', (tester) async {
    int? selected;
    await tester.pumpWidget(_host(onSelect: (i) => selected = i));
    await tester.pump();

    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(selected, 3);

    await tester.tap(find.text('声网配置'));
    await tester.pump();
    expect(selected, 2);
  });

  testWidgets('选中项使用实心图标与高亮色，非选中为线框图标', (tester) async {
    await tester.pumpWidget(_host(index: 2));
    await tester.pump();

    // currentIndex=2：声网配置选中（实心 key 图标），首页回退线框
    expect(find.byIcon(kShellNavSelectedIcons[2]), findsOneWidget);
    expect(find.byIcon(kShellNavIcons[0]), findsOneWidget);
    expect(find.byIcon(kShellNavSelectedIcons[0]), findsNothing);
  });
}
