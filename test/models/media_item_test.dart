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

  group('logoUrl（标题艺术字 ImageTags.Logo）', () {
    test('有 Logo tag + serverUrl → Logo 图 URL', () {
      final item = MediaItem.fromJson({
        'Id': 'm1',
        'Name': '完美世界',
        'Type': 'Movie',
        'ImageTags': {'Primary': 'p1', 'Logo': 'L1'},
      }, serverUrl: 'https://emby.test');
      expect(item.logoUrl, 'https://emby.test/Items/m1/Images/Logo?tag=L1');
    });

    test('无 Logo tag → null（hero 回退文字片名）', () {
      final item = MediaItem.fromJson({
        'Id': 'm1',
        'Name': '完美世界',
        'Type': 'Movie',
        'ImageTags': {'Primary': 'p1'},
      }, serverUrl: 'https://emby.test');
      expect(item.logoUrl, isNull);
    });

    test('有 Logo tag 但无 serverUrl → null（buildUrl 无基址）', () {
      final item = MediaItem.fromJson({
        'Id': 'm1',
        'Name': '完美世界',
        'Type': 'Movie',
        'ImageTags': {'Logo': 'L1'},
      });
      expect(item.logoUrl, isNull);
    });
  });
}
