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
      );

  group('DiagnosticExport 解码环境', () {
    // 回归保护：这些字段曾只加在面板的另一个导出函数里，
    // 用户实际点的「复制卡顿诊断」按钮走的是本函数，根本没带上。
    test('实际解码 / mdk原值 / 音频实际三行必须进入报告', () {
      final report = build(
        decoderReport: const DecoderReport(
          video: DecoderTrack(
            framework: 'AMediaCodec',
            codec: 'c2.qti.hevc.decoder',
            codecIsSoftware: false,
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
      expect(report.split('\n').first,
          '产物身份: 1.1.16+186 | DV通道已注册');
    });

    test('产物缺原生插件时首行直接点明', () {
      final report = build(
        buildSummary: '产物身份: 未知 | DV通道未注册(产物缺原生插件)',
      );
      expect(report.split('\n').first,
          '产物身份: 未知 | DV通道未注册(产物缺原生插件)');
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
      expect(DiagnosticExport.formatBufProgress(150),
          '缓冲进度: 150% (异常值)');
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
  });
}
