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

  test('手动片头 [0,end] 起播即可提示', () {
    final controller = SegmentSkipController();
    final trigger = controller.evaluate(
      positionMs: 500,
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

  test('手动 seek 进入片段不触发', () {
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
