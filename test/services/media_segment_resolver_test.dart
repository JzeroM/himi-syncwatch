import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_segment.dart';
import 'package:himi_syncwatch/services/media_segment_resolver.dart';

void main() {
  const duration = 3000000;

  List<MediaChapter> chapters() => const [
        MediaChapter(startMs: 0, markerType: 'Chapter'),
        MediaChapter(startMs: 10000, markerType: 'IntroStart'),
        MediaChapter(startMs: 100000, markerType: 'IntroEnd'),
        MediaChapter(startMs: 2700000, markerType: 'CreditsStart'),
      ];

  test('解析 IntroStart/IntroEnd 与 CreditsStart', () {
    final segments = MediaSegmentResolver.resolve(
      chapters: chapters(),
      manual: null,
      durationMs: duration,
    );
    expect(segments, hasLength(2));
    expect(segments[0].type, MediaSegmentType.intro);
    expect(segments[0].startMs, 10000);
    expect(segments[0].endMs, 100000);
    expect(segments[1].type, MediaSegmentType.outro);
    expect(segments[1].startMs, 2700000);
    expect(segments[1].endMs, duration);
  });

  test('手动片头/片尾按类型覆盖自动章节', () {
    final segments = MediaSegmentResolver.resolve(
      chapters: chapters(),
      manual: const ManualSegmentRecord(
        serverId: 's1',
        seriesId: 'series-1',
        providerIds: {},
        introEndMs: 80000,
        creditsStartMs: 2600000,
        updatedAtMs: 1,
      ),
      durationMs: duration,
    );
    expect(segments, hasLength(2));
    expect(segments[0].source, MediaSegmentSource.manual);
    expect(segments[0].startMs, 0);
    expect(segments[0].endMs, 80000);
    expect(segments[1].source, MediaSegmentSource.manual);
    expect(segments[1].startMs, 2600000);
    expect(segments[1].endMs, duration);
  });

  test('只覆盖一种类型时另一种继续用章节', () {
    final segments = MediaSegmentResolver.resolve(
      chapters: chapters(),
      manual: const ManualSegmentRecord(
        serverId: 's1',
        seriesId: 'series-1',
        providerIds: {},
        introEndMs: 90000,
        updatedAtMs: 1,
      ),
      durationMs: duration,
    );
    expect(segments[0].source, MediaSegmentSource.manual);
    expect(segments[1].source, MediaSegmentSource.embyChapter);
  });

  test('越界/非法手动标记被忽略并回退章节', () {
    final segments = MediaSegmentResolver.resolve(
      chapters: chapters(),
      manual: const ManualSegmentRecord(
        serverId: 's1',
        seriesId: 'series-1',
        providerIds: {},
        introEndMs: duration + 1,
        creditsStartMs: 0,
        updatedAtMs: 1,
      ),
      durationMs: duration,
    );
    expect(segments, hasLength(2));
    expect(segments[0].source, MediaSegmentSource.embyChapter);
    expect(segments[1].source, MediaSegmentSource.embyChapter);
  });

  test('越界手动片尾回退章节，不吞掉自动片尾', () {
    final segments = MediaSegmentResolver.resolve(
      chapters: chapters(),
      manual: const ManualSegmentRecord(
        serverId: 's1',
        seriesId: 'series-1',
        providerIds: {},
        creditsStartMs: duration + 1,
        updatedAtMs: 1,
      ),
      durationMs: duration,
    );
    expect(segments, hasLength(2));
    expect(segments[1].source, MediaSegmentSource.embyChapter);
  });

  test('缺少 IntroEnd 时不生成片头', () {
    final segments = MediaSegmentResolver.resolve(
      chapters: const [MediaChapter(startMs: 10000, markerType: 'IntroStart')],
      manual: null,
      durationMs: duration,
    );
    expect(segments, isEmpty);
  });

  test('空章节与空手动标记返回空列表', () {
    expect(
      MediaSegmentResolver.resolve(
        chapters: const [],
        manual: null,
        durationMs: duration,
      ),
      isEmpty,
    );
  });
}
