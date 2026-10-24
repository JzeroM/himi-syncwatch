import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_segment.dart';
import 'package:himi_syncwatch/services/segment_skip_controller.dart';

void main() {
  const intro = MediaSegment(
    type: MediaSegmentType.intro,
    startMs: 0,
    endMs: 90000,
    source: MediaSegmentSource.manual,
  );
  const outro = MediaSegment(
    type: MediaSegmentType.outro,
    startMs: 2500000,
    endMs: 3000000,
    source: MediaSegmentSource.embyChapter,
  );

  test('手动片头 [0,end] 前 3 秒不提示，达到 3 秒后提示', () {
    final controller = SegmentSkipController();
    expect(
      controller.evaluate(
        positionMs: 500,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [intro],
      ),
      isNull,
    );
    expect(
      controller.evaluate(
        positionMs: 2900,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [intro],
      ),
      isNull,
    );
    final trigger = controller.evaluate(
      positionMs: 3000,
      durationMs: 3000000,
      playing: true,
      enabled: true,
      segments: const [intro],
    );
    expect(trigger, same(intro));
  });

  test('章节片头 [0,end] 同样延迟到 3 秒后提示', () {
    const chapterIntro = MediaSegment(
      type: MediaSegmentType.intro,
      startMs: 0,
      endMs: 90000,
      source: MediaSegmentSource.embyChapter,
    );
    final controller = SegmentSkipController();
    expect(
      controller.evaluate(
        positionMs: 500,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [chapterIntro],
      ),
      isNull,
    );
    final trigger = controller.evaluate(
      positionMs: 3000,
      durationMs: 3000000,
      playing: true,
      enabled: true,
      segments: const [chapterIntro],
    );
    expect(trigger, same(chapterIntro));
  });

  test('片头起点在 3 秒后仍按自然越过起点触发', () {
    const lateIntro = MediaSegment(
      type: MediaSegmentType.intro,
      startMs: 10000,
      endMs: 90000,
      source: MediaSegmentSource.embyChapter,
    );
    final controller = SegmentSkipController();
    expect(
      controller.evaluate(
        positionMs: 9500,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [lateIntro],
      ),
      isNull,
    );
    final trigger = controller.evaluate(
      positionMs: 10000,
      durationMs: 3000000,
      playing: true,
      enabled: true,
      segments: const [lateIntro],
    );
    expect(trigger, same(lateIntro));
  });

  test('首次判定位于片头内且进度已达 3 秒时触发', () {
    final controller = SegmentSkipController();
    final trigger = controller.evaluate(
      positionMs: 60000,
      durationMs: 3000000,
      playing: true,
      enabled: true,
      segments: const [intro],
    );
    expect(trigger, same(intro));
  });

  test('普通片段只在自然越过起点时触发', () {
    final controller = SegmentSkipController();
    expect(
      controller.evaluate(
        positionMs: 2400000,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [outro],
      ),
      isNull,
    );
    final trigger = controller.evaluate(
      positionMs: 2500500,
      durationMs: 3000000,
      playing: true,
      enabled: true,
      segments: const [outro],
    );
    expect(trigger, same(outro));
  });

  test('同一片段只提示一次', () {
    final controller = SegmentSkipController();
    expect(
      controller.evaluate(
        positionMs: 2500100,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [outro],
      ),
      isNotNull,
    );
    expect(
      controller.evaluate(
        positionMs: 2500600,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [outro],
      ),
      isNull,
    );
  });

  test('初始/手动 seek 允许片尾中段提示', () {
    final controller = SegmentSkipController();
    controller.onSeek(
      positionMs: 2600000,
      segments: const [outro],
      markOutroHandled: false,
    );
    final trigger = controller.evaluate(
      positionMs: 2600500,
      durationMs: 3000000,
      playing: true,
      enabled: true,
      segments: const [outro],
    );
    expect(trigger, same(outro));
  });

  test('手动 seek 进入片段默认不触发', () {
    final controller = SegmentSkipController();
    controller.onSeek(positionMs: 2600000, segments: const [outro]);
    expect(
      controller.evaluate(
        positionMs: 2600500,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [outro],
      ),
      isNull,
    );
  });

  test('关闭开关/暂停时不触发', () {
    final controller = SegmentSkipController();
    expect(
      controller.evaluate(
        positionMs: 500,
        durationMs: 3000000,
        playing: true,
        enabled: false,
        segments: const [intro],
      ),
      isNull,
    );
    expect(
      controller.evaluate(
        positionMs: 500,
        durationMs: 3000000,
        playing: false,
        enabled: true,
        segments: const [intro],
      ),
      isNull,
    );
  });

  test('短于 3 秒的片段不弹询问', () {
    final controller = SegmentSkipController();
    const short = MediaSegment(
      type: MediaSegmentType.intro,
      startMs: 0,
      endMs: 2000,
      source: MediaSegmentSource.manual,
    );
    expect(
      controller.evaluate(
        positionMs: 500,
        durationMs: 3000000,
        playing: true,
        enabled: true,
        segments: const [short],
      ),
      isNull,
    );
  });
}
