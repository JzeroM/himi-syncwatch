import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/stats_panel.dart';

import '../helpers/test_fakes.dart';

Widget _wrap(Widget child, AppSettings settings) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  const counts = MediaCounts(movies: 2565, series: 2415, episodes: 73462);

  testWidgets('横排展示电影/电视剧/集三个数字与标签', (tester) async {
    await tester.pumpWidget(_wrap(const StatsPanel(key: ValueKey('statsPanel'), counts: counts), const AppSettings()));

    expect(find.byKey(const ValueKey('statsPanel')), findsOneWidget);
    expect(find.text('2565'), findsOneWidget);
    expect(find.text('2415'), findsOneWidget);
    expect(find.text('73462'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('集'), findsOneWidget);

    // 三张卡片横排（左 → 右：电影 → 电视剧 → 集）
    expect(find.byType(GlassContainer), findsNWidgets(3));
    final movies = tester.getTopLeft(find.text('2565'));
    final series = tester.getTopLeft(find.text('2415'));
    final episodes = tester.getTopLeft(find.text('73462'));
    expect(movies.dx, lessThan(series.dx));
    expect(series.dx, lessThan(episodes.dx));

    // 卡片扁平：整体高度明显小于 80
    final card = tester.getRect(find.byType(GlassContainer).first);
    expect(card.height, lessThan(80));
  });

  testWidgets('设置了主题色时数字使用主题色', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StatsPanel(key: ValueKey('statsPanel'), counts: counts),
        const AppSettings(themeColor: 0xFF2DD4BF),
      ),
    );

    expect(
      tester.widget<Text>(find.text('2565')).style?.color,
      const Color(0xFF2DD4BF),
    );
  });

  testWidgets('未设置主题色时数字使用主题默认色', (tester) async {
    await tester.pumpWidget(_wrap(const StatsPanel(key: ValueKey('statsPanel'), counts: counts), const AppSettings()));

    final color = tester.widget<Text>(find.text('2565')).style?.color;
    expect(color, isNotNull);
  });
}
