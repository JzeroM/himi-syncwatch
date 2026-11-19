import 'player_adapter.dart';

/// 695：媒体徽章 + 「视频详细信息」聚合。
///
/// 【架构】对 `anime4kStatus` 同款「Dart 产数据、壳只渲染」模式：
/// 四壳（Flutter / Qt QML / Android Kotlin / 鸿蒙 ArkTS）显示的徽章与
/// 详情条目全部由本文件格式化好（**标签中文、值英文**），经
/// `NativePlayerState` 管道透传，壳不做任何计算。
///
/// 【口径】仿 mpv `i` 统计页四段：文件 / 显示 / 视频 / 音频。静态项来自
/// 引擎 `PlayerMediaInfo`；运行时项来自 mpv 属性回读；**无值项整行省略**
///（MDK/Erika 缺指标就少几行，不显示错误数据）。
class MediaInfoRow {
  const MediaInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  Map<String, Object?> toJson() => {'label': label, 'value': value};
}

class MediaInfoGroup {
  const MediaInfoGroup({required this.title, required this.rows});

  final String title;
  final List<MediaInfoRow> rows;

  Map<String, Object?> toJson() =>
      {'title': title, 'rows': [for (final r in rows) r.toJson()]};
}

class MediaInfoSummary {
  const MediaInfoSummary({required this.badges, required this.groups});

  final List<String> badges;
  final List<MediaInfoGroup> groups;

  Map<String, Object?> toJson() => {
        'badges': badges,
        'groups': [for (final g in groups) g.toJson()],
      };
}

/// 徽章格式化（进度条上方胶囊行）：无值省略。
///
/// 示例输出：`['4K', 'DV P5', 'HEVC', '60.0 fps', '29Mbps', '20.50G']`。
List<String> buildMediaBadges({
  int width = 0,
  int height = 0,
  int doviProfile = 0,
  bool hdr10 = false,
  bool hlg = false,
  String? codecName,
  double? fps,
  int bitRateBps = 0,
  int? fileBytes,
}) {
  final out = <String>[];
  final tier = resolutionTier(width, height);
  if (tier != null) out.add(tier);
  if (doviProfile > 0) {
    out.add('DV P$doviProfile');
  } else if (hdr10) {
    out.add('HDR10');
  } else if (hlg) {
    out.add('HLG');
  }
  final codec = codecShortName(codecName);
  if (codec != null) out.add(codec);
  if (fps != null && fps > 0) out.add('${fps.toStringAsFixed(1)} fps');
  if (bitRateBps > 0) out.add(formatMbpsBadge(bitRateBps));
  if (fileBytes != null && fileBytes > 0) out.add(formatSizeBadge(fileBytes));
  return out;
}

/// 分辨率档位徽章：4K / 2K / 1080P / 720P；无分辨率返回 null。
String? resolutionTier(int width, int height) {
  if (width <= 0 && height <= 0) return null;
  if (width >= 3840 || height >= 2160) return '4K';
  if (width >= 2560 || height >= 1440) return '2K';
  if (width >= 1920 || height >= 1080) return '1080P';
  if (width >= 1280 || height >= 720) return '720P';
  return '${height > 0 ? height : width}P';
}

/// 编码短名：hevc→HEVC、h264→H.264、av1→AV1，其余原样大写。
String? codecShortName(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final lower = raw.toLowerCase();
  if (lower.contains('hevc') || lower.contains('h265')) return 'HEVC';
  if (lower.contains('h264') || lower.contains('avc')) return 'H.264';
  if (lower.contains('av1')) return 'AV1';
  return raw.toUpperCase();
}

/// 码率徽章：≥10Mbps 取整，否则一位小数（'29Mbps' / '9.8Mbps'）。
String formatMbpsBadge(int bitRateBps) {
  final mbps = bitRateBps / 1e6;
  return mbps >= 10
      ? '${mbps.round()}Mbps'
      : '${mbps.toStringAsFixed(1)}Mbps';
}

/// 大小徽章：GiB 两位小数（'20.50G'，与详情面板 GiB 口径一致），不足 1G 用 M。
String formatSizeBadge(int bytes) {
  const gib = 1 << 30;
  const mib = 1 << 20;
  if (bytes >= gib) return '${(bytes / gib).toStringAsFixed(2)}G';
  return '${(bytes / mib).round()}M';
}

/// 详情面板数据源（全部可空；空则对应行省略）。
class MediaInfoSource {
  const MediaInfoSource({
    this.fileName,
    this.fileBytes,
    this.container,
    this.cacheText,
    this.vo,
    this.gpuContext,
    this.refreshRateHz,
    this.droppedDecoder,
    this.droppedOutput,
    this.videoCodecDesc,
    this.hwdec,
    this.fps,
    this.width,
    this.height,
    this.pixelFormat,
    this.colorMatrix,
    this.primaries,
    this.transfer,
    this.hdr10Text,
    this.videoBitrateBps,
    this.audioCodecDesc,
    this.channels,
    this.sampleRateHz,
    this.audioBitrateBps,
  });

  final String? fileName;
  final int? fileBytes;
  final String? container;
  final String? cacheText;

  final String? vo;
  final String? gpuContext;
  final double? refreshRateHz;
  final int? droppedDecoder;
  final int? droppedOutput;

  final String? videoCodecDesc;
  final String? hwdec;
  final double? fps;
  final int? width;
  final int? height;
  final String? pixelFormat;
  final String? colorMatrix;
  final String? primaries;
  final String? transfer;
  final String? hdr10Text;
  final int? videoBitrateBps;

  final String? audioCodecDesc;
  final int? channels;
  final int? sampleRateHz;
  final int? audioBitrateBps;
}

/// 构建详情面板四组（文件/显示/视频/音频）。每条信息**纵向独占一行**，
/// 标签中文、值英文；值缺失整行省略；整组无行则整组省略。
List<MediaInfoGroup> buildMediaInfoGroups(MediaInfoSource s) {
  String sizeText(int b) {
    final gib = b / (1 << 30);
    return gib >= 1
        ? '${gib.toStringAsFixed(3)} GiB'
        : '${(b / (1 << 20)).toStringAsFixed(1)} MiB';
  }

  final groups = <MediaInfoGroup>[];

  void add(String title, List<MediaInfoRow> rows) {
    if (rows.isNotEmpty) groups.add(MediaInfoGroup(title: title, rows: rows));
  }

  add('文件', [
    if (s.fileName != null && s.fileName!.isNotEmpty)
      MediaInfoRow(label: '文件名', value: s.fileName!),
    if (s.fileBytes != null && s.fileBytes! > 0)
      MediaInfoRow(label: '大小', value: sizeText(s.fileBytes!)),
    if (s.container != null && s.container!.isNotEmpty)
      MediaInfoRow(label: '格式/协议', value: s.container!),
    if (s.cacheText != null && s.cacheText!.isNotEmpty)
      MediaInfoRow(label: '缓存', value: s.cacheText!),
  ]);

  add('显示', [
    if (s.vo != null && s.vo!.isNotEmpty)
      MediaInfoRow(label: '渲染器', value: s.vo!),
    if (s.gpuContext != null && s.gpuContext!.isNotEmpty)
      MediaInfoRow(label: '图形上下文', value: s.gpuContext!),
    if (s.refreshRateHz != null && s.refreshRateHz! > 0)
      MediaInfoRow(label: '刷新率', value: '${s.refreshRateHz!.round()} Hz'),
    if (s.droppedDecoder != null || s.droppedOutput != null)
      MediaInfoRow(
        label: '丢帧（解码/输出）',
        value: '${s.droppedDecoder ?? 0} / ${s.droppedOutput ?? 0}',
      ),
  ]);

  add('视频', [
    if (s.videoCodecDesc != null && s.videoCodecDesc!.isNotEmpty)
      MediaInfoRow(label: '视频编码', value: s.videoCodecDesc!),
    if (s.hwdec != null && s.hwdec!.isNotEmpty)
      MediaInfoRow(label: '硬件解码', value: s.hwdec!),
    if (s.fps != null && s.fps! > 0)
      MediaInfoRow(label: '帧率', value: '${s.fps!.round()} fps'),
    if (s.width != null && s.width! > 0 && (s.height ?? 0) > 0)
      MediaInfoRow(label: '分辨率', value: '${s.width} x ${s.height}'),
    if (s.pixelFormat != null && s.pixelFormat!.isNotEmpty)
      MediaInfoRow(label: '像素格式', value: s.pixelFormat!),
    if (s.colorMatrix != null && s.colorMatrix!.isNotEmpty)
      MediaInfoRow(label: '色域矩阵', value: s.colorMatrix!),
    if (s.primaries != null && s.primaries!.isNotEmpty)
      MediaInfoRow(label: '色彩原色', value: s.primaries!),
    if (s.transfer != null && s.transfer!.isNotEmpty)
      MediaInfoRow(label: '传输特性', value: s.transfer!),
    if (s.hdr10Text != null && s.hdr10Text!.isNotEmpty)
      MediaInfoRow(label: 'HDR10 亮度', value: s.hdr10Text!),
    if (s.videoBitrateBps != null && s.videoBitrateBps! > 0)
      MediaInfoRow(
        label: '码率',
        value: '${(s.videoBitrateBps! / 1e6).toStringAsFixed(3)} Mbps',
      ),
  ]);

  add('音频', [
    if (s.audioCodecDesc != null && s.audioCodecDesc!.isNotEmpty)
      MediaInfoRow(label: '音频编码', value: s.audioCodecDesc!),
    if (s.channels != null && s.channels! > 0)
      MediaInfoRow(label: '声道', value: '${s.channels}'),
    if (s.sampleRateHz != null && s.sampleRateHz! > 0)
      MediaInfoRow(label: '采样率', value: '${s.sampleRateHz} Hz'),
    if (s.audioBitrateBps != null && s.audioBitrateBps! > 0)
      MediaInfoRow(label: '码率', value: '${(s.audioBitrateBps! / 1000).round()} kbps'),
  ]);

  return groups;
}

/// 从引擎 [AdapterMediaInfo] 抽取静态视频/音频信息（壳无关、可单测）。
MediaInfoSource mediaInfoFromPlayer(AdapterMediaInfo? info,
    {String? fileName}) {
  final v = (info != null && info.video.isNotEmpty) ? info.video.first : null;
  final a = (info != null && info.audio.isNotEmpty) ? info.audio.first : null;
  return MediaInfoSource(
    fileName: fileName,
    videoCodecDesc: codecShortName(v?.codec),
    width: v?.width,
    height: v?.height,
    pixelFormat: (v == null || v.formatName.isEmpty) ? null : v.formatName,
    videoBitrateBps: (v == null || v.bitRate <= 0) ? null : v.bitRate,
    audioCodecDesc: a == null ? null : codecShortName(a.codec),
    channels: (a == null || a.channels <= 0) ? null : a.channels,
    sampleRateHz: (a == null || a.sampleRate <= 0) ? null : a.sampleRate,
    audioBitrateBps: (a == null || a.bitRate <= 0) ? null : a.bitRate,
  );
}
