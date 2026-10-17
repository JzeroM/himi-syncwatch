import 'dart:async';

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

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
  });

  final List<MediaItem> items;
  final PageController controller;
  final double height;
  final ValueChanged<int> onPageChanged;
  final void Function(MediaItem item)? onTap;

  /// 自动切换间隔（默认 5 秒）。
  final Duration interval;

  /// 用户开始拖动时回调（用于暂停外层动画等）。
  final VoidCallback? onUserInteract;

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
      _index = _index.clamp(0, widget.items.isEmpty ? 0 : widget.items.length - 1);
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
              if (n is ScrollStartNotification ||
                  n is UserScrollNotification) {
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
              itemBuilder: (context, index) =>
                  _HeroSlide(item: items[index], onTap: widget.onTap),
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
  const _HeroSlide({required this.item, this.onTap});

  final MediaItem item;
  final void Function(MediaItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = item.backdropWideUrl ?? item.backdropUrl ?? item.posterUrl;
    final logo = item.logoUrl;
    final rating = item.communityRating;
    final year = item.year;
    final genres = item.genres.take(3).toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 底部渐隐到透明：露出下层同源虚化海报，接缝处自然溶解无硬边
          // （v1.2.15；与 home_screen 的虚化背景共用同一取图优先级）。
          ShaderMask(
            shaderCallback: (rect) =>
                HomeHeroCarousel.imageFadeGradient.createShader(rect),
            blendMode: BlendMode.dstIn,
            child: EmbyImage(
              url: bg,
              fit: BoxFit.cover,
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
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
                  EmbyImage(
                    url: logo,
                    height: 54,
                    fit: BoxFit.contain,
                    placeholder: const SizedBox.shrink(),
                    errorWidget: Text(
                      item.name,
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
                  )
                else
                  Text(
                    item.name,
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
