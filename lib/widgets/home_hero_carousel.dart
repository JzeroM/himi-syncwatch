import 'dart:async';

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

  /// 高度双档（698 N7-C，借 SenPlayer「显示区比例贴图」）：显示区比例贴图种
  /// 比例，cover 裁切天然最小——轮播贴竖版海报 2:3、详情贴横版背景图
  /// （SenPlayer 详情实测 ~1.17:1）。**视口护栏**：高度不超屏高 ×
  /// [viewportCapRatio]（宽扁窗不撑破视口，懒列表照常建、信息块可点），
  /// 再钳 [heroHeightMin]~[heroHeightMax]。
  static const double carouselHeightRatio = 1.35;
  static const double detailHeightRatio = 0.85;
  static const double viewportCapRatio = 0.65;
  static const double heroHeightMin = 300;
  static const double heroHeightMax = 640;

  static double _heroHeight(double byWidth, double screenHeight) {
    final cap = screenHeight * viewportCapRatio;
    return (byWidth < cap ? byWidth : cap).clamp(heroHeightMin, heroHeightMax);
  }

  /// 轮播高度（纯函数）：宽 × 1.35（贴 2:3 海报）+ 视口护栏。
  static double carouselHeightFor(double width, double screenHeight) =>
      _heroHeight(width * carouselHeightRatio, screenHeight);

  /// 详情 hero 高度（纯函数）：宽 × 0.85（≈1.17:1，贴横版背景图）+ 视口护栏。
  static double detailHeightFor(double width, double screenHeight) =>
      _heroHeight(width * detailHeightRatio, screenHeight);

  /// 轮播高度（取 MediaQuery）。
  static double carouselHeightOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return carouselHeightFor(size.width, size.height);
  }

  /// 详情 hero 高度（取 MediaQuery）。
  static double detailHeightOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return detailHeightFor(size.width, size.height);
  }

  /// 清晰图底部渐隐（v1.2.15；N7-B 收窄）：**窄带**渐隐到透明（0.88 起），
  /// 画面主体全量呈现——旧 0.62 起渐隐吃掉画面底部 38%（「显示不全」真凶），
  /// 渐隐区半透在虚化底层上还发糊。露出下层同源虚化海报，接缝自然溶解
  ///（详情页 SliverAppBar 同款思路）。
  @visibleForTesting
  static const LinearGradient imageFadeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white, Colors.white, Colors.transparent],
    stops: [0.0, 0.88, 1.0],
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

    // 698 N5-A/N7-D：分槽位取图——hero 大图宁大勿糊（q90、cap 3000、dpr
    // 封 3 用满物理像素）、Logo 不抠质量（cap 800/q100）。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // Logo 显示高仅 ~54px，按 180 逻辑宽估目标宽（槽位钳 300~800）。
    final logoW = embyImageSlotWidth(EmbyImageSlot.logo, 180, dpr);
    final heroW = embyImageSlotWidth(EmbyImageSlot.hero, width, dpr);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 满幅大图（N7-A 构图回归，SenPlayer 同款）：竖版海报 cover 居中
          // 裁切满幅铺开；底部窄带渐隐到透明（N7-B：0.88 起渐隐，画面主体
          // 全量呈现），露出下层同源虚化海报，接缝自然溶解无硬边
          // （v1.2.15；与 home_screen 的虚化背景共用同一取图优先级）。
          ShaderMask(
            shaderCallback: (rect) =>
                HomeHeroCarousel.imageFadeGradient.createShader(rect),
            blendMode: BlendMode.dstIn,
            child: bg == null
                ? const SizedBox.shrink()
                : imageBuilder(
                    embyImageUrlForSlot(bg, EmbyImageSlot.hero, width, dpr) ??
                        bg,
                    fit: BoxFit.cover,
                    cacheWidth: heroW,
                    transparent: true,
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
            bottom: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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

