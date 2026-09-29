/// 卡顿诊断报告的文本组装。
///
/// 纯 Dart、不依赖 Flutter，便于单元测试——报告是排障的主要输出，
/// 「某个字段到底有没有进报告」必须有断言兜底：v1.1.16 曾把实际解码器
/// 只加在面板的另一个导出函数里，用户实际点的那个按钮根本没带上。
library;

import 'decoder_report.dart';

class DiagnosticExport {
  const DiagnosticExport._();

  /// 组装完整诊断报告。
  ///
  /// 各段内容由调用方从 [PlaybackDiagnostics] 与状态采集器取来传入，
  /// 本类只负责拼装与排序，不持有任何状态。
  static String build({
    required String buildSummary,
    required String diagSummary,
    required String decodeMode,
    required String videoDecoders,
    required bool isDolbyVisionContent,
    required String dvCapability,
    required DecoderReport decoderReport,
    required String mdkRawDecoder,
    required int bufProgress,
    required String timeline,
    required String stalls,
    required String events,
    required String notes,
    required String statusLines,
    required String notableLines,
  }) {
    return '$buildSummary\n\n'
        '$diagSummary\n\n'
        '=== 解码环境 ===\n'
        '解码模式: $decodeMode | videoDecoders: $videoDecoders\n'
        '实际解码: ${decoderReport.video.display}\n'
        'mdk原值: $mdkRawDecoder\n'
        '音频实际: ${decoderReport.audio.display}\n'
        '${formatPredicted(decoderReport)}\n'
        'DV 内容: $isDolbyVisionContent\n'
        'DV 能力: $dvCapability\n'
        '${formatBufProgress(bufProgress)}\n\n'
        '=== 时间线 ===\n$timeline\n'
        '=== 卡顿事件 ===\n$stalls\n'
        '=== mdk 事件原文 ===\n$events'
        '=== 诊断事件 ===\n$notes\n'
        '=== mdk 状态行 (fps/cache) ===\n$statusLines\n\n'
        '=== mdk 关键行 (解码器/丢帧/错误) ===\n$notableLines';
  }

  /// 缓冲进度行。
  ///
  /// 源自 mdk `reader.buffering` 事件的 error 字段（0-100），是区分
  /// 「网络喂不进」与「解码跟不上」的关键证据，此前只在面板上瞬时显示、
  /// 从不进报告。-1 表示尚未收到该事件。
  static String formatBufProgress(int bufProgress) {
    if (bufProgress < 0) return '缓冲进度: 未知 (尚未收到 reader.buffering)';
    if (bufProgress > 100) return '缓冲进度: $bufProgress% (异常值)';
    return '缓冲进度: $bufProgress% (mdk reader.buffering, 0-100)';
  }

  /// 探测预选行：DV 能力探测的**预测**值，单列以与实测真值对照。
  ///
  /// 必须与「实际解码」分开——真机上二者并不一致（视频预测
  /// `c2.dolby.decoder.hevc`、实测 `c2.qti.hevc.decoder`；音频预测
  /// `c2.dolby.eac3.decoder.eac3`、实测走 FFmpeg），
  /// 混成一行会给出 `FFmpeg → c2.dolby...` 这种自相矛盾的结论。
  static String formatPredicted(DecoderReport report) {
    final v = report.video.codec;
    final a = report.audio.codec;
    if (v.isEmpty && a.isEmpty) return '探测预选: 未探测';
    final sb = StringBuffer('探测预选:');
    if (v.isNotEmpty) sb.write(' video=$v');
    if (a.isNotEmpty) sb.write(' audio=$a');
    return sb.toString();
  }
}
