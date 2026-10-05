import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/screens/detail/series_sections.dart';

void main() {
  group('SeriesSections.seasonTitle（播出季标题用 Emby 季名）', () {
    test('Emby 季名非空 → 直接用季名（如「特别篇」）', () {
      final s = MediaItem(id: 's1', name: '特别篇', type: 'Season');
      expect(SeriesSections.seasonTitle(s, 0), '特别篇');
    });

    test('空名/纯空白 → 回退「第 N 季」（用 indexNumber）', () {
      final s = MediaItem(
        id: 's1',
        name: '   ',
        type: 'Season',
        indexNumber: 3,
      );
      expect(SeriesSections.seasonTitle(s, 0), '第 3 季');
    });

    test('空名且无 indexNumber → 回退列表序号（1 起）', () {
      final s = MediaItem(id: 's1', name: '', type: 'Season');
      expect(SeriesSections.seasonTitle(s, 1), '第 2 季');
    });

    test('合成季（name=第N季）→ 原样返回', () {
      final s = MediaItem(
        id: 'season_1',
        name: '第1季',
        type: 'Season',
        indexNumber: 1,
      );
      expect(SeriesSections.seasonTitle(s, 0), '第1季');
    });
  });
}
