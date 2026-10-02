import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';

void main() {
  group('MediaItem.premiereDate 解析', () {
    test('PremiereDate ISO 字符串解析为 DateTime', () {
      final item = MediaItem.fromJson({
        'Id': 'e1',
        'Name': '第1集',
        'Type': 'Episode',
        'PremiereDate': '2022-03-31T00:00:00.0000000Z',
      });

      expect(item.premiereDate, isNotNull);
      expect(item.premiereDate!.year, 2022);
      expect(item.premiereDate!.month, 3);
      expect(item.premiereDate!.day, 31);
    });

    test('缺 PremiereDate 字段 → null', () {
      final item = MediaItem.fromJson({
        'Id': 'e1',
        'Name': '第1集',
        'Type': 'Episode',
      });
      expect(item.premiereDate, isNull);
    });

    test('非法日期字符串 → null 不抛错', () {
      final item = MediaItem.fromJson({
        'Id': 'e1',
        'Name': '第1集',
        'Type': 'Episode',
        'PremiereDate': 'not-a-date',
      });
      expect(item.premiereDate, isNull);
    });
  });

  group('季/集字段', () {
    test('IndexNumber/ParentIndexNumber 解析', () {
      final item = MediaItem.fromJson({
        'Id': 'e1',
        'Name': '失败会传染',
        'Type': 'Episode',
        'IndexNumber': 1,
        'ParentIndexNumber': 3,
      });

      expect(item.isEpisode, isTrue);
      expect(item.indexNumber, 1);
      expect(item.parentIndexNumber, 3);
    });

    test('Season 类型 isSeries 为 false、childCount 可用', () {
      final season = MediaItem.fromJson({
        'Id': 'sea1',
        'Name': '第1季',
        'Type': 'Season',
        'IndexNumber': 1,
        'ChildCount': 6,
      });

      expect(season.isSeries, isFalse);
      expect(season.indexNumber, 1);
      expect(season.childCount, 6);
    });
  });
}
