import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';

void main() {
  group('TmdbItem', () {
    test('fromJson 兼容 movie/tv 字段并生成 key/year/图片地址', () {
      final movie = TmdbItem.fromJson(const {
        'id': 603,
        'media_type': 'movie',
        'title': '黑客帝国',
        'original_title': 'The Matrix',
        'release_date': '1999-03-30',
        'poster_path': '/poster.jpg',
        'backdrop_path': '/backdrop.jpg',
        'vote_average': 8.2,
        'vote_count': 24000,
        'genre_ids': [28, 878],
      });
      expect(movie.type, TmdbMediaType.movie);
      expect(movie.title, '黑客帝国');
      expect(movie.key, 'movie:603');
      expect(movie.year, '1999');
      expect(movie.posterUrl('https://img', size: 'w342'),
          'https://img/w342/poster.jpg');
      expect(
          movie.backdropUrl('https://img'), 'https://img/w1280/backdrop.jpg');

      final tv = TmdbItem.fromJson(
        const {
          'id': 1399,
          'name': '权力的游戏',
          'first_air_date': '2011-04-17',
          'poster_path': '/tv.jpg',
          'vote_average': 8.4,
        },
        fallbackType: TmdbMediaType.tv,
      );
      expect(tv.type, TmdbMediaType.tv);
      expect(tv.title, '权力的游戏');
      expect(tv.year, '2011');
      expect(tv.key, 'tv:1399');
    });

    test('fromJson 缺 media_type 且无 fallback 抛 FormatException', () {
      expect(
        () => TmdbItem.fromJson(const {'id': 1, 'title': 'X'}),
        throwsFormatException,
      );
    });

    test('图片路径为空时返回 null', () {
      const item = TmdbItem(id: 1, type: TmdbMediaType.movie, title: 'X');
      expect(item.posterUrl('https://img'), isNull);
      expect(item.backdropUrl('https://img'), isNull);
    });

    test('toJson/fromJson 往返保留核心字段', () {
      const item = TmdbItem(
        id: 42,
        type: TmdbMediaType.tv,
        title: '剧',
        originalTitle: 'Show',
        overview: '简介',
        posterPath: '/p.jpg',
        backdropPath: '/b.jpg',
        releaseDate: '2020-01-01',
        voteAverage: 7.5,
        voteCount: 10,
        popularity: 3.2,
        genreIds: [1, 2],
      );
      final round = TmdbItem.fromJson(item.toJson());
      expect(round.id, item.id);
      expect(round.type, item.type);
      expect(round.title, item.title);
      expect(round.posterPath, item.posterPath);
      expect(round.genreIds, item.genreIds);
    });
  });

  group('TmdbPagedResult', () {
    test('解析分页并过滤无效/未知类型条目', () {
      final result = TmdbPagedResult.fromJson(
        const {
          'page': 2,
          'total_pages': 5,
          'total_results': 100,
          'results': [
            {'id': 1, 'media_type': 'movie', 'title': 'A'},
            {'id': 0, 'media_type': 'movie', 'title': 'invalid'},
            {'id': 2, 'media_type': 'person', 'name': 'nobody'},
            'not-a-map',
          ],
        },
      );
      expect(result.page, 2);
      expect(result.hasMore, isTrue);
      expect(result.items.single.id, 1);
      expect(result.totalResults, 100);
    });

    test('末页 hasMore=false', () {
      final result = TmdbPagedResult.fromJson(const {
        'page': 3,
        'total_pages': 3,
        'results': [],
      });
      expect(result.hasMore, isFalse);
    });
  });

  group('TmdbPlatform', () {
    test('固定七个平台、顺序与本地 Logo 路径', () {
      expect(
        tmdbPlatforms.map((e) => e.providerId),
        [8, 337, 350, 1899, 15, 9, 531],
      );
      expect(tmdbPlatformName(8), 'Netflix');
      expect(tmdbPlatformName(9), 'Prime Video');
      expect(tmdbPlatformById(531)?.logoAsset, endsWith('paramount_plus.png'));
      expect(tmdbPlatformName(999), isNull);
    });
  });

  group('TmdbResumeEntry', () {
    final server = EmbyServerConfig(
      id: 's1',
      serverUrl: 'http://s1',
      serverName: 'S1',
      serverId: 'sid',
      username: 'u',
    );

    test('剧集优先 TMDB id，缺失时按剧名+季集去重', () {
      final withId = TmdbResumeEntry(
        item: _episode(tmdbId: '9'),
        server: server,
      );
      expect(withId.dedupeKey, 'e:9');
      final withoutId = TmdbResumeEntry(
        item: _episode(),
        server: server,
      );
      expect(withoutId.dedupeKey, 'e:剧名|2|3');
    });
  });
}

MediaItem _episode({String? tmdbId}) => MediaItem(
      id: 'ep',
      name: 'S02E03',
      type: 'Episode',
      seriesName: '剧名',
      parentIndexNumber: 2,
      indexNumber: 3,
      providerIds: tmdbId == null ? const {} : {'Tmdb': tmdbId},
    );
