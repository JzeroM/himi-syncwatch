import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';

import '../helpers/test_fakes.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 122, child: child),
          ),
        ),
      ),
    );

MediaItem _item({
  String name = '测试影片',
  String? year = '2026',
  double? communityRating,
  int? indexNumber,
}) =>
    MediaItem(
      id: 'm1',
      name: name,
      type: 'Movie',
      posterUrl: '',
      year: year,
      communityRating: communityRating,
      indexNumber: indexNumber,
    );

void main() {
  group('PosterCard', () {
    test('heightFor 为 1.5 倍宽 + 文字区预留', () {
      expect(
        PosterCard.heightFor(122),
        122 * 1.5 + PosterCard.textReservedHeight,
      );
    });

    testWidgets('海报完整 2:3，标题与年份在海报下方且不套 Card 黑底', (tester) async {
      await tester.pumpWidget(_wrap(PosterCard(item: _item(), width: 122)));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);

      final poster = tester.getRect(find.byType(EmbyImage));
      final title = tester.getRect(find.text('测试影片'));
      final year = tester.getRect(find.text('2026'));

      expect(poster.width, closeTo(122, 0.5));
      expect(poster.height, closeTo(122 * 1.5, 0.5));
      expect(title.top, greaterThanOrEqualTo(poster.bottom));
      expect(year.top, greaterThanOrEqualTo(title.bottom));
    });

    testWidgets('有评分与集数时在海报右下、左上显示角标', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PosterCard(
            item: _item(communityRating: 8.5, indexNumber: 12),
            width: 122,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rating = tester.getRect(find.text('8.5'));
      final index = tester.getRect(find.text('12'));
      final poster = tester.getRect(find.byType(EmbyImage));

      // 评分在海报内右下角
      expect(rating.bottom, lessThanOrEqualTo(poster.bottom));
      expect(rating.right, lessThanOrEqualTo(poster.right));
      expect(rating.top, greaterThan(poster.center.dy));
      // 集数在海报内左上角
      expect(index.top, greaterThanOrEqualTo(poster.top));
      expect(index.left, greaterThanOrEqualTo(poster.left));
      expect(index.bottom, lessThan(poster.center.dy));
      // 星标存在
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('无评分与集数时不渲染角标', (tester) async {
      await tester.pumpWidget(_wrap(PosterCard(item: _item(), width: 122)));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.text('8.5'), findsNothing);
      expect(find.text('12'), findsNothing);
    });

    testWidgets('无年份时只显示标题', (tester) async {
      await tester.pumpWidget(
        _wrap(PosterCard(item: _item(year: null), width: 122)),
      );
      await tester.pumpAndSettle();

      expect(find.text('测试影片'), findsOneWidget);
      // 年份缺失不报错，文字区不溢出
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击触发 onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          PosterCard(
            item: _item(),
            width: 122,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('测试影片'));
      expect(tapped, isTrue);
    });

    testWidgets('海报按显示宽×dpr 传入 cacheWidth（避免全尺寸解码）', (tester) async {
      await tester.pumpWidget(_wrap(PosterCard(item: _item(), width: 122)));
      await tester.pumpAndSettle();

      final img = tester.widget<EmbyImage>(find.byType(EmbyImage));
      final dpr = MediaQuery.devicePixelRatioOf(
        tester.element(find.byType(PosterCard)),
      );
      expect(img.cacheWidth, (122 * dpr).round());
      expect(img.cacheWidth, isNotNull);
    });
  });
}
