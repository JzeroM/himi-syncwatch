import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';
import 'package:himi_syncwatch/widgets/ratings_badge_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      );

  group('RatingsBadgeRow（698 徽章行）', () {
    testWidgets('渲染各平台徽章：图标 + 分数文本', (tester) async {
      await tester.pumpWidget(wrap(const RatingsBadgeRow(badges: [
        HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
        HeroRatingBadge(RatingPlatform.imdb, '7.6'),
        HeroRatingBadge(RatingPlatform.rottenTomatoesCritic, '69%'),
        HeroRatingBadge(RatingPlatform.metacritic, '67'),
      ])));

      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('7.6'), findsOneWidget);
      expect(find.text('69%'), findsOneWidget);
      expect(find.text('67'), findsOneWidget);
      // 品牌图标：4 个 Icon（🍿 emoji 不在此列）。
      expect(find.byType(Icon), findsNWidgets(4));
    });

    testWidgets('全平台徽章渲染（豆瓣/Trakt/Letterboxd 含在内，Simkl 已移除）', (tester) async {
      await tester.pumpWidget(wrap(const RatingsBadgeRow(badges: [
        HeroRatingBadge(RatingPlatform.douban, '8.9'),
        HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
        HeroRatingBadge(RatingPlatform.imdb, '7.6'),
        HeroRatingBadge(RatingPlatform.rottenTomatoesCritic, '69%'),
        HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '85%'),
        HeroRatingBadge(RatingPlatform.letterboxd, '7.6'),
        HeroRatingBadge(RatingPlatform.trakt, '75%'),
        HeroRatingBadge(RatingPlatform.metacritic, '67'),
      ])));

      expect(find.text('8.9'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('🍿'), findsOneWidget);
      // 7 个品牌 Icon（🍿 emoji 不计）。
      expect(find.byType(Icon), findsNWidgets(7));
    });

    testWidgets('烂番茄观众分用 emoji 徽章', (tester) async {
      await tester.pumpWidget(wrap(const RatingsBadgeRow(badges: [
        HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '85%'),
      ])));
      expect(find.text('🍿'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('无数据平台不渲染（缺哪枚隐藏哪枚，绝不留空徽章）', (tester) async {
      await tester.pumpWidget(wrap(const RatingsBadgeRow(badges: [
        HeroRatingBadge(RatingPlatform.imdb, '7.6'),
      ])));
      expect(find.text('7.6'), findsOneWidget);
      expect(find.text('TMDB'), findsNothing);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('空列表渲染零尺寸（整块隐藏）', (tester) async {
      await tester.pumpWidget(wrap(const RatingsBadgeRow(badges: [])));
      expect(find.byType(Wrap), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('按平台声明顺序渲染并同平台去重', (tester) async {
      // 乱序输入 + 重复平台：声明序 douban→tmdb→imdb→…，重复保留首个。
      await tester.pumpWidget(wrap(const RatingsBadgeRow(badges: [
        HeroRatingBadge(RatingPlatform.imdb, '7.6'),
        HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
        HeroRatingBadge(RatingPlatform.imdb, '9.9'),
      ])));

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();
      // TMDB（7.4）排在 IMDb（7.6）前；重复的 9.9 被去重。
      expect(texts, ['7.4', '7.6']);
    });
  });

  group('HeroRatingsLoader（698 异步补位）', () {
    testWidgets('首帧渲染种子徽章，网络数据到达后替换', (tester) async {
      final query = const HeroRatingQuery(tmdbScore: 7.4);
      final completer = Completer<List<HeroRatingBadge>>();
      final service = _FakeService(() => completer.future);

      await tester.pumpWidget(wrap(HeroRatingsLoader(
        query: query,
        service: service,
      )));
      await tester.pump();
      // 首帧：只有种子 TMDB 徽章。
      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('7.6'), findsNothing);

      completer.complete(const [
        HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
        HeroRatingBadge(RatingPlatform.imdb, '7.6'),
      ]);
      await tester.pump();
      await tester.pump();
      // 数据到达：IMDb 徽章补位。
      expect(find.text('7.6'), findsOneWidget);
    });

    testWidgets('query 变化（换条目）时重新加载', (tester) async {
      final service = _FakeService(
        () async => const [HeroRatingBadge(RatingPlatform.imdb, '8.8')],
      );
      final widget = HeroRatingsLoader(
        query: const HeroRatingQuery(tmdbScore: 7.4),
        service: service,
      );
      await tester.pumpWidget(wrap(widget));
      await tester.pump();
      expect(service.calls, 1);

      await tester.pumpWidget(wrap(HeroRatingsLoader(
        query: const HeroRatingQuery(tmdbScore: 6.0),
        service: service,
      )));
      await tester.pump();
      expect(service.calls, 2);
    });

    testWidgets('竞态令牌（698）：旧响晚到不得覆写新条目徽章', (tester) async {
      // 第一响挂起（旧条目），第二响即回（新条目）。
      final slow = Completer<List<HeroRatingBadge>>();
      var first = true;
      final service = _FakeService(() {
        if (first) {
          first = false;
          return slow.future;
        }
        return Future.value(const [
          HeroRatingBadge(RatingPlatform.imdb, '8.8'),
        ]);
      });

      await tester.pumpWidget(wrap(HeroRatingsLoader(
        query: const HeroRatingQuery(tmdbScore: 7.4),
        service: service,
      )));
      await tester.pump();
      expect(find.text('7.4'), findsOneWidget);

      // 换条目：新响 8.8 立即到达。
      await tester.pumpWidget(wrap(HeroRatingsLoader(
        query: const HeroRatingQuery(tmdbScore: 6.0),
        service: service,
      )));
      await tester.pump();
      expect(find.text('8.8'), findsOneWidget);

      // 旧响晚到（6.6）：必须被丢弃，不得覆写。
      slow.complete(const [
        HeroRatingBadge(RatingPlatform.imdb, '6.6'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('6.6'), findsNothing, reason: '旧响不得串场');
      expect(find.text('8.8'), findsOneWidget);
    });

    testWidgets('service 实例变化（配 key 后 provider 重建）立即重拉', (tester) async {
      // 旧 service：空数据（模拟未配 key）。
      final stale = _FakeService(() async => const <HeroRatingBadge>[]);
      await tester.pumpWidget(wrap(HeroRatingsLoader(
        query: const HeroRatingQuery(tmdbScore: 7.4),
        service: stale,
      )));
      await tester.pump();
      expect(find.text('7.6'), findsNothing);

      // 同 query 换新 service（key 配好）：应立即补亮。
      final fresh = _FakeService(
        () async => const [HeroRatingBadge(RatingPlatform.imdb, '7.6')],
      );
      await tester.pumpWidget(wrap(HeroRatingsLoader(
        query: const HeroRatingQuery(tmdbScore: 7.4),
        service: fresh,
      )));
      await tester.pump();
      await tester.pump();
      expect(fresh.calls, 1);
      expect(find.text('7.6'), findsOneWidget);
    });
  });
}

/// 假评分服务：替换 fetch 行为（缓存语义归 service 自己的测试管）。
class _FakeService implements HeroRatingsSource {
  _FakeService(this.result);

  final Future<List<HeroRatingBadge>> Function() result;
  int calls = 0;

  @override
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query) async {
    calls++;
    return result();
  }
}
