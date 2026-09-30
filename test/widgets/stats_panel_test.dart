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

  Widget panel({AppSettings settings = const AppSettings()}) => _wrap(
        const StatsPanel(key: ValueKey('statsPanel'), counts: counts),
        settings,
      );

  testWidgets('横排展示电影/电视剧/集三个数字与标签', (tester) async {
    await tester.pumpWidget(panel());

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

  testWidgets('数字为白色，标签下方三色点缀条各归其位', (tester) async {
    await tester.pumpWidget(panel());

    // 数字纯白（不使用渐变/主题色）
    for (final text in ['2565', '2415', '73462']) {
      final t = tester.widget<Text>(find.text(text));
      expect(t.style?.color, Colors.white);
    }

    // 三条点缀条：青绿 / 琥珀 / 紫罗兰
    final bars = {
      'statBar_电影': const Color(0xFF2DD4BF),
      'statBar_电视剧': const Color(0xFFFBBF24),
      'statBar_集': const Color(0xFFA78BFA),
    };
    for (final entry in bars.entries) {
      final bar = find.byKey(ValueKey(entry.key));
      expect(bar, findsOneWidget);
      final box = tester.widget<Container>(bar);
      expect(box.decoration, isA<BoxDecoration>());
      expect((box.decoration as BoxDecoration).color, entry.value);
      expect(tester.getSize(bar).height, 3);
    }

    // 色条在对应标签下方
    for (final label in ['电影', '电视剧', '集']) {
      final bar = find.byKey(ValueKey('statBar_$label'));
      expect(
        tester.getTopLeft(bar).dy,
        greaterThanOrEqualTo(tester.getBottomRight(find.text(label)).dy),
      );
    }
  });
}
