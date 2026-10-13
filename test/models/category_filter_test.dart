import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/category_filter.dart';

void main() {
  group('CategoryFilter 查询参数拼接', () {
    test('空筛选：全部参数为 null、isEmpty', () {
      const f = CategoryFilter.empty;
      expect(f.isEmpty, isTrue);
      expect(f.isNotEmpty, isFalse);
      expect(f.watchStatusParam, isNull);
      expect(f.genresParam, isNull);
      expect(f.yearsParam, isNull);
      expect(f.ratingsParam, isNull);
    });

    test('播放状态映射 Emby Filters 值；任意 → null', () {
      expect(WatchStatusFilter.any.embyValue, isNull);
      expect(
        const CategoryFilter(watchStatus: WatchStatusFilter.watched)
            .watchStatusParam,
        'IsPlayed',
      );
      expect(
        const CategoryFilter(watchStatus: WatchStatusFilter.unwatched)
            .watchStatusParam,
        'IsUnplayed',
      );
      expect(
        const CategoryFilter(watchStatus: WatchStatusFilter.resumable)
            .watchStatusParam,
        'IsResumable',
      );
    });

    test('多选分隔符：Genres/Ratings 管道符、Years 逗号', () {
      final f = CategoryFilter(
        genres: {'动作', '科幻'},
        years: {2024, 2023},
        ratings: {'PG-13', 'R'},
      );
      expect(f.genresParam!.split('|').toSet(), {'动作', '科幻'});
      expect(f.yearsParam, anyOf('2024,2023', '2023,2024'));
      expect(f.ratingsParam, anyOf('PG-13|R', 'R|PG-13'));
      expect(f.isEmpty, isFalse);
    });

    test('copyWith 替换指定维度、保留其余', () {
      final f = CategoryFilter.empty.copyWith(
        watchStatus: WatchStatusFilter.watched,
        genres: {'动作'},
      );
      expect(f.watchStatus, WatchStatusFilter.watched);
      expect(f.genres, {'动作'});
      expect(f.years, isEmpty);

      final cleared = f.copyWith(watchStatus: WatchStatusFilter.any);
      expect(cleared.watchStatus, WatchStatusFilter.any);
      expect(cleared.genres, {'动作'});
    });

    test('相等性：集合内容比较（与插入顺序无关）', () {
      final a = CategoryFilter(genres: {'动作', '科幻'}, years: {2024});
      final b = CategoryFilter(genres: {'科幻', '动作'}, years: {2024});
      final c = CategoryFilter(genres: {'动作'}, years: {2024});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('MediaFilterOptions 分组可用性', () {
    test('全空 → isEmpty、各组隐藏', () {
      const o = MediaFilterOptions();
      expect(o.isEmpty, isTrue);
      expect(o.hasGenres, isFalse);
      expect(o.hasYears, isFalse);
      expect(o.hasRatings, isFalse);
    });

    test('任一组非空 → 对应 has 为 true', () {
      const o = MediaFilterOptions(years: [2024]);
      expect(o.isEmpty, isFalse);
      expect(o.hasYears, isTrue);
      expect(o.hasGenres, isFalse);
    });
  });
}
