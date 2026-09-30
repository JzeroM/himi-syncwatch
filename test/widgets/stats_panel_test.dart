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

  group('buildRainbowStripeGradient 彩虹条纹', () {
    test('七色、14 个 stop、相邻同色形成硬边条纹', () {
      final g = buildRainbowStripeGradient();

      expect(g.colors, hasLength(14));
      expect(g.stops, hasLength(14));

      // 七个色段，每色连续出现两次（硬边突变而非平滑过渡）
      final uniqueColors = <Color>{};
      for (var i = 0; i < g.colors.length; i += 2) {
        expect(g.colors[i], g.colors[i + 1]);
        uniqueColors.add(g.colors[i]);
      }
      expect(uniqueColors, hasLength(7));

      // stops 成对重复：[..., a, a, b, b, ...]
      for (var i = 1; i < g.stops!.length - 1; i += 2) {
        expect(g.stops![i], g.stops![i + 1]);
      }
      expect(g.stops!.first, 0);
      expect(g.stops!.last, 1);

      // 横向：左 → 右
      expect(g.begin, Alignment.centerLeft);
      expect(g.end, Alignment.centerRight);
    });
  });

  testWidgets('横排展示电影/电视剧/集三个数字与标签', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StatsPanel(key: ValueKey('statsPanel'), counts: counts),
        const AppSettings(),
      ),
    );

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

  testWidgets('每个数字由 ShaderMask 条纹着色（srcIn + 白色底字）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const StatsPanel(key: ValueKey('statsPanel'), counts: counts),
        const AppSettings(),
      ),
    );

    final masks = find.byType(ShaderMask);
    expect(masks, findsNWidgets(3));
    for (final mask in tester.widgetList<ShaderMask>(masks)) {
      expect(mask.blendMode, BlendMode.srcIn);
    }

    // 数字本体为白色（由条纹 shader 着色）
    for (final text in ['2565', '2415', '73462']) {
      final t = tester.widget<Text>(find.text(text));
      expect(t.style?.color, Colors.white);
    }
  });
}
