import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/mdk_log_parser.dart';

void main() {
  group('MdkLogParser 状态行识别', () {
    test('真机状态行被识别', () {
      const line = '[DD 21:26:53.580][720->0][ffmpeg] | 26.4fps cache 0v 1.0s';
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

    test('RenderAPI / Surface 渲染链路行被识别（黑屏分叉取证）', () {
      // 深诊报告里要靠这两类行区分「mdk 渲染输出黑帧」vs「Flutter
      // 合成黑屏」，关键词表必须能留住它们。
      expect(MdkLogParser.isNotableLine('RenderAPI.type: 1'), isTrue);
      expect(
        MdkLogParser.isNotableLine('setVideoSurfaceSize(1920x1080, 0)'),
        isTrue,
      );
      expect(
        MdkLogParser.isNotableLine('present: SurfaceFlinger overlay'),
        isTrue,
      );
      expect(MdkLogParser.shouldKeep('RenderAPI.type: 0'), isTrue);
      // 普通行仍被丢弃（关键词扩展不能放大到刷屏）
      expect(MdkLogParser.isNotableLine('media info opened ok'), isFalse);
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

      expect(MdkLogParser.parseFps(mediaInfo), isNull, reason: '声明帧率不得进入诊断时间线');
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

  group('MdkLogParser 实测解码器名解析', () {
    // 真机样本：探测预测 c2.dolby.decoder.hevc，实测却是 c2.qti.hevc.decoder。
    test('提取 selected video codec name（真机实测样本）', () {
      expect(
        MdkLogParser.parseSelectedCodec(
          'AMediaCodec selected video codec name: c2.qti.hevc.decoder',
          video: true,
        ),
        'c2.qti.hevc.decoder',
      );
    });

    test('提取 createCodecByName 样本并带 mime 前缀', () {
      expect(
        MdkLogParser.parseSelectedCodec(
          'video/hevc AMediaCodec_createCodecByName: c2.qti.hevc.decoder',
          video: true,
        ),
        'c2.qti.hevc.decoder',
      );
    });

    test('行首带 mdk 时间戳前缀时仍可提取', () {
      expect(
        MdkLogParser.parseSelectedCodec(
          '[DD 12:00:01.234][720->0][ffmpeg] '
          'video/hevc AMediaCodec_createCodecByName: c2.qti.hevc.decoder',
          video: true,
        ),
        'c2.qti.hevc.decoder',
      );
    });

    test('音频与视频按 kind 区分，不串台', () {
      expect(
        MdkLogParser.parseSelectedCodec(
          'AMediaCodec selected audio codec name: c2.android.aac.decoder',
          video: false,
        ),
        'c2.android.aac.decoder',
      );
      // 同一行用 video 解析应为 null
      expect(
        MdkLogParser.parseSelectedCodec(
          'AMediaCodec selected audio codec name: c2.android.aac.decoder',
          video: true,
        ),
        isNull,
      );
      expect(
        MdkLogParser.parseSelectedCodec(
          'audio/eac3 AMediaCodec_createCodecByName: c2.qti.eac3.decoder',
          video: false,
        ),
        'c2.qti.eac3.decoder',
      );
    });

    // FFmpeg 软解不产生 Android 组件名，必须返回 null 让调用方降级。
    test('FFmpeg 行不产出 Android 组件名', () {
      expect(
        MdkLogParser.parseSelectedCodec('opening ffmpeg audio decoder: eac3',
            video: false),
        isNull,
      );
      expect(
        MdkLogParser.parseSelectedCodec('opening ffmpeg audio decoder: eac3',
            video: true),
        isNull,
      );
    });

    test('无关行返回 null', () {
      expect(MdkLogParser.parseSelectedCodec('dropped 12 frames', video: true),
          isNull);
      expect(MdkLogParser.parseSelectedCodec('', video: true), isNull);
    });
  });
}
