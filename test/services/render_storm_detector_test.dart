import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/mdk_log_parser.dart';
import 'package:himi_syncwatch/services/render_storm_detector.dart';

/// 渲染风暴检测器（v1.1.82）：mdk renderer 持续丢帧 = 画面定格、
/// 音频/进度正常的签名（himi_logs_5 切集后实测约 58 帧/秒）。
void main() {
  // himi_logs_5 实测两种丢帧行形态
  const frameDrop =
      '[DD 20:36:55.123][3840->0][ffmpeg] VideoFrame 25 to be destroyed '
      'is not rendered by 0xb4000076bfbfc7e0 0xb4000076bfb721b0';
  const codecDrop =
      '[DD 20:36:55.124][AMediaCodec] release MediaCodec output buffer '
      'which was not rendered @0';
  const normalLine =
      '[DD 20:36:55.100][720->0][ffmpeg] | 24.0fps cache 0v 1.0s update 8ms';

  group('MdkLogParser.isNotRenderedLine', () {
    test('两种丢帧形态均识别', () {
      expect(MdkLogParser.isNotRenderedLine(frameDrop), isTrue);
      expect(MdkLogParser.isNotRenderedLine(codecDrop), isTrue);
    });

    test('状态行/普通行不识别；含 not rendered 即签名（宽松匹配刻意）', () {
      expect(MdkLogParser.isNotRenderedLine(normalLine), isFalse);
      expect(
          MdkLogParser.isNotRenderedLine('RenderAPI: OpenGL ES 3.2'), isFalse);
      expect(MdkLogParser.isNotRenderedLine('NOT RENDERED YET'), isTrue);
    });
  });

  group('RenderStormDetector', () {
    test('非丢帧行恒返回 null 且不累计', () {
      final d = RenderStormDetector(threshold: 3);
      expect(d.feed(normalLine), isNull);
      expect(d.feed(normalLine), isNull);
      expect(d.feed('anything else'), isNull);
    });

    test('零星丢帧（低于阈值）不报警', () {
      final d = RenderStormDetector(threshold: 20);
      final t0 = DateTime(2026, 10, 4, 20, 36, 55);
      for (var i = 0; i < 19; i++) {
        expect(d.feed(frameDrop, now: t0), isNull);
      }
    });

    test('1s 窗口内达到阈值：恰好报一次（去重）', () {
      final d = RenderStormDetector(threshold: 3);
      final t0 = DateTime(2026, 10, 4, 20, 36, 55);
      expect(d.feed(frameDrop, now: t0), isNull);
      expect(d.feed(codecDrop, now: t0), isNull);
      final report = d.feed(frameDrop, now: t0);
      expect(report, isNotNull);
      expect(report, contains('丢帧 3 帧'));
      expect(report, contains('画面定格'));
      // 同窗口继续丢帧不再重复报
      expect(d.feed(frameDrop, now: t0.add(const Duration(milliseconds: 100))),
          isNull);
    });

    test('窗口过期重置：下个 1s 窗口可再次报警', () {
      final d = RenderStormDetector(threshold: 2);
      final t0 = DateTime(2026, 10, 4, 20, 36, 55);
      expect(d.feed(frameDrop, now: t0), isNull);
      expect(d.feed(frameDrop, now: t0), isNotNull);
      final t1 = t0.add(const Duration(seconds: 2));
      expect(d.feed(frameDrop, now: t1), isNull);
      expect(d.feed(frameDrop, now: t1), isNotNull, reason: '新窗口计数从头开始，可再次触发');
    });

    test('reset 复位窗口与去重（换集时不跨媒体累计）', () {
      final d = RenderStormDetector(threshold: 2);
      final t0 = DateTime(2026, 10, 4, 20, 36, 55);
      expect(d.feed(frameDrop, now: t0), isNull);
      expect(d.feed(frameDrop, now: t0), isNotNull);
      d.reset();
      expect(d.feed(frameDrop, now: t0), isNull,
          reason: 'reset 后同窗口时间也要从 0 计数');
      expect(d.feed(frameDrop, now: t0), isNotNull);
    });

    test('不同行形态混合计数（VideoFrame + release 同窗口累计）', () {
      final d = RenderStormDetector(threshold: 4);
      final t0 = DateTime(2026, 10, 4, 20, 36, 55);
      expect(d.feed(frameDrop, now: t0), isNull);
      expect(d.feed(codecDrop, now: t0), isNull);
      expect(d.feed(frameDrop, now: t0), isNull);
      expect(d.feed(codecDrop, now: t0), isNotNull,
          reason: '两种形态都是 renderer 丢帧签名，合并计数');
    });
  });
}
