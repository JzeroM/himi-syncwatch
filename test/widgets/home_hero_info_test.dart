import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';
import 'package:himi_syncwatch/widgets/dots_ellipsis_text.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';

/// 698：轮播底部信息块——简介 2 行省略号截断 + 多平台评分行。
void main() {
  HomeHeroItem item({String? overview, HeroRatingQuery? query}) => HomeHeroItem(
        title: '影片',
        overview: overview,
        ratingQuery: query,
      );

  Widget wrap(List<HomeHeroItem> items, {HeroRatingsSource? service}) {
    return MaterialApp(
      home: Scaffold(
        body: HomeHeroCarousel(
          items: items,
          controller: PageController(),
          height: 500,
          onPageChanged: (_) {},
          ratingsService: service,
        ),
      ),
    );
  }

  testWidgets('简介 2 行三点省略（698 N13：maxLines 2、居中、三点「...」）', (tester) async {
    await tester.pumpWidget(wrap([
      item(overview: '很长的简介' * 50),
    ]));

    final dots = tester.widget<DotsEllipsisText>(
      find.descendant(
        of: find.byType(HomeHeroCarousel),
        matching: find.byType(DotsEllipsisText),
      ),
    );
    expect(dots.maxLines, 2, reason: '简介最多显示 2 行');
    expect(dots.textAlign, TextAlign.center, reason: '简介居中');
    expect(DotsEllipsisText.dots, '...', reason: '三点省略号（非 …）');
  });

  testWidgets('空简介整块隐藏', (tester) async {
    await tester.pumpWidget(wrap([item(overview: null)]));
    // 无简介时底部块只剩标题文本（无 meta/徽章），简介文本不渲染。
    expect(find.text('影片'), findsOneWidget);
    expect(find.byType(DotsEllipsisText), findsNothing);

    await tester.pumpWidget(wrap([item(overview: '')]));
    expect(find.byType(DotsEllipsisText), findsNothing);
  });

  testWidgets('评分行随轮播渲染（有查询 + 服务时）', (tester) async {
    final service = _FakeSource(const [
      HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
      HeroRatingBadge(RatingPlatform.imdb, '7.6'),
      HeroRatingBadge(RatingPlatform.rottenTomatoesCritic, '69%'),
    ]);
    await tester.pumpWidget(wrap(
      [
        item(
          overview: '剧情简介',
          query: const HeroRatingQuery(
            imdbId: 'tt0133093',
            tmdbScore: 7.4,
          ),
        ),
      ],
      service: service,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('7.4'), findsOneWidget);
    expect(find.text('7.6'), findsOneWidget);
    expect(find.text('69%'), findsOneWidget);
  });

  testWidgets('无服务时不渲染徽章行（现状回退）', (tester) async {
    await tester.pumpWidget(wrap([
      item(
        overview: '剧情简介',
        query: const HeroRatingQuery(imdbId: 'tt0133093'),
      ),
    ]));
    await tester.pump();
    expect(find.text('7.4'), findsNothing);
  });
}

class _FakeSource implements HeroRatingsSource {
  _FakeSource(this.badges);

  final List<HeroRatingBadge> badges;

  @override
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query) async => badges;

  @override
  Stream<List<HeroRatingBadge>> watch(HeroRatingQuery query) async* {
    yield await fetch(query);
  }
}
