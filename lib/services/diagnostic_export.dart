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
  /// [quickSnapshot]：可选的快速快照（[buildQuick] 输出），插在摘要之后、
  /// 解码环境之前——完整报告此前没有播放状态/帧率/码率段。
  static String build({
    required String buildSummary,
    required String diagSummary,
    required String decodeMode,
    String videoOutput = '',
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
    String? quickSnapshot,
  }) {
    final quick = (quickSnapshot == null || quickSnapshot.isEmpty)
        ? ''
        : '$quickSnapshot\n\n';
    return '$buildSummary\n\n'
        '$diagSummary\n\n'
        '$quick'
        '=== 解码环境 ===\n'
        '解码模式: $decodeMode | videoDecoders: $videoDecoders'
        '${videoOutput.isEmpty ? '' : ' | 视频输出: $videoOutput'}\n'
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

  /// 时长/位置的时钟格式：`01:02.3`，超 1 小时为 `1h02m03s`。
  static String formatClock(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final milli = ms % 1000;
    if (h > 0) {
      return '${h}h${m.toString().padLeft(2, '0')}m'
          '${s.toString().padLeft(2, '0')}s';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.${(milli ~/ 100)}';
  }

  /// 帧率行值：保留 1 位小数；取不到（0 或负值，探测未完成）显示 `-`，
  /// 避免导出报告出现 `0.0fps` 与 `59.940000000000005fps` 这类噪音。
  static String formatFps(double fps) =>
      fps > 0 ? '${fps.toStringAsFixed(1)}fps' : '-';

  /// 码率行值：0 表示 mediaInfo 未给出码率，显示 `-` 而非误导的 `0 kbps`。
  static String formatBitrate(int kbps) => kbps > 0 ? '$kbps kbps' : '-';

  /// 快速诊断快照：播放诊断 / 视频 / 音频 三段。
  ///
  /// 面板「复制诊断」与播放器完整报告共用（经 [build] 的 quickSnapshot
  /// 参数），保证两处字段与格式化完全一致——此前面板导出用原始插值，
  /// 帧率输出 `0.0fps`/长小数、码率 0 输出 `0kbps`，与面板 UI 行的
  /// `-` 格式互相矛盾。
  static String buildQuick({
    required String playbackState,
    required String mediaStatus,
    required String position,
    required String duration,
    required int bufferedMs,
    required int mediaBitrate,
    required String mediaFormat,
    required String videoCodec,
    required String videoResolution,
    required double videoFps,
    required int videoBitrate,
    required String pixelFormat,
    required int doviProfile,
    required String hdrType,
    required String audioCodec,
    required int audioSampleRate,
    required int audioChannels,
    required int audioBitrate,
    required String stereoDownmix,
    required String audioFilter,
    required int? textureId,
    required String textureSize,
    String videoFilter = '(未写入)',
  }) {
    return '=== 播放诊断 ===\n'
        '状态: $playbackState | 媒体: $mediaStatus\n'
        '位置: $position / $duration\n'
        '缓冲区: ${bufferedMs}ms\n'
        '码率: ${formatBitrate(mediaBitrate)} | '
        '封装: ${mediaFormat.isEmpty ? '-' : mediaFormat}\n\n'
        '=== 视频 ===\n'
        '编码: $videoCodec | 分辨率: $videoResolution\n'
        '帧率: ${formatFps(videoFps)} | 码率: ${formatBitrate(videoBitrate)}\n'
        '像素: $pixelFormat | DOVI: ${doviProfile > 0 ? 'P$doviProfile' : '-'}\n'
        'HDR: $hdrType\n'
        // 非标尺寸黑屏取证：滤镜串=null(未写入)/(无)=已对齐或已清
        '视频滤镜: $videoFilter\n'
        // Android 盒子黑帧取证：textureId null=纹理未创建（UI 转圈），
        // 非 null 仍黑=纹理存在但无帧合成（Impeller/插件错配方向）
        '纹理: ${textureId ?? 'null'} | 尺寸: $textureSize\n\n'
        '=== 音频 ===\n'
        '编码: $audioCodec | 采样率: ${audioSampleRate > 0 ? '${audioSampleRate}Hz' : '-'}\n'
        '声道: ${audioChannels > 0 ? '${audioChannels}ch' : '-'} | '
        '码率: ${formatBitrate(audioBitrate)}\n'
        '降混: $stereoDownmix\n'
        // iOS TrueHD 无声取证：区分「滤镜没写入」vs「写入了仍无声」
        '滤镜: $audioFilter';
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
