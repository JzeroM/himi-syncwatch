/// mdk `log.status` 输出行的解析工具。
///
/// 纯 Dart 实现，不依赖 mdk / Flutter，便于单元测试。
///
/// mdk 未文档化状态行格式，真机样本形如：
/// ```
/// [DD 12:00:01.234][720->0][ffmpeg] | 26.4fps cache 0v 1.0s update 46.6ms
/// ```
/// 其中 `26.4fps` 是**实测**帧率，会随卡顿掉到个位数。
///
/// 陷阱：媒体信息行同样含有 `fps` 字段，但那是**声明**帧率，
/// 恒为 24/25/30 且不随卡顿变化。早期版本未区分二者，
/// 导致面板永远显示 24fps，完全掩盖了真实的掉帧。
library;

class MdkLogParser {
  const MdkLogParser._();

  /// 状态行必须同时含 `cache` 与 `fps`。
  ///
  /// 媒体信息行含 `fps` 但不含 `cache`，据此可稳定区分。
  static bool isStatusLine(String line) {
    final l = line.toLowerCase();
    return l.contains('cache') && l.contains('fps');
  }

  /// 值得关注的关键行：解码器选择、丢帧、同步修正、错误。
  ///
  /// `buffering progress` 这类进度刷屏既无诊断价值，又会在一秒内
  /// 堆出数十行把日志安全阀误触发，故不在此列。
  static const notableKeywords = <String>[
    'decoder',
    'ffmpeg',
    'dropped',
    'av_sync',
    'dovi',
    'rpu',
    'error',
    'fail',
  ];

  /// mdk 在 FINE 级输出的底层 codec 名，是硬解判定的**实证**，用来交叉
  /// 验证平台预选（推断）的结论。字段特征明确，用模式而非关键词匹配——
  /// `AMediaCodec selected video codec name` 不含既有关键词表中的任何词。
  static final notablePatterns = <RegExp>[
    RegExp(r'selected\s+(?:video|audio)\s+codec\s+name', caseSensitive: false),
    RegExp(r'AMediaCodec_createCodecByName:\s*\S', caseSensitive: false),
  ];

  static bool isNotableLine(String line) {
    final l = line.toLowerCase();
    for (final k in notableKeywords) {
      if (l.contains(k)) return true;
    }
    for (final p in notablePatterns) {
      if (p.hasMatch(line)) return true;
    }
    return false;
  }

  /// 该行是否值得保留（状态行或关键行）。
  static bool shouldKeep(String line) =>
      isStatusLine(line) || isNotableLine(line);

  /// 该行是否参与速率安全阀统计。
  ///
  /// 只有状态行（周期性刷新的播放统计）参与：正常约 4 行/秒，异常时可达
  /// 数百行/秒。`decoder.*` / `ffmpeg.*` 这类关键行在 prepare 阶段会突发
  /// 成百上千行（解码器初始化），若计入速率统计，安全阀会在开启后
  /// 0.04 秒内立刻误触发，反而一条数据都留不下。
  static bool isRateLimitedLine(String line) => isStatusLine(line);

  static final _fpsPatterns = <RegExp>[
    // 状态行内 fps 通常写作 `26.4fps`（数值在前），优先匹配该形式
    RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*fps\b', caseSensitive: false),
    // 兼容 `fps: 23.98` / `fps 23.98` / `rfps: 24.5`
    RegExp(r'\br?fps[^0-9A-Za-z]{0,3}([0-9]+(?:\.[0-9]+)?)',
        caseSensitive: false),
  ];

  /// 从状态行中提取实测帧率；非状态行一律返回 null。
  ///
  /// 0 与异常大值视为无效（启动阶段 / 解析噪声），返回 null 以免污染
  /// 时间线上的 fps 序列。
  static double? parseFps(String line) {
    if (!isStatusLine(line)) return null;
    for (final re in _fpsPatterns) {
      final m = re.firstMatch(line);
      if (m == null) continue;
      final v = double.tryParse(m.group(1)!);
      if (v != null && v > 0 && v < 1000) return v;
    }
    return null;
  }

  /// 从状态行中提取缓存时长（秒），仅用于展示，取不到时返回 null。
  ///
  /// 样本形如 `cache 0v 1.0s`。
  static double? parseCacheSeconds(String line) {
    if (!isStatusLine(line)) return null;
    final m = RegExp(
      r'cache\s+\S+\s+([0-9]+(?:\.[0-9]+)?)s',
      caseSensitive: false,
    ).firstMatch(line);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }
}
