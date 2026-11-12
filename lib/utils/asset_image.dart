import 'dart:async';

import 'package:flutter/material.dart';

/// 681：按**显示尺寸**解码资源图，避免原图分辨率同步解码阻塞首帧。
///
/// 【为什么需要】`Image.asset` 不带 `cacheWidth` 时按**原图分辨率**解码
/// （`instantiateImageCodec` 在 UI 线程同步执行）。实测：
/// - 声网页 4 张截图（175 KB）首次构建阻塞 20~80ms → 切标签明显掉帧
/// - TMDB 首页 7 张平台 logo（89 KB，`disney_plus` 单张 65 KB）在**启动
///   首屏**同步解码 → 拖慢首页渲染
///
/// 加上 `cacheWidth`（= 显示宽 × dpr）后解码量按显示尺寸收敛，通常小
/// 一个数量级。
///
/// 【为什么用 clamp(1, 2048)】下限防 0 宽（未布局时），上限防超大屏
/// （平板/TV 4K）解码出巨图反而更慢。
Image assetImage(
  BuildContext context,
  String path, {
  required double displayWidth,
  BoxFit fit = BoxFit.contain,
  FilterQuality quality = FilterQuality.medium,
  Key? key,
  String? semanticLabel,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.asset(
    path,
    key: key,
    fit: fit,
    filterQuality: quality,
    cacheWidth: cacheWidthFor(context, displayWidth),
    semanticLabel: semanticLabel,
    errorBuilder: errorBuilder,
  );
}

/// 681：计算 `cacheWidth`（显示宽 × dpr，clamp 1..2048）。
///
/// 【单一真相源】[assetImage] 与 [precacheAssetImage] 必须用**同一个**
/// 计算结果——`ResizeImage` 的缓存 key 含 width，两者不一致会解码两份
/// （预热白做，内存翻倍）。
int cacheWidthFor(BuildContext context, double displayWidth) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final raw = displayWidth * (dpr > 0 ? dpr : 1.0);
  if (raw.isNaN || raw.isInfinite) return 1;
  return raw.round().clamp(1, 2048);
}

/// 681：预热资源图（宽度与 [assetImage] 完全一致，保证命中同一缓存项）。
///
/// 【必须放 post-frame】预热会立即触发解码；在 `initState` 里同步调会
/// 和首帧抢 UI 线程，反而更卡。
Future<void> precacheAssetImage(
  BuildContext context,
  String path, {
  required double displayWidth,
}) async {
  final w = cacheWidthFor(context, displayWidth);
  try {
    await precacheImage(ResizeImage(AssetImage(path), width: w), context);
  } catch (_) {
    // 资源缺失/解码失败静默（与 Image.asset 的 errorBuilder 同语义）
  }
}

/// 681：批量预热（post-frame 后逐张预热，不阻塞首帧）。
///
/// [onSchedule] 仅供测试注入；生产传 null 走
/// `WidgetsBinding.instance.addPostFrameCallback`。
void precacheAssetImagesAfterFrame(
  BuildContext context,
  Iterable<String> paths, {
  required double displayWidth,
  void Function(VoidCallback)? onSchedule,
}) {
  void run() {
    for (final p in paths) {
      unawaited(precacheAssetImage(context, p, displayWidth: displayWidth));
    }
  }

  if (onSchedule != null) {
    onSchedule(run);
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) => run());
}
