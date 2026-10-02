import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/decoder_report.dart';
import 'package:himi_syncwatch/services/diagnostic_export.dart';

void main() {
  /// 组装一份报告，只覆盖关心的字段，其余走默认。
  String build({
    String buildSummary = '产物身份: 1.1.16+186 | DV通道已注册',
    String diagSummary = '卡顿次数: 11',
    String decodeMode = '智能',
    String videoDecoders = 'AMediaCodec,FFmpeg',
    bool isDolbyVisionContent = true,
    String dvCapability = '支持 DV 硬解',
    DecoderReport decoderReport = DecoderReport.empty,
    String mdkRawDecoder = '-',
    int bufProgress = -1,
    String timeline = 't(s)  ahead(ms)  cache(s)  buf%  state  status  fps',
    String stalls = '(无卡顿记录)\n',
    String events = '(无 mdk 事件)\n',
    String notes = '(无诊断事件)\n',
    String statusLines = '(深度诊断未开启或无数据)',
    String notableLines = '(无)',
    String? quickSnapshot,
  }) =>
      DiagnosticExport.build(
        buildSummary: buildSummary,
        diagSummary: diagSummary,
        decodeMode: decodeMode,
        videoDecoders: videoDecoders,
        isDolbyVisionContent: isDolbyVisionContent,
        dvCapability: dvCapability,
        decoderReport: decoderReport,
        mdkRawDecoder: mdkRawDecoder,
        bufProgress: bufProgress,
        timeline: timeline,
        stalls: stalls,
        events: events,
        notes: notes,
        statusLines: statusLines,
        notableLines: notableLines,
        quickSnapshot: quickSnapshot,
      );

  group('DiagnosticExport 解码环境', () {
    // 回归保护：这些字段曾只加在面板的另一个导出函数里，
    // 用户实际点的「复制卡顿诊断」按钮走的是本函数，根本没带上。
    test('实际解码 / mdk原值 / 音频实际三行必须进入报告', () {
      final report = build(
        decoderReport: const DecoderReport(
          video: DecoderTrack(
            framework: 'AMediaCodec',
            codec: 'c2.dolby.decoder.hevc',
            codecIsSoftware: false,
            actualCodec: 'c2.qti.hevc.decoder',
          ),
          audio: DecoderTrack(framework: 'FFmpeg'),
        ),
        mdkRawDecoder: 'c2.qti.hevc.decoder',
      );

      expect(report, contains('实际解码: AMediaCodec → c2.qti.hevc.decoder'));
      expect(report, contains('硬解(推断)'));
      expect(report, contains('mdk原值: c2.qti.hevc.decoder'));
      expect(report, contains('音频实际: FFmpeg'));
      expect(report, contains('软解(确证)'));
    });

    // 回归保护：预测值曾被直接塞进「实际解码」，真机上与实测值
    // 完全不同（c2.dolby.decoder.hevc vs c2.qti.hevc.decoder）。
    test('预测值只出现在探测预选行，不进实际解码行', () {
      final report = build(
        decoderReport: const DecoderReport(
          video: DecoderTrack(
            framework: 'FFmpeg',
            codec: 'c2.dolby.eac3.decoder.eac3',
            codecIsSoftware: true,
          ),
        ),
      );
      final actualLine =
          report.split('\n').firstWhere((l) => l.startsWith('实际解码:'));
      expect(actualLine, startsWith('实际解码:'));
      expect(actualLine, isNot(contains('c2.dolby.eac3.decoder.eac3')));
      expect(report, contains('探测预选: video=c2.dolby.eac3.decoder.eac3'));
    });

    test('探测预选行同时列出视频与音频预测值', () {
      final report = build(
        decoderReport: const DecoderReport(
          video: DecoderTrack(codec: 'c2.dolby.decoder.hevc'),
          audio: DecoderTrack(codec: 'c2.dolby.eac3.decoder.eac3'),
        ),
      );
      expect(
        report,
        contains('探测预选: video=c2.dolby.decoder.hevc '
            'audio=c2.dolby.eac3.decoder.eac3'),
      );
    });

    test('未探测时探测预选行给出占位符而非空白', () {
      final report = build(decoderReport: DecoderReport.empty);
      expect(report, contains('探测预选: 未探测'));
    });

    test('解码模式与视频解码器配置照常保留', () {
      final report = build();
      expect(report, contains('解码模式: 智能 | videoDecoders: AMediaCodec,FFmpeg'));
      expect(report, contains('DV 内容: true'));
      expect(report, contains('DV 能力: 支持 DV 硬解'));
    });

    test('无解码器数据时输出占位符而非空行', () {
      final report = build(decoderReport: DecoderReport.empty);
      expect(report, contains('实际解码: ?  未知  code 0'));
      expect(report, contains('音频实际: ?  未知  code 0'));
    });
  });

  group('DiagnosticExport 产物身份', () {
    test('产物身份位于报告首行', () {
      final report = build(
        buildSummary: '产物身份: 1.1.16+186 | DV通道已注册',
      );
      expect(report.split('\n').first, '产物身份: 1.1.16+186 | DV通道已注册');
    });

    test('产物缺原生插件时首行直接点明', () {
      final report = build(
        buildSummary: '产物身份: 未知 | DV通道未注册(产物缺原生插件)',
      );
      expect(report.split('\n').first, '产物身份: 未知 | DV通道未注册(产物缺原生插件)');
    });
  });

  group('DiagnosticExport 缓冲进度', () {
    test('已收到 reader.buffering 时给出百分比与来源', () {
      expect(DiagnosticExport.formatBufProgress(62),
          '缓冲进度: 62% (mdk reader.buffering, 0-100)');
      expect(DiagnosticExport.formatBufProgress(0),
          '缓冲进度: 0% (mdk reader.buffering, 0-100)');
    });

    test('未收到事件时标注未知', () {
      expect(DiagnosticExport.formatBufProgress(-1),
          '缓冲进度: 未知 (尚未收到 reader.buffering)');
    });

    test('越界值不吞掉，如实标注', () {
      expect(DiagnosticExport.formatBufProgress(150), '缓冲进度: 150% (异常值)');
    });

    test('缓冲进度行进入报告', () {
      expect(build(bufProgress: 37), contains('缓冲进度: 37%'));
      expect(build(bufProgress: -1), contains('缓冲进度: 未知'));
    });
  });

  group('DiagnosticExport 段落结构', () {
    test('各章节按固定顺序出现', () {
      final report = build();
      final order = [
        '=== 解码环境 ===',
        '=== 时间线 ===',
        '=== 卡顿事件 ===',
        '=== mdk 事件原文 ===',
        '=== 诊断事件 ===',
        '=== mdk 状态行 (fps/cache) ===',
        '=== mdk 关键行 (解码器/丢帧/错误) ===',
      ];
      var last = -1;
      for (final h in order) {
        final i = report.indexOf(h);
        expect(i, greaterThan(-1), reason: '缺少章节 $h');
        expect(i, greaterThan(last), reason: '章节顺序错乱于 $h');
        last = i;
      }
    });

    test('各段落原文被完整保留', () {
      final report = build(
        timeline: 'TIME_LINE_BODY',
        stalls: 'STALL_BODY',
        events: 'EVENT_BODY\n',
        notes: 'NOTE_BODY\n',
        statusLines: 'STATUS_BODY',
        notableLines: 'NOTABLE_BODY',
      );
      expect(report, contains('TIME_LINE_BODY'));
      expect(report, contains('STALL_BODY'));
      expect(report, contains('EVENT_BODY'));
      expect(report, contains('NOTE_BODY'));
      expect(report, contains('STATUS_BODY'));
      expect(report, contains('NOTABLE_BODY'));
    });

    test('诊断摘要紧随产物身份之后', () {
      final report = build(diagSummary: '卡顿次数: 11\n累计卡顿: 19412ms');
      final lines = report.split('\n');
      expect(lines[0], '产物身份: 1.1.16+186 | DV通道已注册');
      expect(lines.any((l) => l == '卡顿次数: 11'), isTrue);
      expect(lines.any((l) => l == '累计卡顿: 19412ms'), isTrue);
    });

    test('quickSnapshot 插在摘要之后、解码环境之前', () {
      final report = build(quickSnapshot: '=== 播放诊断 ===\n状态: playing');
      expect(
        report.indexOf('=== 播放诊断 ==='),
        greaterThan(report.indexOf('卡顿次数')),
      );
      expect(
        report.indexOf('=== 播放诊断 ==='),
        lessThan(report.indexOf('=== 解码环境 ===')),
      );
    });

    test('未传 quickSnapshot 时不出现快照段（回归旧行为）', () {
      final report = build();
      expect(report, isNot(contains('=== 播放诊断 ===')));
      expect(report, contains('=== 解码环境 ==='));
    });
  });

  group('DiagnosticExport 格式化函数', () {
    test('formatFps：0/负值显示 -，正常值保留 1 位小数', () {
      expect(DiagnosticExport.formatFps(0), '-');
      expect(DiagnosticExport.formatFps(-1), '-');
      expect(DiagnosticExport.formatFps(24), '24.0fps');
      expect(DiagnosticExport.formatFps(29.97), '30.0fps');
      // mdk 上报的浮点噪音不得整串输出
      expect(DiagnosticExport.formatFps(59.940000000000005), '59.9fps');
    });

    test('formatBitrate：0 显示 -，不输出误导的 0 kbps', () {
      expect(DiagnosticExport.formatBitrate(0), '-');
      expect(DiagnosticExport.formatBitrate(-5), '-');
      expect(DiagnosticExport.formatBitrate(38500), '38500 kbps');
    });

    test('formatClock：分钟内与超 1 小时两种格式', () {
      expect(DiagnosticExport.formatClock(0), '00:00.0');
      expect(DiagnosticExport.formatClock(125300), '02:05.3');
      expect(DiagnosticExport.formatClock(3661000), '1h01m01s');
    });
  });

  group('DiagnosticExport.buildQuick', () {
    /// 只关心帧率/码率格式时的最小快照。
    String quick({
      double videoFps = 0,
      int mediaBitrate = 0,
      int videoBitrate = 0,
      int audioBitrate = 0,
      String mediaFormat = '',
    }) =>
        DiagnosticExport.buildQuick(
          playbackState: 'playing',
          mediaStatus: 'ok',
          position: '00:10.0',
          duration: '01:00.0',
          bufferedMs: 1000,
          mediaBitrate: mediaBitrate,
          mediaFormat: mediaFormat,
          videoCodec: 'hevc',
          videoResolution: '3840x1608',
          videoFps: videoFps,
          videoBitrate: videoBitrate,
          pixelFormat: 'yuv420p',
          doviProfile: 0,
          hdrType: 'SDR',
          audioCodec: 'truehd',
          audioSampleRate: 0,
          audioChannels: 0,
          audioBitrate: audioBitrate,
          stereoDownmix: '关',
          audioFilter: '(无) | codec=未知',
          textureId: null,
          textureSize: '-',
        );

    test('帧率/码率未取到（0）时输出 - 而非 0.0fps / 0kbps', () {
      final text = quick();
      expect(text, contains('帧率: -'));
      expect(text, contains('码率: -'));
      expect(text, isNot(contains('0.0fps')));
      expect(text, isNot(contains('0kbps')));
      expect(text, isNot(contains('0 kbps')));
      // 采样率/声道同样为 0 时显示 -
      expect(text, contains('采样率: -'));
      expect(text, contains('声道: -'));
    });

    test('有值时带单位输出，封装为空显示 -', () {
      final text = quick(
        videoFps: 23.976,
        mediaBitrate: 70000,
        videoBitrate: 68000,
        audioBitrate: 2000,
        mediaFormat: 'mkv',
      );
      expect(text, contains('帧率: 24.0fps | 码率: 68000 kbps'));
      expect(text, contains('码率: 70000 kbps | 封装: mkv'));
      expect(text, contains('码率: 2000 kbps'));
      expect(quick(), contains('封装: -'));
    });

    test('三段标题齐全（播放诊断/视频/音频）', () {
      final text = quick();
      expect(text, contains('=== 播放诊断 ==='));
      expect(text, contains('=== 视频 ==='));
      expect(text, contains('=== 音频 ==='));
      expect(text, contains('位置: 00:10.0 / 01:00.0'));
      expect(text, contains('降混: 关'));
    });

    test('音频段含滤镜取证行（iOS TrueHD 无声排障）', () {
      // 区分「滤镜没写入」vs「写入了仍无声」——报告里必须能看到
      expect(quick(), contains('滤镜: (无) | codec=未知'));
      final withFilter = DiagnosticExport.buildQuick(
        playbackState: 'playing',
        mediaStatus: 'ok',
        position: '00:10.0',
        duration: '01:00.0',
        bufferedMs: 1000,
        mediaBitrate: 0,
        mediaFormat: '',
        videoCodec: 'hevc',
        videoResolution: '3840x1608',
        videoFps: 0,
        videoBitrate: 0,
        pixelFormat: 'yuv420p',
        doviProfile: 0,
        hdrType: 'SDR',
        audioCodec: 'truehd',
        audioSampleRate: 48000,
        audioChannels: 8,
        audioBitrate: 0,
        stereoDownmix: '关',
        audioFilter:
            'aformat=sample_fmts=s16|flt:channel_layouts=stereo | codec=truehd',
        textureId: 7,
        textureSize: '3840x1608',
      );
      expect(
        withFilter,
        contains(
            '滤镜: aformat=sample_fmts=s16|flt:channel_layouts=stereo | codec=truehd'),
      );
    });

    test('纹理行：null=未创建（转圈）/ 非 null 带尺寸（黑帧分叉取证）', () {
      expect(quick(), contains('纹理: null | 尺寸: -'));
      final withTexture = DiagnosticExport.buildQuick(
        playbackState: 'playing',
        mediaStatus: 'ok',
        position: '00:10.0',
        duration: '01:00.0',
        bufferedMs: 1000,
        mediaBitrate: 0,
        mediaFormat: '',
        videoCodec: 'hevc',
        videoResolution: '3840x1608',
        videoFps: 0,
        videoBitrate: 0,
        pixelFormat: 'yuv420p',
        doviProfile: 0,
        hdrType: 'SDR',
        audioCodec: 'aac',
        audioSampleRate: 0,
        audioChannels: 0,
        audioBitrate: 0,
        stereoDownmix: '关',
        audioFilter: '(无) | codec=未知',
        textureId: 3,
        textureSize: '1920x1080',
      );
      expect(withTexture, contains('纹理: 3 | 尺寸: 1920x1080'));
    });
  });
}
