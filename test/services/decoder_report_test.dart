import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/decoder_report.dart';

void main() {
  group('DecoderTrack.verdict', () {
    test('FFmpeg 为软解确证——mdk 事件直接点名', () {
      const t = DecoderTrack(framework: 'FFmpeg');
      expect(t.verdict.kind, DecoderKind.software);
      expect(t.verdict.confirmed, isTrue);
      expect(t.verdict.label, '软解(确证)');
    });

    test('AMediaCodec + 硬件 codec 判为硬解，但标注为推断', () {
      const t = DecoderTrack(
        framework: 'AMediaCodec',
        codec: 'c2.qti.hevc.decoder',
        codecIsSoftware: false,
      );
      expect(t.verdict.kind, DecoderKind.hardware);
      expect(t.verdict.confirmed, isFalse);
      expect(t.verdict.label, '硬解(推断)');
    });

    test('AMediaCodec + c2.android 判为软解，仍是推断', () {
      // AMediaCodec 只是框架名，框架内完全可能落到软件 codec
      const t = DecoderTrack(
        framework: 'AMediaCodec',
        codec: 'c2.android.hevc.decoder',
        codecIsSoftware: true,
      );
      expect(t.verdict.kind, DecoderKind.software);
      expect(t.verdict.confirmed, isFalse);
      expect(t.verdict.label, '软解(推断)');
    });

    test('框架名大小写不敏感', () {
      DecoderVerdict judge(String fw) => DecoderTrack(
            framework: fw,
            codec: 'c2.qti.hevc.decoder',
            codecIsSoftware: false,
          ).verdict;
      // mdk 上报的原始形态为 AMediaCodec，比较时统一小写
      expect(judge('AMediaCodec').kind, DecoderKind.hardware);
      expect(judge('amediacodec').kind, DecoderKind.hardware);
      expect(judge('  AMEDIACODEC  ').kind, DecoderKind.hardware);
    });

    test('无框架名时判为未知，不猜', () {
      const t = DecoderTrack(codec: 'c2.qti.hevc.decoder', codecIsSoftware: false);
      expect(t.verdict.kind, DecoderKind.unknown);
      expect(t.verdict.label, '未知');
    });

    test('未知 codec 软件属性时判为未知，不猜', () {
      const t = DecoderTrack(framework: 'AMediaCodec');
      expect(t.verdict.kind, DecoderKind.unknown);
    });

    test('detail 填了状态而非解码器名时判为未知而非错值', () {
      // mdk 各版本对 detail 的填充不一致：我们的构建填解码器名，
      // 而 fvp issue #266 的日志里同一字段填的是 open。
      // 不在白名单内就必须判未知。
      const t = DecoderTrack(
        framework: 'open',
        codec: 'c2.qti.hevc.decoder',
        codecIsSoftware: false,
      );
      expect(t.verdict.kind, DecoderKind.unknown);
    });
  });

  group('DecoderTrack.display', () {
    test('包含框架、底层 codec、判定与 mdk error 码', () {
      const t = DecoderTrack(
        framework: 'AMediaCodec',
        error: 0,
        codec: 'c2.qti.hevc.decoder',
        codecIsSoftware: false,
      );
      expect(
        t.display,
        'AMediaCodec → c2.qti.hevc.decoder  硬解(推断)  code 0',
      );
    });

    test('失败时保留 mdk 的实际错误码', () {
      const t = DecoderTrack(framework: 'AMediaCodec', error: -10002);
      expect(t.display, contains('code -10002'));
    });

    test('未探测到底层 codec 时不显示箭头', () {
      const t = DecoderTrack(framework: 'FFmpeg');
      expect(t.display, 'FFmpeg  软解(确证)  code 0');
    });

    test('完全无数据时给出占位符', () {
      const t = DecoderTrack();
      expect(t.display, '?  未知  code 0');
    });
  });

  group('DecoderTrack.copyWith', () {
    test('只更新指定字段，其余保留', () {
      const t = DecoderTrack(
        framework: 'AMediaCodec',
        error: 3,
        codec: 'c2.qti.hevc.decoder',
        codecIsSoftware: false,
      );
      final n = t.copyWith(framework: 'FFmpeg');
      expect(n.framework, 'FFmpeg');
      expect(n.error, 3);
      expect(n.codec, 'c2.qti.hevc.decoder');
      expect(n.codecIsSoftware, isFalse);
    });
  });

  group('DecoderReport', () {
    test('empty 两条轨道都无框架', () {
      expect(DecoderReport.empty.isEmpty, isTrue);
      expect(DecoderReport.empty.video.hasFramework, isFalse);
      expect(DecoderReport.empty.audio.hasFramework, isFalse);
    });

    test('withVideo/withAudio 互不覆盖', () {
      const v = DecoderTrack(framework: 'AMediaCodec', codec: 'c2.qti.hevc.decoder', codecIsSoftware: false);
      const a = DecoderTrack(framework: 'FFmpeg');
      final r = DecoderReport.empty.withVideo(v).withAudio(a);
      expect(r.video.framework, 'AMediaCodec');
      expect(r.audio.framework, 'FFmpeg');
    });

    test('任一轨道有框架即非空', () {
      final r = DecoderReport.empty.withAudio(const DecoderTrack(framework: 'AMediaCodec'));
      expect(r.isEmpty, isFalse);
    });

    test('换集重置后回落到未知，不残留上一集解码器', () {
      final before = DecoderReport.empty
          .withVideo(const DecoderTrack(framework: 'AMediaCodec', codec: 'c2.qti.hevc.decoder', codecIsSoftware: false))
          .withAudio(const DecoderTrack(framework: 'FFmpeg'));
      const after = DecoderReport.empty;
      expect(after.video.verdict.kind, DecoderKind.unknown);
      expect(after.audio.verdict.kind, DecoderKind.unknown);
      expect(after.video.codec, '');
      expect(before.video.codec, isNotEmpty);
    });
  });

  group('DecoderVerdict', () {
    test('相同 kind 与 confirmed 视为相等', () {
      const a = DecoderVerdict(DecoderKind.hardware, confirmed: false);
      const b = DecoderVerdict(DecoderKind.hardware, confirmed: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('推断与确证不相等', () {
      const a = DecoderVerdict(DecoderKind.software, confirmed: false);
      const b = DecoderVerdict(DecoderKind.software, confirmed: true);
      expect(a == b, isFalse);
    });
  });
}
