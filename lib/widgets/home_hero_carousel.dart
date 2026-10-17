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
    final bg = item.backdropWideUrl ?? item.posterUrl;
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
          EmbyImage(
            url: bg,
            fit: BoxFit.cover,
            placeholder: const SizedBox.shrink(),
            errorWidget: const SizedBox.shrink(),
          ),
          // 底部压暗：保证标题/信息可读，并与下方内容底色衔接
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.55, 0.80, 1.0],
                colors: [
                  Colors.transparent,
                  Color(0x33000000),
                  Color(0x99000000),
                  Color(0xE6000000),
                ],
              ),
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
    const style = TextStyle(color: Colors.white70, fontSize: 13);
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
            ),
          ),
      ],
    );
  }
}
