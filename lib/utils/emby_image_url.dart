/// Emby 图片按需取图工具（698 N4/N5-A）：**分槽位**请求尺寸贴合显示 +
/// 同宽解码。
///
/// 模型层图片 URL 是**小图档**（`maxHeight=400`）或**无尺寸原图**（Logo
/// `?tag=`），直接放大显示会糊（详情页/轮播 hero 区达 600+ 逻辑高），直接
/// 下载原图会慢（Logo 常为数 MB 透明 PNG）。Emby 图片端点按 `tag` 服务端
/// 缩放，重写 query 的尺寸参数即可**同时**解决「糊」与「慢」。
///
/// 槽位分档借鉴 SenPlayer 的 ImageKit 策略表（`media-card:poster:w540:q90`/
/// `media-detail:large:portraitDetail:3000x4500:q90` 逐槽定档：卡片小图省
/// 流量、hero 大图宁大勿糊）。
library;

/// 图片槽位（698 N5-A）：不同 UI 位置的取图策略不同。
enum EmbyImageSlot {
  /// 轮播/详情 hero 大图：宁大勿糊（cap 1600，q90）。
  hero,

  /// 标题艺术字 Logo（透明 PNG）：不抠质量（cap 800，q100）。
  logo,

  /// 网格/列表卡片海报：小而清晰（cap 540，q85，对齐 w540 同档）。
  card,
}

/// 槽位策略表（698 N5-A/N7-D，借 SenPlayer 分档）。
class EmbyImagePolicy {
  const EmbyImagePolicy({
    required this.minWidth,
    required this.maxWidth,
    required this.quality,
    this.maxDpr = 2,
  });

  final int minWidth;
  final int maxWidth;
  final int quality;

  /// dpr 封顶（N7-D）：hero 宁大勿糊用满物理像素（封 3）；小件封 2 省流量。
  final double maxDpr;
}

const Map<EmbyImageSlot, EmbyImagePolicy> embyImagePolicies = {
  // hero：宁大勿糊（N7-D）——上限 3000 对齐 SenPlayer media-detail:large
  //（3000x4500/3000x1688 q90）档；dpr 封 3，3x 屏用满物理像素。
  EmbyImageSlot.hero:
      EmbyImagePolicy(minWidth: 600, maxWidth: 3000, quality: 90, maxDpr: 3),
  EmbyImageSlot.logo: EmbyImagePolicy(minWidth: 300, maxWidth: 800, quality: 100),
  EmbyImageSlot.card: EmbyImagePolicy(minWidth: 300, maxWidth: 540, quality: 85),
};

/// 设备感知目标宽（物理像素，已含 dpr）：`逻辑宽 × min(dpr, [dprCap])`，
/// 按槽位 [EmbyImagePolicy] 钳位。
int embyImageTargetWidth(
  double logicalWidth,
  double devicePixelRatio, {
  int? min,
  int? max,
  double dprCap = 2,
}) {
  final dpr = devicePixelRatio < dprCap ? devicePixelRatio : dprCap;
  final pixels = logicalWidth * dpr;
  return pixels
      .clamp((min ?? 600).toDouble(), (max ?? 1600).toDouble())
      .round();
}

/// 槽位目标宽便捷入口。
int embyImageSlotWidth(
  EmbyImageSlot slot,
  double logicalWidth,
  double devicePixelRatio,
) {
  final p = embyImagePolicies[slot]!;
  return embyImageTargetWidth(
    logicalWidth,
    devicePixelRatio,
    min: p.minWidth,
    max: p.maxWidth,
    dprCap: p.maxDpr,
  );
}

/// 按目标宽 [targetWidth] 重写 Emby 图片 URL 的尺寸参数（698 N4/N4-5）：
///
/// - `maxHeight=400` 小图档（Poster/Backdrop）→ `maxWidth=$w` +
///   `quality=$quality`（未带 quality 时）；
/// - **无尺寸参数的原图**（Logo `?tag=…`）→ 追加 `maxWidth=$w&quality=$quality`；
/// - 已带尺寸（虚化层 `maxWidth=320` 小图、宽幅档）或非 Emby 图片 URL
///   （无 `/Images/` 形态、外部图床）→ **原样透传**，绝不误改。
///
/// 只改 query，`tag` 不动——Emby 按 tag 校验资源，缓存键随之变化属预期。
String? embyImageUrlFor(
  String? url,
  int targetWidth, {
  int quality = 85,
}) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  final query = Map<String, String>.from(uri.queryParameters);
  final isEmbyImage =
      uri.path.contains('/Items/') && uri.path.contains('/Images/');
  final hasSize = query.containsKey('maxWidth') || query.containsKey('maxHeight');

  if (query['maxHeight'] == '400') {
    // 小图档 → 按显示宽请求（服务端缩放）。
    query.remove('maxHeight');
    query['maxWidth'] = '$targetWidth';
  } else if (isEmbyImage && !hasSize && query.containsKey('tag')) {
    // 无尺寸原图（Logo）→ 追加尺寸提示。
    query['maxWidth'] = '$targetWidth';
  } else {
    // 已带尺寸（虚化小图/宽幅档）或非 Emby 图片：透传。
    return url;
  }

  if (!query.containsKey('quality')) query['quality'] = '$quality';
  return uri.replace(queryParameters: query).toString();
}

/// 槽位取图便捷入口：目标宽与 quality 都按槽位策略。
String? embyImageUrlForSlot(
  String? url,
  EmbyImageSlot slot,
  double logicalWidth,
  double devicePixelRatio,
) {
  final p = embyImagePolicies[slot]!;
  return embyImageUrlFor(
    url,
    embyImageSlotWidth(slot, logicalWidth, devicePixelRatio),
    quality: p.quality,
  );
}
