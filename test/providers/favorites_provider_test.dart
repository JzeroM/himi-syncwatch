import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';

void main() {
  group('FavoriteGroups.fromItems', () {
    test('按 Type 分为 电影/电视剧/集，忽略其它类型', () {
      final groups = FavoriteGroups.fromItems([
        MediaItem(id: 'm1', name: '电影', type: 'Movie'),
        MediaItem(id: 's1', name: '剧集', type: 'Series'),
        MediaItem(id: 'e1', name: '第1集', type: 'Episode'),
        MediaItem(id: 'e2', name: '第2集', type: 'Episode'),
        MediaItem(id: 'x1', name: '季', type: 'Season'),
      ]);

      expect(groups.movies.map((e) => e.id), ['m1']);
      expect(groups.series.map((e) => e.id), ['s1']);
      expect(groups.episodes.map((e) => e.id), ['e1', 'e2']);
      expect(groups.isEmpty, isFalse);
    });

    test('空列表 → isEmpty', () {
      expect(FavoriteGroups.fromItems(const []).isEmpty, isTrue);
    });
  });
}
