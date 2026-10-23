import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';

/// TMDB 首页顶部的光盘栏目。
///
/// 数据由 [tmdbDiscProvider] 懒加载；组件本身只负责把动态分区列表
/// 投影成“左中右”三张可视卡，其他分区留在视野外暗区。
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

/// 三槽位弧形光盘轮播。
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
  static const _discTilt = 0.98;
  static const _perspective = -0.0018;
  static const _discHeightFactor = 0.78;
  static const _slotFactor = 0.26;
  static const _cardWidthFactor = 0.30;
  static const _cardHeightFactor = 0.37;

  late final AnimationController _controller;
  final FocusNode _internalFocusNode =
      FocusNode(debugLabel: 'TmdbDiscCarousel');
  late final bool _ownsFocusNode;
  double _position = 0;
  double _animStart = 0;
  double _animTarget = 0;
  bool _focused = false;
  double _slotDistance = 90;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
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
        final height = discSize * _discHeightFactor;
        _slotDistance = discSize * _slotFactor;

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
              theme,
            ),
        ];
        final plane = Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          ..rotateX(_discTilt);

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
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _DiscGroundPainter(discSize: discSize),
                      ),
                    ),
                  ),
                  Center(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      minWidth: discSize,
                      maxWidth: discSize,
                      minHeight: discSize,
                      maxHeight: discSize,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: plane,
                        child: SizedBox.square(
                          dimension: discSize,
                          child: ShaderMask(
                            key: const ValueKey('tmdbDiscEdgeFade'),
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x08000000),
                                Color(0x2A000000),
                                Color(0x85000000),
                                Color(0xF2000000),
                                Color(0xFF000000),
                              ],
                              stops: [0, 0.12, 0.34, 0.58, 1],
                            ).createShader(bounds),
                            child: ClipOval(
                              child: Stack(
                                fit: StackFit.expand,
                                clipBehavior: Clip.none,
                                children: [
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      key: const ValueKey('tmdbDiscSurface'),
                                      painter: _DiscSurfacePainter(
                                        rotation: -_position * 0.09,
                                        glassEnabled: widget.glassEnabled,
                                        accent: accent,
                                      ),
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      painter: _DiscZonePainter(
                                        discSize: discSize,
                                        accent: accent,
                                      ),
                                    ),
                                  ),
                                  ...panels,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
    ThemeData theme,
  ) {
    final absT = t.abs();
    final opacity = (1 - absT * 0.34).clamp(0.55, 1.0);
    final scale = (1 - 0.07 * math.min(absT, 1.5)).clamp(0.86, 1.0);
    final cardWidth = discSize * _cardWidthFactor;
    final cardHeight = discSize * _cardHeightFactor;
    final centerX = discSize / 2 + t * discSize * _slotFactor;
    final centerY = discSize * 0.75 - absT * discSize * 0.035;
    final active = absT < 0.5;

    return Positioned(
      left: centerX - cardWidth / 2,
      top: centerY - cardHeight / 2,
      width: cardWidth,
      height: cardHeight,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: t * 0.06,
          child: Transform.scale(
            scale: scale,
            child: RepaintBoundary(
              child: _DiscSectionCard(
                key: ValueKey('tmdbDiscPanel_${section.key}'),
                section: section,
                imageBase: widget.imageBase,
                active: active,
                accent: theme.colorScheme.primary,
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
    required this.onTap,
    required this.onOpen,
  });

  final TmdbDiscSectionData section;
  final String imageBase;
  final bool active;
  final Color accent;
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
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 30,
            child: _DiscSectionTitle(
              title: section.title,
              active: active,
              accent: accent,
              onOpen: onOpen,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 23,
            bottom: 0,
            child: loading
                ? _PosterFanSkeleton(active: active)
                : empty
                    ? _EmptyPanel(accent: accent)
                    : _PosterFan(
                        sectionKey: section.key,
                        items: items,
                        imageBase: imageBase,
                        active: active,
                        onOpen: onOpen,
                      ),
          ),
        ],
      ),
    );
  }
}

class _DiscSectionTitle extends StatelessWidget {
  const _DiscSectionTitle({
    required this.title,
    required this.active,
    required this.accent,
    required this.onOpen,
  });

  final String title;
  final bool active;
  final Color accent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: active ? 20 : 15,
      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
      letterSpacing: active ? 0.9 : 0.45,
      height: 1.05,
    );
    final style = active
        ? base.copyWith(
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
          )
        : base.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.70),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          );

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(-0.72),
      child: Semantics(
        button: true,
        label: '$title，进入栏目',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Center(
            child: SizedBox(
              width: active ? null : 68,
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
    required this.onOpen,
  });

  final String sectionKey;
  final List<TmdbAvailability> items;
  final String imageBase;
  final bool active;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = math.min(items.length, 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final panelHeight = constraints.maxHeight;
        final posterWidth = panelWidth * 0.52;
        final posterHeight = posterWidth * 1.5;
        final spread = panelWidth * 0.24;
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
    required this.onTap,
  });

  final TmdbAvailability entry;
  final String imageBase;
  final double width;
  final double height;
  final bool active;
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
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.22 : 0.12),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.42 : 0.30),
                blurRadius: 3,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
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
                            Colors.white.withValues(alpha: 0.12),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.24),
                          ],
                          stops: const [0, 0.36, 1],
                        ),
                      ),
                    ),
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

class _PosterFanSkeleton extends StatelessWidget {
  const _PosterFanSkeleton({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final panelHeight = constraints.maxHeight;
        final posterWidth = panelWidth * 0.52;
        final posterHeight = posterWidth * 1.5;
        final spread = panelWidth * 0.24;
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
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.white.withValues(
                        alpha: active ? 0.09 : 0.05,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                        width: 0.8,
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

class _DiscGroundPainter extends CustomPainter {
  const _DiscGroundPainter({required this.discSize});

  final double discSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);

    final shadow = Rect.fromCenter(
      center: center + Offset(0, discSize * 0.255),
      width: discSize * 0.82,
      height: discSize * 0.18,
    );
    canvas.drawOval(
      shadow,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, discSize * 0.045),
    );

    final body = Rect.fromCenter(
      center: center + Offset(0, discSize * 0.018),
      width: discSize * 0.96,
      height: discSize * 0.55,
    );
    canvas.drawOval(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2336), Color(0xFF070A10)],
        ).createShader(body),
    );
    canvas.drawArc(
      body.deflate(0.8),
      math.pi * 0.16,
      math.pi * 0.68,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _DiscGroundPainter oldDelegate) =>
      oldDelegate.discSize != discSize;
}

class _DiscSurfacePainter extends CustomPainter {
  const _DiscSurfacePainter({
    required this.rotation,
    required this.glassEnabled,
    required this.accent,
  });

  final double rotation;
  final bool glassEnabled;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final surface = Path()..addOval(rect);

    canvas.save();
    canvas.clipPath(surface);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, 0.16),
          radius: 0.94,
          colors: [
            Color(0xFF263149),
            Color(0xFF101725),
            Color(0xFF070A11),
            Color(0xFF030408),
          ],
          stops: [0, 0.42, 0.78, 1],
        ).createShader(rect),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation - 0.35);
    final sweepRect = Rect.fromCircle(center: Offset.zero, radius: radius);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = SweepGradient(
          startAngle: -0.4,
          endAngle: math.pi * 2 - 0.4,
          colors: [
            Colors.transparent,
            const Color(0x2822DDF5),
            const Color(0x143966FF),
            const Color(0x2A7B5CFF),
            const Color(0x1AF43F8E),
            const Color(0x2415E0C4),
            Colors.transparent,
          ],
          stops: const [0, 0.10, 0.27, 0.45, 0.62, 0.82, 1],
        ).createShader(sweepRect),
    );
    canvas.restore();

    final sheen = Rect.fromCenter(
      center: center + Offset(-radius * 0.08, -radius * 0.04),
      width: radius * 1.92,
      height: radius * 0.34,
    );
    canvas.drawOval(
      sheen,
      Paint()
        ..blendMode = BlendMode.screen
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.025)
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: glassEnabled ? 0.13 : 0.09),
            Colors.transparent,
          ],
        ).createShader(sheen),
    );

    final grooveCount = 42;
    for (var i = 0; i < grooveCount; i++) {
      final t = i / (grooveCount - 1);
      final grooveRadius = radius * (0.275 + 0.705 * t);
      canvas.drawCircle(
        center,
        grooveRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55 + t * 0.35
          ..color = Colors.white.withValues(
            alpha: 0.012 + t * 0.052,
          ),
      );
    }

    canvas.drawCircle(
      center,
      radius * 0.18,
      Paint()..color = Colors.black.withValues(alpha: 0.50),
    );
    canvas.drawCircle(
      center,
      radius * 0.18,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    canvas.drawCircle(
      center,
      radius * 0.145,
      Paint()..color = const Color(0xFF111827),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.145),
      math.pi * 0.10,
      math.pi * 0.80,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF7DDBFF).withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      center,
      radius * 0.072,
      Paint()..color = const Color(0xFF03050A),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.072),
      math.pi * 0.12,
      math.pi * 0.76,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.22),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment(0, 0.45),
          colors: [
            Colors.black.withValues(alpha: 0.58),
            Colors.black.withValues(alpha: 0.20),
            Colors.transparent,
          ],
          stops: const [0, 0.36, 1],
        ).createShader(rect),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          center: const Alignment(0, 0.82),
          radius: 0.72,
          colors: [
            accent.withValues(alpha: 0.13),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    final rimRect = Rect.fromCircle(center: center, radius: radius - 1.2);
    canvas.drawCircle(
      center,
      radius - 1.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    canvas.drawArc(
      rimRect,
      math.pi * 0.12,
      math.pi * 0.76,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2)
        ..color = Colors.white.withValues(alpha: 0.30),
    );
    canvas.drawArc(
      rimRect,
      -math.pi * 0.86,
      math.pi * 0.52,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiscSurfacePainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.glassEnabled != glassEnabled ||
      oldDelegate.accent != accent;
}

class _DiscZonePainter extends CustomPainter {
  const _DiscZonePainter({required this.discSize, required this.accent});

  final double discSize;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centerX = size.width / 2;
    final centerY = discSize * 0.75;
    final zoneWidth = discSize * 0.30;
    final zoneHeight = discSize * 0.26;

    for (final slot in const [-1, 0, 1]) {
      final center = Offset(
        centerX + slot * discSize * _TmdbDiscMetrics.slotFactor,
        centerY - slot.abs() * discSize * 0.035,
      );
      final rect = Rect.fromCenter(
        center: center,
        width: zoneWidth,
        height: zoneHeight,
      );
      canvas.drawOval(
        rect.inflate(discSize * 0.008),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.24)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, discSize * 0.012),
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: slot == 0
                ? [
                    accent.withValues(alpha: 0.16),
                    accent.withValues(alpha: 0.035),
                    Colors.transparent,
                  ]
                : [
                    Colors.white.withValues(alpha: 0.055),
                    Colors.white.withValues(alpha: 0.012),
                    Colors.transparent,
                  ],
            stops: const [0, 0.62, 1],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiscZonePainter oldDelegate) =>
      oldDelegate.discSize != discSize || oldDelegate.accent != accent;
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.color, required this.discSize});

  final Color color;
  final double discSize;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: math.min(size.width - 4, discSize * 0.98),
      height: discSize * 0.62,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      rect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.28),
    );
    canvas.drawArc(
      rect.deflate(1),
      math.pi * 0.10,
      math.pi * 0.80,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
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
        final height = discSize * _TmdbDiscMetrics.heightFactor;
        final plane = Matrix4.identity()
          ..setEntry(3, 2, _TmdbDiscMetrics.perspective)
          ..rotateX(_TmdbDiscMetrics.tilt);

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _DiscGroundPainter(discSize: discSize),
                ),
              ),
              Center(
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: discSize,
                  maxWidth: discSize,
                  minHeight: discSize,
                  maxHeight: discSize,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: plane,
                    child: SizedBox.square(
                      dimension: discSize,
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Opacity(
                              opacity: 0.42,
                              child: CustomPaint(
                                painter: _DiscSurfacePainter(
                                  rotation: 0,
                                  glassEnabled: false,
                                  accent: accent,
                                ),
                              ),
                            ),
                            for (final slot in const [-1, 0, 1])
                              Positioned(
                                left: discSize / 2 +
                                    slot *
                                        discSize *
                                        _TmdbDiscMetrics.slotFactor -
                                    discSize *
                                        _TmdbDiscMetrics.cardWidthFactor /
                                        2,
                                top: discSize * 0.75 -
                                    discSize *
                                        _TmdbDiscMetrics.cardHeightFactor /
                                        2 -
                                    slot.abs() * discSize * 0.035,
                                width:
                                    discSize * _TmdbDiscMetrics.cardWidthFactor,
                                height: discSize *
                                    _TmdbDiscMetrics.cardHeightFactor,
                                child: Opacity(
                                  opacity: slot == 0 ? 1 : 0.55,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: discSize * 0.16,
                                        height: 9,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          color: Colors.white.withValues(
                                            alpha: 0.10,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Expanded(
                                        child: _PosterFanSkeleton(active: true),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TmdbDiscMetrics {
  static const tilt = 0.98;
  static const perspective = -0.0018;
  static const heightFactor = 0.78;
  static const slotFactor = 0.26;
  static const cardWidthFactor = 0.30;
  static const cardHeightFactor = 0.37;
}
