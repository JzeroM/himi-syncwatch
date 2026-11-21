import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/utils/motion.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';
import 'package:himi_syncwatch/utils/emby_image_url.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/ratings_badge_row.dart';

typedef HomeHeroImageBuilder = Widget Function(
  String url, {
  BoxFit fit,
  int? cacheWidth,
  bool transparent,
  Widget? errorWidget,
});

class HomeHeroItem {
  const HomeHeroItem({
    required this.title,
    this.imageUrl,
    this.logoUrl,
    this.year,
    this.rating,
    this.genres = const [],
    this.overview,
    this.ratingQuery,
    this.payload,
  });

  final String title;
  final String? imageUrl;
  final String? logoUrl;
  final String? year;
  final double? rating;
  final List<String> genres;

  /// 剧情简介（轮播底部 2 行截断展示；空则不渲染）。
  final String? overview;

  /// 多平台评分查询参数（null = 不渲染徽章行）。
  final HeroRatingQuery? ratingQuery;

  final Object? payload;

  factory HomeHeroItem.fromMediaItem(MediaItem item, {Object? payload}) {
    return HomeHeroItem(
      title: item.name,
      // 698 N1：轮播只获取电影封面（Primary 海报），不再用宽幅背景图。
      imageUrl: item.posterUrl,
      logoUrl: item.logoUrl,
      year: item.year,
      rating: item.communityRating,
      genres: item.genres.take(3).toList(),
      overview: item.overview,
      ratingQuery: HeroRatingQuery.fromMediaItem(item),
      payload: payload ?? item,
    );
  }
}

String? ambientBackdropUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return url;
  final query = Map<String, String>.from(uri.queryParameters);
  query.remove('maxHeight');
  query['maxWidth'] = '320';
  query['quality'] = '70';
  return uri.replace(queryParameters: query).toString();
}

Widget embyHeroImageBuilder(
  String url, {
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  bool transparent = false,
  Widget? errorWidget,
}) {
  return EmbyImage(
    url: url,
    fit: fit,
    cacheWidth: cacheWidth,
    placeholder: transparent ? const SizedBox.shrink() : null,
    errorWidget: errorWidget ?? (transparent ? const SizedBox.shrink() : null),
  );
}

/// 首页顶部随机海报轮播（非 TV）：每 [interval] 自动切页，末页回卷首页。
///
/// 页码由外层 [controller] 驱动；切页通过 [onPageChanged] 通知外层更新
/// 虚化背景与当前索引。用户手动拖动会重置自动计时。
class HomeHeroCarousel extends StatefulWidget {
  const HomeHeroCarousel({
    super.key,
    required this.items,
    required this.controller,
    required this.height,
    required this.onPageChanged,
    this.onTap,
    this.interval = const Duration(seconds: 5),
    this.onUserInteract,
    this.imageBuilder = embyHeroImageBuilder,
    this.ratingsService,
  });

  final List<HomeHeroItem> items;
  final PageController controller;
  final double height;
  final ValueChanged<int> onPageChanged;
  final void Function(HomeHeroItem item)? onTap;
  final HomeHeroImageBuilder imageBuilder;

  /// 多平台评分服务（null = 不渲染徽章行）。
  final HeroRatingsSource? ratingsService;

  /// 自动切换间隔（默认 5 秒）。
  final Duration interval;

  /// 用户开始拖动时回调（用于暂停外层动画等）。
  final VoidCallback? onUserInteract;

  /// 轮播/详情页海报高度单源（698）：屏高 × [heroHeightRatio]，钳位
  /// [heroHeightMin]~[heroHeightMax]（超大窗不糊成巨幅、小窗不塌成条）。
  /// 服务器首页 / TMDB 首页 / 详情页（非 TV）三处消费，改一处全局生效。
  static const double heroHeightRatio = 0.55;
  static const double heroHeightMin = 300;
  static const double heroHeightMax = 640;

  /// 高度计算（纯函数，便于测试）：[screenHeight] × 0.55，钳位 300~640。
  static double heroHeightFor(double screenHeight) =>
      (screenHeight * heroHeightRatio).clamp(heroHeightMin, heroHeightMax);

  /// 高度计算（取 MediaQuery 屏高）。
  static double heroHeightOf(BuildContext context) =>
      heroHeightFor(MediaQuery.sizeOf(context).height);

  /// 清晰图底部渐隐（v1.2.15）：底部渐隐到透明，露出下层同源虚化海报，
  /// 消除「清晰图 → 虚化图」的内容硬切（详情页 SliverAppBar 同款处理）。
  @visibleForTesting
  static const LinearGradient imageFadeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white, Colors.white, Colors.transparent],
    stops: [0.0, 0.62, 1.0],
  );

  /// 可读性压暗罩（v1.2.17）：文字区维持 0x99（60%）可读性，但**底边必须
  /// 归零**——本罩画在虚化背景（含背景蒙罩）之上，暗度是叠加关系：底边若
  /// 保留 0x66（40%），接缝上方总暗度 ≈ 64% 而下方仅 40% → 约 24% 的台阶
  /// 就是「分割线」的真正来源。底边归零后接缝两侧暗度均为背景蒙罩的
  /// ~40%，颜色连续。
  @visibleForTesting
  static const LinearGradient scrimGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0x33000000),
      Color(0x99000000),
      Color(0x99000000),
      Colors.transparent,
    ],
    stops: [0.0, 0.40, 0.68, 0.84, 1.0],
  );

  /// 轻微文字投影（v1.2.17）：压暗罩底边归零后，浅色海报上的白色文字/
  /// 圆点需要兜底对比度。
  @visibleForTesting
  static const List<Shadow> lightTextShadows = [
    Shadow(color: Color(0xAA000000), blurRadius: 4),
  ];

  @override
  State<HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<HomeHeroCarousel> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _index =
          _index.clamp(0, widget.items.isEmpty ? 0 : widget.items.length - 1);
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer(widget.interval, _advance);
  }

  void _advance() {
    if (!mounted || widget.items.length < 2) return;
    final next = (_index + 1) % widget.items.length;
    widget.controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
    );
    // 兜底：animateToPage 未触发 onPageChanged 时仍继续轮播
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return SizedBox(height: widget.height);
    return SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // 手动拖动：重置计时，避免拖动中/刚结束后被自动切走
              if (n is ScrollStartNotification || n is UserScrollNotification) {
                widget.onUserInteract?.call();
                _schedule();
              }
              return false;
            },
            child: PageView.builder(
              controller: widget.controller,
              itemCount: items.length,
              onPageChanged: (i) {
                _index = i;
                widget.onPageChanged(i);
                _schedule();
              },
              itemBuilder: (context, index) {
                // 687：滚动视差——背景图随页面切换以 0.5 倍速平移，
                // 制造纵深（前景文字保持原位）。系统减少动画时关闭。
                final slide = _HeroSlide(
                  item: items[index],
                  imageBuilder: widget.imageBuilder,
                  onTap: widget.onTap,
                  ratingsService: widget.ratingsService,
                );
                if (Motion.reduced(context)) return slide;
                return AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, child) {
                    double delta = 0;
                    if (widget.controller.hasClients &&
                        widget.controller.position.haveDimensions) {
                      final page = widget.controller.page ?? index.toDouble();
                      delta = (index - page).clamp(-1.0, 1.0);
                    }
                    return Transform.translate(
                      // 0.5 倍反向位移（相邻页最大偏移半个屏宽）
                      offset: Offset(delta * 60, 0),
                      child: child,
                    );
                  },
                  child: slide,
                );
              },
            ),
          ),
          if (items.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: _Dots(count: items.length, index: _index),
            ),
        ],
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({
    required this.item,
    required this.imageBuilder,
    this.onTap,
    this.ratingsService,
  });

  final HomeHeroItem item;
  final HomeHeroImageBuilder imageBuilder;
  final void Function(HomeHeroItem item)? onTap;
  final HeroRatingsSource? ratingsService;

  @override
  Widget build(BuildContext context) {
    final bg = item.imageUrl;
    final logo = item.logoUrl;
    final rating = item.rating;
    final year = item.year;
    final genres = item.genres;
    final overview = item.overview?.trim();
    final query = item.ratingQuery;

    // 698 N5-A：分槽位取图——hero 大图宁大勿糊（cap 1600/q90）、Logo 不抠
    // 质量（cap 800/q100）。海报目标宽按实际显示宽（LayoutBuilder 实测）。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Logo 显示高仅 ~54px，按 180 逻辑宽估目标宽（槽位钳 300~800）。
    final logoW = embyImageSlotWidth(EmbyImageSlot.logo, 180, dpr);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 虚化铺底（698 N5-B 构图 A）：同图 320 小图 cover + 高斯模糊——
          // 海报四周由同源虚化填满，无硬边无色相跳变；底部渐隐到透明
          // （v1.2.15）与首页虚化背景无缝溶解（接缝对齐层共用取图优先级）。
          if (bg != null)
            ShaderMask(
              shaderCallback: (rect) =>
                  HomeHeroCarousel.imageFadeGradient.createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ClipRect(
                // 模糊采样边缘会向内渗透明光晕：放大 15% 让渗出区落在
                // 裁剪之外。
                child: Transform.scale(
                  scale: 1.15,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: imageBuilder(
                      ambientBackdropUrl(bg) ?? bg,
                      fit: BoxFit.cover,
                      transparent: true,
                    ),
                  ),
                ),
              ),
            ),
          // 底部压暗：保证标题/信息可读；底边归零（v1.2.17），接缝暗度
          // 完全由背景蒙罩连续提供，避免叠加出暗带。
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: HomeHeroCarousel.scrimGradient,
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: 0,
            bottom: 30,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 海报完整居中（698 N5-B 构图 A）：AspectRatio 2:3 + contain
                // ——零裁切完整可见（修「显示不全」），圆角 + 投影轻量卡片
                // 感；高度吃剩余空间（Column 定序），信息块永不被挤出。
                if (bg != null)
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      // 海报实际显示宽上界：min(可用宽, 可用高×2/3)。
                      final posterW = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight * 2 / 3,
                      );
                      final targetW = embyImageSlotWidth(
                          EmbyImageSlot.hero, posterW, dpr);
                      return Center(
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 24,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: imageBuilder(
                                embyImageUrlForSlot(
                                        bg, EmbyImageSlot.hero, posterW, dpr) ??
                                    bg,
                                fit: BoxFit.contain,
                                cacheWidth: targetW,
                                transparent: true,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                if (logo != null && logo.isNotEmpty)
                  SizedBox(
                    height: 54,
                    child: imageBuilder(
                      // 698 N5-A：Logo 槽位不抠质量（cap 800/q100）；原图常为
                      // 数 MB 透明 PNG，按显示需要追加尺寸提示 + 同宽解码。
                      embyImageUrlForSlot(logo, EmbyImageSlot.logo, 180, dpr) ??
                          logo,
                      fit: BoxFit.contain,
                      cacheWidth: logoW,
                      errorWidget: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          shadows: HomeHeroCarousel.lightTextShadows,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      shadows: HomeHeroCarousel.lightTextShadows,
                    ),
                  ),
                if (rating != null || year != null || genres.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _MetaRow(rating: rating, year: year, genres: genres),
                ],
                if (overview != null && overview.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  // 简介：最多 2 行，省略号截断（698；对齐参考截图）。
                  Text(
                    overview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                      shadows: HomeHeroCarousel.lightTextShadows,
                    ),
                  ),
                ],
                if (query != null && ratingsService != null) ...[
                  const SizedBox(height: 8),
                  // 多平台评分徽章行（698）：品牌图标 + 分数，缺哪枚隐藏哪枚。
                  HeroRatingsLoader(
                    query: query,
                    service: ratingsService!,
                    iconSize: 15,
                    alignment: WrapAlignment.center,
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      shadows: HomeHeroCarousel.lightTextShadows,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({this.rating, this.year, this.genres = const []});

  final double? rating;
  final String? year;
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Colors.white70,
      fontSize: 13,
      shadows: HomeHeroCarousel.lightTextShadows,
    );
    final parts = <Widget>[];
    void sep() {
      if (parts.isNotEmpty) {
        parts.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('·', style: style),
        ));
      }
    }

    if (rating != null) {
      parts.add(const Icon(Icons.star, size: 15, color: Colors.amber));
      parts.add(const SizedBox(width: 3));
      parts.add(Text(rating!.toStringAsFixed(1), style: style));
    }
    if (year != null && year!.isNotEmpty) {
      sep();
      parts.add(Text(year!, style: style));
    }
    if (genres.isNotEmpty) {
      sep();
      parts.add(Text(genres.join(' '), style: style));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? Colors.white : Colors.white38,
              borderRadius: BorderRadius.circular(3),
              // 压暗罩底边归零后圆点落在较亮背景上，轻微投影兜底对比度。
              boxShadow: const [
                BoxShadow(color: Color(0x59000000), blurRadius: 3),
              ],
            ),
          ),
      ],
    );
  }
}

class HomeHeroBackground extends StatelessWidget {
  const HomeHeroBackground({
    super.key,
    required this.imageUrl,
    required this.baseColor,
    required this.heroHeight,
    this.imageBuilder = embyHeroImageBuilder,
  });

  final String? imageUrl;
  final Color baseColor;
  final double heroHeight;
  final HomeHeroImageBuilder imageBuilder;

  static const LinearGradient seamFadeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white,
      Colors.white,
      Colors.transparent,
      Colors.transparent,
    ],
    stops: [0.0, 0.5, 0.73, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final source = imageUrl;
    final url = ambientBackdropUrl(source);
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Stack(
        key: ValueKey(source),
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Transform.scale(
              scale: 1.35,
              child: KeyedSubtree(
                key: const Key('homeAmbientImage'),
                child: imageBuilder(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: 200,
                  transparent: true,
                ),
              ),
            ),
          ),
          Positioned(
            key: const Key('homeAmbientSeamLayer'),
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight * 2,
            child: ShaderMask(
              shaderCallback: (rect) => seamFadeGradient.createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: heroHeight,
                      child: imageBuilder(
                        url,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        transparent: true,
                      ),
                    ),
                    Positioned(
                      top: heroHeight,
                      left: 0,
                      right: 0,
                      height: heroHeight,
                      child: Transform.flip(
                        flipY: true,
                        child: KeyedSubtree(
                          key: const Key('homeAmbientSeamImage'),
                          child: imageBuilder(
                            url,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                            transparent: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  Colors.black.withValues(alpha: 0.42),
                  baseColor.withValues(alpha: 0.90),
                  baseColor,
                ],
                stops: const [0.0, 0.5, 0.85, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
