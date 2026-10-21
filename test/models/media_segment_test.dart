import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_segment.dart';

void main() {
  group('MediaChapter', () {
    test('Ticks 转毫秒并解析 MarkerType', () {
      final chapter = MediaChapter.fromJson({
        'StartPositionTicks': 125000000,
        'Name': 'Opening',
        'MarkerType': 'IntroStart',
      });
      expect(chapter.startMs, 12500);
      expect(chapter.name, 'Opening');
      expect(chapter.markerType, 'IntroStart');
    });

    test('缺失/非法 StartPositionTicks 回退 0', () {
      expect(MediaChapter.fromJson(const {}).startMs, 0);
      expect(
        MediaChapter.fromJson(const {'StartPositionTicks': -10}).startMs,
        0,
      );
    });
  });

  group('ManualSegmentRecord', () {
    test('剧集 key 使用 seriesId，电影使用 itemId', () {
      const episode = ManualSegmentRecord(
        serverId: 's1',
        seriesId: 'series-1',
        itemId: 'ep-1',
        providerIds: {},
        updatedAtMs: 1,
      );
      const movie = ManualSegmentRecord(
        serverId: 's1',
        itemId: 'movie-1',
        providerIds: {},
        updatedAtMs: 1,
      );
      expect(episode.key, 's1|series-1');
      expect(movie.key, 's1|movie-1');
    });

    test('copyWith 可显式清除标记字段', () {
      const record = ManualSegmentRecord(
        serverId: 's1',
        itemId: 'm1',
        providerIds: {},
        introEndMs: 1000,
        creditsStartMs: 2000,
        updatedAtMs: 1,
      );
      final next = record.copyWith(introEndMs: null);
      expect(next.introEndMs, isNull);
      expect(next.creditsStartMs, 2000);
    });

    test('JSON 往返保留标记与 providerIds', () {
      const record = ManualSegmentRecord(
        serverId: 's1',
        seriesId: 'series-1',
        itemId: 'ep-1',
        providerIds: {'Tvdb': '123'},
        introEndMs: 90000,
        creditsStartMs: 2500000,
        updatedAtMs: 42,
      );
      final back = ManualSegmentRecord.fromJson(record.toJson());
      expect(back.key, record.key);
      expect(back.providerIds, {'Tvdb': '123'});
      expect(back.introEndMs, 90000);
      expect(back.creditsStartMs, 2500000);
    });
  });

  test('MediaSegment contains/有效性', () {
    const segment = MediaSegment(
      type: MediaSegmentType.intro,
      startMs: 1000,
      endMs: 2000,
      source: MediaSegmentSource.manual,
    );
    expect(segment.contains(999), isFalse);
    expect(segment.contains(1000), isTrue);
    expect(segment.contains(2000), isFalse);
    expect(segment.isValid(10000), isTrue);
    expect(
      const MediaSegment(
        type: MediaSegmentType.intro,
        startMs: 0,
        endMs: 0,
        source: MediaSegmentSource.manual,
      ).isValid(10000),
      isFalse,
    );
  });
}
