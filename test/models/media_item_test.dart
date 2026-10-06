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

  group('收藏态 UserData.IsFavorite 解析', () {
    test('UserData.IsFavorite=true → isFavorite=true', () {
      final item = MediaItem.fromJson({
        'Id': 'm1',
        'Name': '电影',
        'Type': 'Movie',
        'UserData': {'IsFavorite': true},
      });
      expect(item.isFavorite, isTrue);
    });

    test('缺 UserData / IsFavorite → isFavorite=false', () {
      expect(
        MediaItem.fromJson({'Id': 'm1', 'Name': '电影', 'Type': 'Movie'})
            .isFavorite,
        isFalse,
      );
      expect(
        MediaItem.fromJson({
          'Id': 'm1',
          'Name': '电影',
          'Type': 'Movie',
          'UserData': <String, dynamic>{},
        }).isFavorite,
        isFalse,
      );
    });
  });

  group('已观看态 UserData.Played 解析', () {
    test('UserData.Played=true → isWatched=true', () {
      final item = MediaItem.fromJson({
        'Id': 'm1',
        'Name': '电影',
        'Type': 'Movie',
        'UserData': {'Played': true},
      });
      expect(item.isWatched, isTrue);
    });

    test('缺 UserData / Played → isWatched=false', () {
      expect(
        MediaItem.fromJson({'Id': 'm1', 'Name': '电影', 'Type': 'Movie'})
            .isWatched,
        isFalse,
      );
      expect(
        MediaItem.fromJson({
          'Id': 'm1',
          'Name': '电影',
          'Type': 'Movie',
          'UserData': <String, dynamic>{},
        }).isWatched,
        isFalse,
      );
    });
  });

  group('续播进度 UserData 解析', () {
    test('PlaybackPositionTicks → playbackPositionMs，PlayedPercentage 透传', () {
      final item = MediaItem.fromJson({
        'Id': 'e1',
        'Name': '第1集',
        'Type': 'Episode',
        'UserData': {
          'PlaybackPositionTicks': 1690000000, // 169s
          'PlayedPercentage': 12.5,
          'Played': false,
        },
      });
      expect(item.playbackPositionMs, 169000);
      expect(item.playedPercentage, 12.5);
      expect(item.isWatched, isFalse);
    });

    test('缺字段 → 0', () {
      final item =
          MediaItem.fromJson({'Id': 'm1', 'Name': '电影', 'Type': 'Movie'});
      expect(item.playbackPositionMs, 0);
      expect(item.playedPercentage, 0.0);
    });
  });
}
