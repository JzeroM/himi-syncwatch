/// Emby 图片按需取图工具（698 N4）：请求尺寸贴合显示尺寸 + 同宽解码。
///
/// 模型层图片 URL 是**小图档**（`maxHeight=400`）或**无尺寸原图**（Logo
/// `?tag=`），直接放大显示会糊（详情页/轮播 hero 区达 600+ 逻辑高），直接
/// 下载原图会慢（Logo 常为数 MB 透明 PNG）。Emby 图片端点按 `tag` 服务端
/// 缩放，重写 query 的尺寸参数即可**同时**解决「糊」与「慢」：
/// 传输量降 10 倍+，解码宽与显示一致（不拉大图再缩）。
library;

/// 设备感知目标宽（物理像素，已含 dpr）：
/// `逻辑宽 × min(dpr, 2)`，钳位 [min]~[max]。
///
/// - dpr 封顶 2：高 dpr（手机 3×）屏 2× 已足够清晰，3× 纯耗流量；
/// - 默认钳 600~1280：hero 大图；小件（Logo 等）调用方传自己的区间。
int embyImageTargetWidth(
  double logicalWidth,
  double devicePixelRatio, {
  int min = 600,
  int max = 1280,
}) {
  final dpr = devicePixelRatio < 2 ? devicePixelRatio : 2;
  final pixels = logicalWidth * dpr;
  return pixels.clamp(min.toDouble(), max.toDouble()).round();
}

/// 按目标宽 [targetWidth] 重写 Emby 图片 URL 的尺寸参数（698 N4/N4-5）：
///
/// - `maxHeight=400` 小图档（Poster/Backdrop）→ `maxWidth=$w` +
///   `quality=85`（未带 quality 时）；
/// - **无尺寸参数的原图**（Logo `?tag=…`）→ 追加 `maxWidth=$w&quality=90`；
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
