import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/mdk_log_parser.dart';

void main() {
  group('MdkLogParser 状态行识别', () {
    test('真机状态行被识别', () {
      const line =
          '[DD 21:26:53.580][720->0][ffmpeg] | 26.4fps cache 0v 1.0s';
      expect(MdkLogParser.isStatusLine(line), isTrue);
    });

    test('媒体信息行不是状态行（关键：避免取到声明帧率 24）', () {
      const line = '[DD 21:26:52.100][0x7f0][ffmpeg] video info: '
          '3840x2160 fps: 24 duration: 5400.0';
      expect(MdkLogParser.isStatusLine(line), isFalse);
      expect(MdkLogParser.parseFps(line), isNull);
    });

    test('关键行被识别', () {
      expect(
        MdkLogParser.isNotableLine('[DD][decoder.video | FFmpeg | 0]'),
        isTrue,
      );
      expect(MdkLogParser.isNotableLine('av_sync drop 12 frames'), isTrue);
      expect(
        MdkLogParser.isNotableLine('dovi profile 8.4 detected'),
        isTrue,
      );
    });

    test('mdk 底层 codec 名单独由模式识别', () {
      // 该行是硬解判定的实证，用来交叉验证平台预选的推断。
      // 它不含既有关键词表中的任何词，必须靠模式匹配才能留住。
      expect(
        MdkLogParser.isNotableLine(
          'AMediaCodec selected video codec name: c2.qti.hevc.decoder',
        ),
        isTrue,
      );
      expect(
        MdkLogParser.isNotableLine(
          'AMediaCodec selected audio codec name: c2.qti.audio.decoder',
        ),
        isTrue,
      );
      expect(
        MdkLogParser.isNotableLine(
          'video/hevc AMediaCodec_createCodecByName: c2.android.hevc.decoder',
        ),
        isTrue,
      );
    });

    test('codec 名单参与保留但不计入速率限流', () {
      // 速率安全阀只统计状态行；codec 名偶尔出现且信息量高，不该被限流丢弃
      const line = 'AMediaCodec selected video codec name: c2.qti.hevc.decoder';
      expect(MdkLogParser.shouldKeep(line), isTrue);
      expect(MdkLogParser.isRateLimitedLine(line), isFalse);
    });

    test('buffering progress 刷屏既非状态行也非关键行', () {
      // 这一行每秒会刷 10~30 条，早期版本因保留它而误触发 50 行/秒安全阀
      const line = 'buffering progress 12.5%';
      expect(MdkLogParser.isStatusLine(line), isFalse);
      expect(MdkLogParser.isNotableLine(line), isFalse);
      expect(MdkLogParser.shouldKeep(line), isFalse);
    });

    test('空行被丢弃', () {
      expect(MdkLogParser.shouldKeep(''), isFalse);
      expect(MdkLogParser.shouldKeep('   '), isFalse);
    });

    group('速率安全阀范围', () {
      test('prepare 阶段爆发的解码器初始化行不计入速率统计', () {
        // 旧实现把关键行也计入速率统计，导致深度诊断在开启后 0.04 秒
        // 就被安全阀关闭，反而一条数据都留不下。
        for (var i = 0; i < 500; i++) {
          const line =
              '[DD 12:00:00.000][info][ffmpeg] decoder.video | FFmpeg | 0';
          expect(MdkLogParser.shouldKeep(line), isTrue, reason: '应保留');
          expect(MdkLogParser.isRateLimitedLine(line), isFalse,
              reason: '不应计入速率统计');
        }
      });

      test('状态行计入速率统计', () {
        const line = '[DD 12:00:00.000][0][0] | 24.0fps cache 0v 1.0s';
        expect(MdkLogParser.isRateLimitedLine(line), isTrue);
      });

      test('ffmpeg / dovi 关键行保留但不限速', () {
        for (final k in ['ffmpeg', 'dovi', 'rpu', 'dropped', 'av_sync']) {
          final line = 'some $k line here';
          expect(MdkLogParser.shouldKeep(line), isTrue);
          expect(MdkLogParser.isRateLimitedLine(line), isFalse);
        }
      });
    });
  });

  group('MdkLogParser 实测帧率解析', () {
    test('取状态行中的实测帧率，而非媒体声明的 24', () {
      const mediaInfo = 'video info: 3840x2160 fps: 24';
      const status = '| 7.7fps cache 0v 0.0s';

      expect(MdkLogParser.parseFps(mediaInfo), isNull,
          reason: '声明帧率不得进入诊断时间线');
      expect(MdkLogParser.parseFps(status), closeTo(7.7, 0.01));
    });

    test('兼容整数与小数形式', () {
      expect(
        MdkLogParser.parseFps('[0][0] | 24fps cache 0v 3.0s'),
        closeTo(24.0, 0.01),
      );
      expect(
        MdkLogParser.parseFps('[0][0] | 23.976fps cache 0v 3.0s'),
        closeTo(23.976, 0.001),
      );
    });

    test('兼容 fps 在前的写法', () {
      expect(
        MdkLogParser.parseFps('status fps: 18.8 cache 2v 1.5s'),
        closeTo(18.8, 0.01),
      );
      expect(
        MdkLogParser.parseFps('rfps: 24.5 cache 2v 1.5s'),
        closeTo(24.5, 0.01),
      );
    });

    test('0 fps 视为无效，不污染时间线', () {
      expect(MdkLogParser.parseFps('| 0.0fps cache 0v 0.0s'), isNull);
    });

    test('异常大值被拒绝', () {
      expect(MdkLogParser.parseFps('| 99999fps cache 0v 0.0s'), isNull);
    });

    test('无 fps 的行返回 null', () {
      expect(MdkLogParser.parseFps('| cache 0v 1.0s'), isNull);
    });
  });

  group('MdkLogParser 缓存解析', () {
    test('提取缓存秒数', () {
      expect(
        MdkLogParser.parseCacheSeconds('| 26.4fps cache 0v 1.0s'),
        closeTo(1.0, 0.01),
      );
      expect(
        MdkLogParser.parseCacheSeconds('| 23.4fps cache 2v 5.5s update 42ms'),
        closeTo(5.5, 0.01),
      );
    });

    test('非状态行返回 null', () {
      expect(MdkLogParser.parseCacheSeconds('video info: fps: 24'), isNull);
    });
  });
}
