import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

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
      duration: const Duration(milliseconds: 360),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final discSize = math
            .min(width - 16, widget.tvMode ? 560.0 : 420.0)
            .clamp(240.0, 560.0);
        final height = discSize * 0.96;
        _slotDistance = discSize * 0.31;

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
                alignment: Alignment.center,
                children: [
                  Center(
                    child: _DiscBase(
                      discSize: discSize,
                      glassEnabled: widget.glassEnabled,
                      rotation: -_position * 0.11,
                    ),
                  ),
                  ...panels,
                  const Positioned.fill(
                    child: IgnorePointer(child: _EdgeFade()),
                  ),
                  if (_focused)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FocusRingPainter(
                            color: theme.colorScheme.primary,
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
    final opacity = absT <= 1
        ? (1 - absT * 0.45).clamp(0.0, 1.0)
        : (0.55 * (1 - (absT - 1) / 0.5)).clamp(0.0, 0.55);
    final scale = (1 - 0.14 * math.min(absT, 1.4)).clamp(0.80, 1.0);
    final panelWidth = discSize * 0.50;
    final active = absT < 0.5;

    return Transform.translate(
      offset: Offset(t * _slotDistance, absT * 5),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(-t * 0.38)
          ..rotateZ(t * 0.018)
          ..scaleByDouble(scale, scale, 1, 1),
        child: Opacity(
          opacity: opacity,
          child: RepaintBoundary(
            child: _DiscSectionPanel(
              key: ValueKey('tmdbDiscPanel_${section.key}'),
              section: section,
              imageBase: widget.imageBase,
              width: panelWidth,
              height: panelWidth * 0.95,
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
    );
  }
}

class _DiscSectionPanel extends StatelessWidget {
  const _DiscSectionPanel({
    super.key,
    required this.section,
    required this.imageBase,
    required this.width,
    required this.height,
    required this.active,
    required this.accent,
    required this.onTap,
    required this.onOpen,
  });

  final TmdbDiscSectionData section;
  final String imageBase;
  final double width;
  final double height;
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
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [
                    accent.withValues(alpha: 0.30),
                    const Color(0x331A1D23),
                    const Color(0xBB0E1116),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.12),
                    const Color(0x221A1D23),
                    const Color(0xCC0E1116),
                  ],
          ),
          border: Border.all(
            color: active
                ? accent.withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.13),
            width: active ? 1.6 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: active ? 15 : 13.5,
                        fontWeight: FontWeight.w700,
                        color:
                            Colors.white.withValues(alpha: active ? 1 : 0.86),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 17,
                    color: Colors.white.withValues(alpha: active ? 0.9 : 0.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
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
            const SizedBox(height: 3),
            Text(
              loading ? '加载中' : (empty ? '暂无匹配' : '查看全部 ›'),
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: active ? 0.72 : 0.42),
              ),
            ),
          ],
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
    final count = items.length.clamp(1, 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final posterWidth = panelWidth * 0.46;
        final posterHeight = posterWidth * 1.5;
        final spread = panelWidth * 0.23;
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
                top: i == 1 ? 0 : 4,
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
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.32 : 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.42 : 0.25),
                blurRadius: active ? 10 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TmdbAvailabilityImage(
              entry: entry,
              imageBase: imageBase,
              posterSize: 'w154',
              cacheWidth: cacheWidth,
              serverMaxWidth: cacheWidth,
              fadeInDuration: const Duration(milliseconds: 120),
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
        final posterWidth = panelWidth * 0.46;
        final posterHeight = posterWidth * 1.5;
        final spread = panelWidth * 0.23;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: (panelWidth - posterWidth) / 2 + (i - 1) * spread,
                top: i == 1 ? 0 : 4,
                child: Transform.rotate(
                  angle: (i - 1) * 0.07,
                  child: Container(
                    width: posterWidth,
                    height: posterHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color:
                          Colors.white.withValues(alpha: active ? 0.10 : 0.06),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
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
            size: 26,
            color: accent.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 6),
          Text(
            '暂无匹配',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.56),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscBase extends StatelessWidget {
  const _DiscBase({
    required this.discSize,
    required this.glassEnabled,
    required this.rotation,
  });

  final double discSize;
  final bool glassEnabled;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final surface = ClipOval(
      child: SizedBox(
        width: discSize,
        height: discSize,
        child: CustomPaint(
          painter: _DiscSurfacePainter(
            rotation: rotation,
            glassEnabled: glassEnabled,
          ),
        ),
      ),
    );

    Widget disc;
    if (glassEnabled) {
      disc = lg.GlassContainer(
        width: discSize,
        height: discSize,
        shape: const lg.LiquidOval(),
        quality: lg.GlassQuality.standard,
        useOwnLayer: true,
        child: surface,
      );
    } else {
      disc = Container(
        width: discSize,
        height: discSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0x335A6476), Color(0xCC11151B), Color(0xF20A0C10)],
            stops: [0, 0.68, 1],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.24),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: surface,
      );
    }

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(0.38),
      child: disc,
    );
  }
}

class _DiscSurfacePainter extends CustomPainter {
  const _DiscSurfacePainter({
    required this.rotation,
    required this.glassEnabled,
  });

  final double rotation;
  final bool glassEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: glassEnabled ? 0.045 : 0.07);
    for (var i = 1; i <= 10; i++) {
      final r = radius * (0.34 + i * 0.055);
      if (r < radius - 6) canvas.drawCircle(center, r, groove);
    }

    canvas.drawCircle(
      center,
      radius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.045),
    );
    canvas.drawCircle(
      center,
      radius * 0.22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    final highlightRect = Rect.fromCircle(
      center: Offset.zero,
      radius: radius * 0.84,
    );
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.10
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: glassEnabled ? 0.10 : 0.15),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(highlightRect);
    canvas.drawArc(
      highlightRect,
      -math.pi * 0.95,
      math.pi * 0.55,
      false,
      highlight,
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      radius - 1.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.24),
    );
  }

  @override
  bool shouldRepaint(covariant _DiscSurfacePainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.glassEnabled != glassEnabled;
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      key: ValueKey('tmdbDiscEdgeFade'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xEB000000),
            Color(0x7A000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x7A000000),
            Color(0xEB000000),
          ],
          stops: [0, 0.15, 0.34, 0.66, 0.85, 1],
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({required this.color, required this.discSize});

  final Color color;
  final double discSize;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: math.min(size.width - 4, discSize * 0.98),
      height: discSize * 0.90,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = color.withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = color.withValues(alpha: 0.92),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final discSize = math.min(width - 16, 420.0).clamp(240.0, 420.0);
        return SizedBox(
          height: discSize * 0.96,
          child: Center(
            child: Container(
              width: discSize * 0.88,
              height: discSize * 0.44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                '正在加载精选…',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
