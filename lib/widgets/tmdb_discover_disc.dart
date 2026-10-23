import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_disc_shape.dart';

/// TMDB 首页顶部的光盘栏目。
///
/// 数据由 [tmdbDiscProvider] 懒加载；组件使用虚拟上拱半圆的三段弧线，
/// 画面上仅保留三张会随位置形变的贴纸及其局部柔光，其余区域完全透明。
class TmdbDiscoverDisc extends ConsumerWidget {
  const TmdbDiscoverDisc({super.key, required this.tvMode});

  final bool tvMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tmdbDiscProvider);
    final data = async.valueOrNull;
    if (async.hasError && data == null) return const SizedBox.shrink();
    if (data == null) return const _DiscSkeleton();
    if (!data.configured) return const SizedBox.shrink();

    final sections = data.sections
        .where((section) => section.loading || section.items.isNotEmpty)
        .toList(growable: false);
    if (sections.isEmpty) return const SizedBox.shrink();

    return TmdbDiscCarousel(
      key: const ValueKey('tmdbDiscoverDisc'),
      sections: sections,
      imageBase: ref.watch(tmdbImageBaseProvider),
      tvMode: tvMode,
      glassEnabled: ref.watch(settingsProvider.select((s) => s.glassUi)),
      onOpenSection: (section) => context.push('/tmdb/section/${section.key}'),
    );
  }
}

/// 上拱半圆三槽位贴纸轮播。
///
/// 分区数量动态；`_position` 是连续的分区位置，0 表示第 0 个分区居中。
/// 始终只构建中间分区和左右相邻分区，避免未来分区增多后渲染量线性增长。
class TmdbDiscCarousel extends StatefulWidget {
  const TmdbDiscCarousel({
    super.key,
    required this.sections,
    required this.imageBase,
    required this.onOpenSection,
    this.tvMode = false,
    this.glassEnabled = true,
    this.focusNode,
  });

  final List<TmdbDiscSectionData> sections;
  final String imageBase;
  final ValueChanged<TmdbDiscSectionData> onOpenSection;
  final bool tvMode;
  final bool glassEnabled;

  /// 测试或外部焦点管理使用；为空时组件自己创建。
  final FocusNode? focusNode;

  @override
  State<TmdbDiscCarousel> createState() => _TmdbDiscCarouselState();
}

class _TmdbDiscCarouselState extends State<TmdbDiscCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final FocusNode _internalFocusNode =
      FocusNode(debugLabel: 'TmdbDiscCarousel');
  late final bool _ownsFocusNode;
  double _position = 0;
  double _animStart = 0;
  double _animTarget = 0;
  bool _focused = false;
  double _slotDistance = 100;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(_tick);
  }

  void _tick() {
    final t = Curves.easeOutCubic.transform(_controller.value);
    setState(() {
      _position = _animStart + (_animTarget - _animStart) * t;
    });
  }

  @override
  void didUpdateWidget(covariant TmdbDiscCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sections.length == oldWidget.sections.length) return;
    _controller.stop();
    if (widget.sections.isEmpty || oldWidget.sections.isEmpty) {
      _position = 0;
      return;
    }
    final oldIndex = _mod(_position.round(), oldWidget.sections.length);
    final oldKey = oldWidget.sections[oldIndex].key;
    final newIndex = widget.sections.indexWhere((s) => s.key == oldKey);
    _position = newIndex >= 0
        ? newIndex.toDouble()
        : (_position.round() % widget.sections.length).toDouble();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsFocusNode) _internalFocusNode.dispose();
    super.dispose();
  }

  int _mod(int value, int length) => ((value % length) + length) % length;

  int get _activeIndex {
    if (widget.sections.isEmpty) return 0;
    return _mod(_position.round(), widget.sections.length);
  }

  void _animateTo(double target) {
    if (widget.sections.isEmpty) return;
    _animStart = _position;
    _animTarget = target;
    _controller.forward(from: 0);
  }

  void _rotate(int delta) {
    _animateTo(_position.roundToDouble() + delta);
  }

  void _selectSection(TmdbDiscSectionData section) {
    final index = widget.sections.indexWhere((s) => s.key == section.key);
    if (index < 0) return;
    final length = widget.sections.length;
    final base = _position.round();
    final baseSection = _mod(base, length);
    var delta = index - baseSection;
    if (delta > length / 2) delta -= length;
    if (delta < -length / 2) delta += length;
    _animateTo((base + delta).toDouble());
  }

  void _openActive() {
    if (widget.sections.isEmpty) return;
    widget.onOpenSection(widget.sections[_activeIndex]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.tvMode || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _rotate(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _rotate(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      _openActive();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.sections.isEmpty) return;
    setState(() {
      _position -= details.delta.dx / math.max(_slotDistance, 1);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.sections.isEmpty) return;
    final velocity = details.primaryVelocity ?? 0;
    final projected =
        _position - (velocity / math.max(_slotDistance, 1)) * 0.14;
    _animateTo(projected.roundToDouble());
  }

  List<int> _panelIndices(int center, int length) {
    if (length == 1) return [center];
    if (length == 2) return [center, center + 1];
    return [center - 1, center, center + 1];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final discSize = math
            .min(width - 12, widget.tvMode ? 560.0 : 420.0)
            .clamp(250.0, 560.0);
        final height = discSize * _DiscMetrics.heightFactor;
        _slotDistance = discSize * _DiscMetrics.dragFactor;

        final center = _position.round();
        final indices = _panelIndices(center, widget.sections.length)
          ..sort((a, b) => (b - center).abs().compareTo((a - center).abs()));
        final panels = <Widget>[
          for (final index in indices)
            _buildPanel(
              context,
              widget.sections[_mod(index, widget.sections.length)],
              index - _position,
              discSize,
              width / 2,
              theme,
            ),
        ];
        final activeSlot = _position.round();
        final activeT = activeSlot - _position;
        final activeAngle = activeT * _DiscMetrics.angleStep;
        final orbitRadius = discSize * _DiscMetrics.orbitFactor;
        final cardWidth = discSize * _DiscMetrics.cardWidthFactor;
        final cardHeight = discSize * _DiscMetrics.cardHeightFactor;
        final activeCenterX = width / 2 + math.sin(activeAngle) * orbitRadius;
        final activeCenterY = discSize * _DiscMetrics.topInsetFactor +
            cardHeight / 2 +
            (1 - math.cos(activeAngle)) * orbitRadius;
        final titleOpacity = (1 - 2 * activeT.abs()).clamp(0.0, 1.0);
        final activeSection =
            widget.sections[_mod(activeSlot, widget.sections.length)];
        final titleWidth = cardWidth + 24;

        return SizedBox(
          height: height,
          width: double.infinity,
          child: Focus(
            focusNode: _focusNode,
            canRequestFocus: widget.tvMode,
            onFocusChange: (value) {
              if (mounted) setState(() => _focused = value);
            },
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ...panels,
                  if (_focused)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FocusRingPainter(
                            color: accent,
                            discSize: discSize,
                          ),
                        ),
                      ),
                    ),
                  if (titleOpacity > 0.01)
                    Positioned(
                      left: activeCenterX - titleWidth / 2,
                      top: activeCenterY - cardHeight / 2 + 6,
                      width: titleWidth,
                      height: 32,
                      child: Opacity(
                        opacity: titleOpacity,
                        child: _DiscSectionTitle(
                          key: const ValueKey('tmdbDiscActiveTitle'),
                          title: activeSection.title,
                          accent: accent,
                          onTap: () => widget.onOpenSection(activeSection),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPanel(
    BuildContext context,
    TmdbDiscSectionData section,
    double t,
    double discSize,
    double discCenterX,
    ThemeData theme,
  ) {
    final absT = t.abs();
    final angle = t * _DiscMetrics.angleStep;
    final active = absT < 0.5;
    final opacity = (1 - absT * 0.30).clamp(0.58, 1.0);
    final scale = active
        ? _DiscMetrics.activeScale
        : (1 - 0.06 * math.min(absT, 1.5)).clamp(0.90, 0.97);
    final lift = active ? discSize * _DiscMetrics.liftFactor : 0.0;
    final cardWidth = discSize * _DiscMetrics.cardWidthFactor;
    final cardHeight = discSize * _DiscMetrics.cardHeightFactor;
    final orbitRadius = discSize * _DiscMetrics.orbitFactor;
    final centerX = discCenterX + math.sin(angle) * orbitRadius;
    final centerY = discSize * _DiscMetrics.topInsetFactor +
        cardHeight / 2 +
        (1 - math.cos(angle)) * orbitRadius;
    final shape = TmdbDiscStickerShape.fromOffset(t);

    return Positioned(
      left: centerX - cardWidth / 2,
      top: centerY - cardHeight / 2,
      width: cardWidth,
      height: cardHeight,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, -lift),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, _DiscMetrics.perspective)
              ..rotateX(_DiscMetrics.panelTilt),
            child: Transform.scale(
              scale: scale,
              child: RepaintBoundary(
                child: _DiscSectionCard(
                  key: ValueKey('tmdbDiscPanel_${section.key}'),
                  section: section,
                  imageBase: widget.imageBase,
                  active: active,
                  accent: theme.colorScheme.primary,
                  glassEnabled: widget.glassEnabled,
                  shape: shape,
                  onTap: () {
                    if (active) {
                      widget.onOpenSection(section);
                    } else {
                      _selectSection(section);
                    }
                  },
                  onOpen: () => widget.onOpenSection(section),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscSectionCard extends StatelessWidget {
  const _DiscSectionCard({
    super.key,
    required this.section,
    required this.imageBase,
    required this.active,
    required this.accent,
    required this.glassEnabled,
    required this.shape,
    required this.onTap,
    required this.onOpen,
  });

  final TmdbDiscSectionData section;
  final String imageBase;
  final bool active;
  final Color accent;
  final bool glassEnabled;
  final TmdbDiscStickerShape shape;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final items = section.items.take(3).toList(growable: false);
    final loading = section.loading && items.isEmpty;
    final empty = !section.loading && items.isEmpty;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: ValueKey('tmdbDiscIsland_${section.key}'),
                painter: _DiscIslandPainter(
                  active: active,
                  accent: accent,
                  glassEnabled: glassEnabled,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: _DiscStickerSurface(
              shape: shape,
              child: loading
                  ? _PosterFanSkeleton(active: active)
                  : empty
                      ? _EmptyPanel(accent: accent)
                      : _PosterFan(
                          sectionKey: section.key,
                          items: items,
                          imageBase: imageBase,
                          active: active,
                          accent: accent,
                          onOpen: onOpen,
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscSectionTitle extends StatelessWidget {
  const _DiscSectionTitle({
    super.key,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      height: 1.05,
      foreground: Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF9FCFF),
            Color.lerp(Colors.white, accent, 0.62)!,
          ],
        ).createShader(const Rect.fromLTWH(0, 0, 600, 26)),
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.80),
          blurRadius: 9,
          offset: const Offset(0, 2),
        ),
        Shadow(
          color: accent.withValues(alpha: 0.55),
          blurRadius: 16,
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '$title，进入栏目',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: SizedBox(
            height: 24,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFan extends StatelessWidget {
  const _PosterFan({
    required this.sectionKey,
    required this.items,
    required this.imageBase,
    required this.active,
    required this.accent,
    required this.onOpen,
  });

  final String sectionKey;
  final List<TmdbAvailability> items;
  final String imageBase;
  final bool active;
  final Color accent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = math.min(items.length, 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final panelHeight = constraints.maxHeight;
        final posterWidth = panelWidth * 0.62;
        final posterHeight = posterWidth * 1.5;
        final spread = panelWidth * 0.16;
        final top = math.max(0.0, (panelHeight - posterHeight) / 2);
        final order =
            count == 3 ? const [0, 2, 1] : [for (var i = 0; i < count; i++) i];
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            for (final i in order)
              Positioned(
                left: (panelWidth - posterWidth) / 2 +
                    (i - (count - 1) / 2) * spread,
                top: top + (i == 1 ? 0 : 2),
                child: Transform.rotate(
                  angle: (i - (count - 1) / 2) * 0.07,
                  child: _DiscPosterTile(
                    key: ValueKey(
                      'tmdbDiscPoster_${sectionKey}_${items[i].tmdb.key}',
                    ),
                    entry: items[i],
                    imageBase: imageBase,
                    width: posterWidth,
                    height: posterHeight,
                    active: active,
                    accent: accent,
                    onTap: onOpen,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DiscPosterTile extends StatelessWidget {
  const _DiscPosterTile({
    super.key,
    required this.entry,
    required this.imageBase,
    required this.width,
    required this.height,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final TmdbAvailability entry;
  final String imageBase;
  final double width;
  final double height;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();
    return Semantics(
      button: true,
      label: '${entry.tmdb.title}，进入栏目',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TmdbAvailabilityImage(
                entry: entry,
                imageBase: imageBase,
                posterSize: 'w154',
                cacheWidth: cacheWidth,
                serverMaxWidth: cacheWidth,
                fadeInDuration: const Duration(milliseconds: 120),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.13),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                        stops: const [0, 0.38, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscStickerSurface extends StatelessWidget {
  const _DiscStickerSurface({
    required this.shape,
    required this.child,
  });

  final TmdbDiscStickerShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _DiscStickerClipper(shape),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => RadialGradient(
          center: const Alignment(0, -0.02),
          radius: 0.80,
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0.96),
            Colors.transparent,
          ],
          stops: const [0, 0.80, 1],
        ).createShader(bounds),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(0, 0, shape.contentScaleX)
            ..setEntry(0, 1, math.tan(shape.contentSkewX)),
          child: child,
        ),
      ),
    );
  }
}

class _DiscStickerClipper extends CustomClipper<Path> {
  const _DiscStickerClipper(this.shape);

  final TmdbDiscStickerShape shape;

  @override
  Path getClip(Size size) => shape.buildClipPath(size);

  @override
  bool shouldReclip(covariant _DiscStickerClipper oldClipper) =>
      oldClipper.shape.progress != shape.progress ||
      oldClipper.shape.direction != shape.direction;
}

class _PosterFanSkeleton extends StatelessWidget {
  const _PosterFanSkeleton({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final panelHeight = constraints.maxHeight;
        final posterWidth = panelWidth * 0.62;
        final posterHeight = posterWidth * 1.5;
        final spread = panelWidth * 0.16;
        final top = math.max(0.0, (panelHeight - posterHeight) / 2);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: (panelWidth - posterWidth) / 2 + (i - 1) * spread,
                top: top + (i == 1 ? 0 : 2),
                child: Transform.rotate(
                  angle: (i - 1) * 0.07,
                  child: Container(
                    width: posterWidth,
                    height: posterHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Colors.white.withValues(
                        alpha: active ? 0.09 : 0.05,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.movie_filter_outlined,
            size: 24,
            color: accent.withValues(alpha: 0.62),
          ),
          const SizedBox(height: 5),
          Text(
            '暂无匹配',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.52),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscIslandPainter extends CustomPainter {
  const _DiscIslandPainter({
    required this.active,
    required this.accent,
    required this.glassEnabled,
  });

  final bool active;
  final Color accent;
  final bool glassEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height * 0.56);
    final glowRect = Rect.fromCenter(
      center: center,
      width: size.width * 1.30,
      height: size.height * 1.08,
    );

    final glowColor = active ? accent : const Color(0xFF8FD8FF);
    canvas.drawOval(
      glowRect,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(
              alpha: active ? 0.16 : (glassEnabled ? 0.06 : 0.045),
            ),
            glowColor.withValues(alpha: active ? 0.045 : 0.012),
            Colors.transparent,
          ],
          stops: const [0, 0.58, 1],
        ).createShader(glowRect),
    );

    final contact = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.9),
      width: size.width * 0.94,
      height: size.height * 0.16,
    );
    canvas.drawOval(
      contact,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            glowColor.withValues(alpha: active ? 0.09 : 0.035),
            Colors.transparent,
          ],
        ).createShader(contact),
    );
  }

  @override
  bool shouldRepaint(covariant _DiscIslandPainter oldDelegate) =>
      oldDelegate.active != active ||
      oldDelegate.accent != accent ||
      oldDelegate.glassEnabled != glassEnabled;
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.color, required this.discSize});

  final Color color;
  final double discSize;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      discSize *
          (_DiscMetrics.topInsetFactor + _DiscMetrics.cardHeightFactor / 2),
    );
    final rect = Rect.fromCenter(
      center: center,
      width: discSize * _DiscMetrics.cardWidthFactor + 14,
      height: discSize * _DiscMetrics.cardHeightFactor * 0.78 + 12,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.drawRRect(
      rrect.inflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = color.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = color.withValues(alpha: 0.72),
    );
    canvas.drawArc(
      rect,
      math.pi * 0.14,
      math.pi * 0.72,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..color = color.withValues(alpha: 0.94),
    );
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.discSize != discSize;
}

class _DiscSkeleton extends StatelessWidget {
  const _DiscSkeleton();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final discSize = math.min(width - 12, 420.0).clamp(250.0, 420.0);
        final height = discSize * _DiscMetrics.heightFactor;
        final cardWidth = discSize * _DiscMetrics.cardWidthFactor;
        final cardHeight = discSize * _DiscMetrics.cardHeightFactor;
        final orbitRadius = discSize * _DiscMetrics.orbitFactor;

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final slot in const [-1, 0, 1])
                _skeletonPanel(
                  slot: slot,
                  discSize: discSize,
                  discCenterX: width / 2,
                  cardWidth: cardWidth,
                  cardHeight: cardHeight,
                  orbitRadius: orbitRadius,
                  accent: accent,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeletonPanel({
    required int slot,
    required double discSize,
    required double discCenterX,
    required double cardWidth,
    required double cardHeight,
    required double orbitRadius,
    required Color accent,
  }) {
    final angle = slot * _DiscMetrics.angleStep;
    final active = slot == 0;
    final centerX = discCenterX + math.sin(angle) * orbitRadius;
    final centerY = discSize * _DiscMetrics.topInsetFactor +
        cardHeight / 2 +
        (1 - math.cos(angle)) * orbitRadius;
    final shape = TmdbDiscStickerShape.fromOffset(slot.toDouble());

    return Positioned(
      left: centerX - cardWidth / 2,
      top: centerY - cardHeight / 2,
      width: cardWidth,
      height: cardHeight,
      child: Opacity(
        opacity: active ? 1 : 0.62,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, _DiscMetrics.perspective)
            ..rotateX(_DiscMetrics.panelTilt),
          child: Transform.scale(
            scale: active ? _DiscMetrics.activeScale : _DiscMetrics.sideScale,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DiscIslandPainter(
                      active: active,
                      accent: accent,
                      glassEnabled: false,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _DiscStickerSurface(
                    shape: shape,
                    child: _PosterFanSkeleton(active: active),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscMetrics {
  static const panelTilt = 0.64;
  static const perspective = 0.0012;
  static const heightFactor = 0.57;
  static const topInsetFactor = 0.04;
  static const orbitFactor = 0.38;
  static const angleStep = 0.82;
  static const cardWidthFactor = 0.32;
  static const cardHeightFactor = 0.38;
  static const dragFactor = 0.24;
  static const liftFactor = 0.012;
  static const activeScale = 1.04;
  static const sideScale = 0.95;
}
