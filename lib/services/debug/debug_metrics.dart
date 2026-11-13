import 'dart:convert';

/// 697：播放调试面板的数据模型（纯 Dart，无 IO，便于单测）。
///
/// ## 设计原则
///
/// **扁平键值 + 分组**，而不是嵌套对象。原因：
/// 1. 四端渲染（Flutter / Android / HarmonyOS / Windows Qt）只需遍历
///    `(标签, 值)` 二元组，不需要各自理解业务字段含义
/// 2. 新增指标只改采集侧，四端渲染零改动
/// 3. 一键复制/导出时天然是「标签: 值」的文本格式
///
/// ## 为什么按「分组」而不是「平铺」
///
/// HDR/DV 排查需要快速定位「输入是什么、输出是什么、中间映射是什么」。
/// 平铺 50+ 行会让人找不到重点，分组后可折叠、可聚焦。
class DebugMetrics {
  const DebugMetrics(this.groups);

  /// 分组列表（有序，渲染按此顺序）。
  final List<DebugMetricGroup> groups;

  /// 空指标（面板未就绪时用）。
  static const empty = DebugMetrics([]);

  /// 是否无任何指标。
  bool get isEmpty => groups.every((g) => g.rows.isEmpty);

  /// 转成可复制的纯文本（用于「复制诊断」按钮）。
  ///
  /// 格式：
  /// ```
  /// ## 播放
  /// 状态: playing
  /// 位置: 00:12:34 / 00:45:00
  /// ## HDR 输入
  /// 色域: bt.2020
  /// ```
  String toPlainText() {
    final buf = StringBuffer();
    for (final g in groups) {
      if (g.rows.isEmpty) continue;
      buf.writeln('## ${g.title}');
      for (final r in g.rows) {
        buf.writeln('${r.label}: ${r.value}');
      }
    }
    return buf.toString().trimRight();
  }

  @override
  String toString() => 'DebugMetrics(${groups.length} groups)';
}

/// 一个指标分组（如「HDR 输入」）。
class DebugMetricGroup {
  const DebugMetricGroup({
    required this.title,
    required this.rows,
    this.highlight = false,
  });

  final String title;
  final List<DebugMetricRow> rows;

  /// 是否高亮（HDR/DV 等关键分组，UI 用主色标题）。
  final bool highlight;

  DebugMetricGroup copyWith({List<DebugMetricRow>? rows}) =>
      DebugMetricGroup(
        title: title,
        rows: rows ?? this.rows,
        highlight: highlight,
      );
}

/// 单条指标（标签 + 值 + 可选状态色）。
class DebugMetricRow {
  const DebugMetricRow(this.label, this.value, {this.severity = Severity.normal});

  final String label;
  final String value;

  /// 值的重要性（决定显示颜色）。
  ///
  /// - [Severity.normal]：普通（白 70%）
  /// - [Severity.good]：正常/成功（绿）
  /// - [Severity.warn]：可疑/降级（琥珀）
  /// - [Severity.error]：异常/失败（红）
  final Severity severity;

  @override
  String toString() => '$label=$value';
}

/// 指标值的状态色。
enum Severity { normal, good, warn, error }

/// 697：从 mpv 的 `video-params` JSON 解析 HDR/DV 输入信息。
///
/// ## 为什么单独抽出来
///
/// ## 数据来源（必须按 mpv 源码为准）
///
/// 色彩元数据来自 `video-params`，DV Profile/Level 来自
/// **`current-tracks/video`**（不是 `video-params`！）：
///
/// ```
/// video-params/primaries            → "bt.2020"
/// video-params/gamma                → "pq"
/// video-params/sig-peak             → 5.0  ← 归一化，×100 = nits
/// video-params/pixelformat          → "yuv420p10"
/// current-tracks/video/dolby-vision-profile → 5 / 8
/// current-tracks/video/dolby-vision-level   → 6
/// ```
///
/// 【697 真机回归：鸿蒙 P5 显示「非 DV 内容」】两个错误假设：
/// 1. `video-params` 里**没有** `dovi-profile` 字段（mpv `cmd.c`
///    `property_imgparams` 的字段表里不存在）→ 恒解析出 0
/// 2. `sig-peak` 是 `max_luma / MP_REF_WHITE(100)` 的**倍数**，不是 nits
///    → 5 实际是 500 nits，直接显示会差 100 倍
///
/// 注意与 `video-out-params`（**输出**信息）区分：HDR 排查必须同时看
/// 输入和输出，否则无法判断「是片源没识别」还是「映射错了」。
class VideoColorInfo {
  const VideoColorInfo({
    this.pixelFormat = '',
    this.width = 0,
    this.height = 0,
    this.primaries = '',
    this.gamma = '',
    this.sigPeak = 0,
    this.minLuma = 0,
    this.maxLuma = 0,
    this.doviProfile = 0,
    this.doviLevel = 0,
    this.raw = const {},
  });

  final String pixelFormat;
  final int width;
  final int height;

  /// 输入色域（`bt.2020` / `bt.709` / `display-p3`）。
  final String primaries;

  /// 输入 transfer（`pq` / `hlg` / `bt.1886`）。
  final String gamma;

  /// 信号峰值，**归一化倍数**（mpv `sig-peak` = `max_luma / 100`）。
  ///
  /// 显示 nits 请用 [sigPeakNits]。
  final double sigPeak;

  final double minLuma;
  final double maxLuma;

  /// 杜比视界 Profile（5 / 7 / 8 / 8.4）；0 = 非 DV。
  ///
  /// 来源：`current-tracks/video/dolby-vision-profile`。
  /// mpv 读不到时为 0，此时应回退 Emby 元数据（见
  /// `DebugMetricsCollector` 的 Emby 兜底）。
  final int doviProfile;

  /// 杜比视界 Level（决定最大码率/分辨率）。
  final int doviLevel;

  /// 原始 JSON（排查时可能需要未解析字段）。
  final Map<String, Object?> raw;

  /// 信号峰值（nits）。
  ///
  /// mpv 的 `sig-peak` 是 `max_luma / MP_REF_WHITE`（MP_REF_WHITE = 100）
  /// 的**归一化倍数**，不是绝对亮度。5 → 500 nits。
  double get sigPeakNits => sigPeak * 100;

  /// 是否杜比视界内容。
  bool get isDolbyVision => doviProfile > 0;

  /// 是否 HDR 内容（PQ 或 HLG transfer）。
  bool get isHdr => gamma == 'pq' || gamma == 'hlg';

  /// 是否 HLG（与 PQ 区分，输出 target-trc 不同）。
  bool get isHlg => gamma == 'hlg';

  /// 位深（从 pixelformat 推断，如 `yuv420p10` → 10）。
  int get bitDepth {
    final m = RegExp(r'p(\d+)$').firstMatch(pixelFormat);
    if (m == null) return pixelFormat.contains('10') ? 10 : 8;
    final v = int.tryParse(m.group(1)!) ?? 8;
    return v <= 8 ? 8 : v;
  }

  /// DV Profile 的可读标签（`P5` / `P8.4`）。
  String get doviLabel {
    if (doviProfile <= 0) return '';
    // mpv 对 8.4 报 profile=8 + 特殊 el 标记，这里按 level 粗略区分
    return 'P$doviProfile';
  }

  /// 从 mpv 的**标量子属性**构建（697 起的推荐路径）。
  ///
  /// 【为什么不用 JSON】鸿蒙的 mpv 封装只暴露 `getProperty`(number) /
  /// `getPropertyBool` / `getPropertyString`，**不支持 NODE**——
  /// `video-params` 整块读出来是空串。改读标量子属性后三端同构。
  ///
  /// [props] 的键就是 mpv 属性路径（见 [propertyNames]）。
  /// 全部缺失时返回 null（尚未起播）。
  static VideoColorInfo? fromProperties(Map<String, String> props) {
    if (props.isEmpty) return null;
    final primaries = props['video-params/primaries'] ?? '';
    final gamma = props['video-params/gamma'] ?? '';
    final pixelFormat = props['video-params/pixelformat'] ?? '';
    if (primaries.isEmpty &&
        gamma.isEmpty &&
        pixelFormat.isEmpty &&
        (props['video-params/w'] ?? '').isEmpty) {
      return null;
    }
    double d(String k) => double.tryParse(props[k] ?? '') ?? 0;
    int i(String k) => int.tryParse(props[k] ?? '') ?? 0;
    return VideoColorInfo(
      pixelFormat: pixelFormat,
      width: i('video-params/w'),
      height: i('video-params/h'),
      primaries: primaries,
      gamma: gamma,
      sigPeak: d('video-params/sig-peak'),
      minLuma: d('video-params/min-luma'),
      maxLuma: d('video-params/max-luma'),
      // DV 在 current-tracks/video 下，不在 video-params（mpv 源码实证）
      doviProfile: i('current-tracks/video/dolby-vision-profile'),
      doviLevel: i('current-tracks/video/dolby-vision-level'),
      raw: props,
    );
  }

  /// 需要读取的 mpv 属性路径（**标量**，三端通用）。
  ///
  /// 这张表是「mpv 到底暴露了什么」的唯一真相源：加字段前必须先在
  /// mpv 源码 `player/command.c` 里核实，不能凭印象写。
  static const propertyNames = <String>[
    'video-params/primaries',
    'video-params/gamma',
    'video-params/sig-peak',
    'video-params/pixelformat',
    'video-params/w',
    'video-params/h',
    'video-params/min-luma',
    'video-params/max-luma',
    'current-tracks/video/dolby-vision-profile',
    'current-tracks/video/dolby-vision-level',
  ];

  /// 从 mpv `video-params` JSON 字符串解析；失败返回 null。
  ///
  /// 【保留原因】Windows 走 media_kit，NODE 可读；且 `_parseVideoParams`
  /// 的事件通道本来就是 JSON。标量路径是鸿蒙/安卓的主路径。
  static VideoColorInfo? tryParse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = decoded.cast<String, Object?>();
      double d(String key) => (m[key] as num?)?.toDouble() ?? 0;
      int i(String key) => (m[key] as num?)?.toInt() ?? 0;
      return VideoColorInfo(
        pixelFormat: (m['pixelformat'] as String?) ?? '',
        width: i('w'),
        height: i('h'),
        primaries: (m['primaries'] as String?) ?? '',
        gamma: (m['gamma'] as String?) ?? '',
        sigPeak: d('sig-peak'),
        minLuma: d('min-luma'),
        maxLuma: d('max-luma'),
        // 【不要在这里解析 dovi-profile】mpv 的 `video-params` 里**没有**
        // 这个字段（DV 在 `current-tracks/video` 下）。697 曾凭空写它，
        // 导致鸿蒙把 P5 显示成「非 DV 内容」。DV 走 [fromProperties]。
        raw: m,
      );
    } catch (_) {
      return null;
    }
  }
}
