import 'package:himi_syncwatch/models/media_item.dart';

/// 视频版本（多版本 MediaSource）偏好维度，顺序即优先级（越靠前越高）。
///
/// 用于：① 详情页「可用版本」列表排序与默认高亮；② 版本选择器排序。
/// 纯数据 + 纯排序逻辑，无 IO，便于单测。
enum VersionPreference {
  highBitrate('高码率优先'),
  hdr('HDR优先'),
  dolbyVision('杜比优先'),
  lowBitrate('低码率优先'),
  serverDefault('由服务决定'),
  sdr('SDR优先');

  final String label;
  const VersionPreference(this.label);

  /// 默认优先级（与设置面板初始顺序一致）。
  static const List<VersionPreference> defaults = [
    highBitrate,
    hdr,
    dolbyVision,
    lowBitrate,
    serverDefault,
    sdr,
  ];

  /// 逗号分隔的持久化键（`name`）→ 列表；缺失项按默认顺序补齐到末尾，
  /// 保证新增维度时旧存档仍完整。
  static List<VersionPreference> decode(String? csv) {
    final out = <VersionPreference>[];
    for (final part in (csv ?? '').split(',')) {
      final key = part.trim();
      if (key.isEmpty) continue;
      for (final v in values) {
        if (v.name == key && !out.contains(v)) out.add(v);
      }
    }
    for (final v in defaults) {
      if (!out.contains(v)) out.add(v);
    }
    return out;
  }

  /// 列表 → 逗号分隔键。
  static String encode(List<VersionPreference> order) =>
      order.map((e) => e.name).join(',');
}

/// 按 [order] 对多版本 [sources] 排序（高优先级在前）。
///
/// 逐条比较：命中首个能区分两者的维度即定序；`serverDefault` 恒为平局
/// （不干预）；最终以 **原始（服务端）顺序** 兜底（稳定）。返回副本，不改
/// 原列表。
List<MediaSource> sortSourcesByPreference(
  List<MediaSource> sources,
  List<VersionPreference> order,
) {
  final indexed = List.generate(sources.length, (i) => (i, sources[i]));
  indexed.sort((a, b) {
    final c = _compare(a.$2, b.$2, order);
    if (c != 0) return c;
    return a.$1.compareTo(b.$1); // 稳定：保留服务端顺序
  });
  return [for (final e in indexed) e.$2];
}

/// 偏好最高的版本（排序后首个）。
MediaSource? preferredSource(
  List<MediaSource> sources,
  List<VersionPreference> order,
) {
  if (sources.isEmpty) return null;
  return sortSourcesByPreference(sources, order).first;
}

/// a 相对 b 的比较：负 = a 更靠前。
int _compare(
  MediaSource a,
  MediaSource b,
  List<VersionPreference> order,
) {
  for (final pref in order) {
    switch (pref) {
      case VersionPreference.highBitrate:
        final c = b.effectiveBitrate.compareTo(a.effectiveBitrate);
        if (c != 0) return c;
      case VersionPreference.lowBitrate:
        final c = a.effectiveBitrate.compareTo(b.effectiveBitrate);
        if (c != 0) return c;
      case VersionPreference.hdr:
        final c = _boolFirst(a.isHdr, b.isHdr);
        if (c != 0) return c;
      case VersionPreference.sdr:
        final c = _boolFirst(!a.isHdr, !b.isHdr);
        if (c != 0) return c;
      case VersionPreference.dolbyVision:
        final c = _boolFirst(a.isDolbyVision, b.isDolbyVision);
        if (c != 0) return c;
      case VersionPreference.serverDefault:
        break; // 不干预
    }
  }
  return 0;
}

/// true 一方更靠前：`a=true,b=false` → -1。
int _boolFirst(bool a, bool b) {
  if (a == b) return 0;
  return a ? -1 : 1;
}
