import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_cover.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_page.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';

export 'agora_book_page.dart' show AgoraGuideStep, agoraGuideSteps;

Matrix4 agoraPageTurnTransform(double progress) {
  final p = progress.clamp(0.0, 1.0);
  final eased = Curves.easeInOutCubic.transform(p);
  final angle = eased * math.pi * 0.49;
  final lift = math.sin(math.pi * p);
  return Matrix4.identity()
    ..setEntry(3, 2, 0.00055)
    ..rotateY(angle)
    ..rotateZ(-0.012 * lift);
}

typedef AgoraBookExtraPageBuilder = Widget Function(
  BuildContext context,
  AgoraBookPalette palette,
  int index,
  int total,
);

class AgoraGuideBook extends StatefulWidget {
  const AgoraGuideBook({
    super.key,
    this.steps = agoraGuideSteps,
    this.extraPageBuilder,
    this.onImageTap,
    this.themeColor,
  });

  final List<AgoraGuideStep> steps;
  final AgoraBookExtraPageBuilder? extraPageBuilder;
  final ValueChanged<String>? onImageTap;
  final Color? themeColor;

  @override
  State<AgoraGuideBook> createState() => _AgoraGuideBookState();
}

class _AgoraGuideBookState extends State<AgoraGuideBook>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  int _index = -1;
  int? _target;
  bool _forward = true;
  double _bookWidth = 320;
  double _dragDx = 0;
  int? _dragTarget;

  bool get _busy => _target != null;

  int get _pageCount =>
      widget.steps.length + (widget.extraPageBuilder == null ? 0 : 1);

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  void _openCover() {
    if (_busy || _pageCount == 0) return;
    _animateTo(0);
  }

  void _goToStep(int step) {
    if (_busy || step < -1 || step >= _pageCount) return;
    _animateTo(step);
  }

  void _animateTo(int target) {
    if (target == _index) return;
    final forward = target > _index;
    setState(() {
      _target = target;
      _forward = forward;
    });
    _flip.value = forward ? 0 : 1;
    _settle(complete: true);
  }

  Future<void> _settle({required bool complete}) async {
    final target = _target;
    if (target == null) return;
    final end = _forward ? (complete ? 1.0 : 0.0) : (complete ? 0.0 : 1.0);
    final distance = (end - _flip.value).abs();
    await _flip.animateTo(
      end,
      duration: Duration(
        milliseconds: (440 * distance).round().clamp(130, 440),
      ),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      if (complete) _index = target;
      _target = null;
      _flip.value = 0;
    });
  }

  void _handleDragStart(DragStartDetails details) {
    if (_busy) return;
    _dragDx = 0;
    _dragTarget = null;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_busy && _dragTarget == null) return;
    _dragDx += details.delta.dx;

    if (_dragTarget == null) {
      if (_dragDx < -10 && _index < _pageCount - 1) {
        _dragTarget = _index + 1;
        _forward = true;
      } else if (_dragDx > 10 && _index > -1) {
        _dragTarget = _index - 1;
        _forward = false;
      } else {
        return;
      }
      setState(() {
        _target = _dragTarget;
        _flip.value = _forward ? 0 : 1;
      });
    }

    final width = math.max(_bookWidth, 1);
    if (_forward) {
      _flip.value = (-_dragDx / width).clamp(0.0, 1.0);
    } else {
      _flip.value = 1 - (_dragDx / width).clamp(0.0, 1.0);
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final target = _dragTarget;
    if (target == null) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final complete = _forward
        ? (_flip.value > 0.28 || velocity < -460)
        : (_flip.value < 0.72 || velocity > 460);
    _dragTarget = null;
    _settle(complete: complete);
  }

  void _handleDragCancel() {
    if (_dragTarget == null) return;
    _dragTarget = null;
    _settle(complete: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_pageCount == 0) return const SizedBox.shrink();
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
        end: widget.themeColor ?? AgoraBookPalette.defaultAccent,
      ),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, accent, _) {
        final palette = AgoraBookPalette.fromAccent(accent);
        return Column(
          key: const ValueKey('agoraGuideBook'),
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 0.72,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _bookWidth = constraints.maxWidth;
                  return GestureDetector(
                    key: const ValueKey('agoraBookViewport'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _handleDragStart,
                    onHorizontalDragUpdate: _handleDragUpdate,
                    onHorizontalDragEnd: _handleDragEnd,
                    onHorizontalDragCancel: _handleDragCancel,
                    child: IgnorePointer(
                      ignoring: _busy,
                      child: _buildBook(palette),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            _BookControls(
              cover: _index == -1,
              page: _index,
              total: _pageCount,
              busy: _busy,
              onPrevious: () => _goToStep(_index - 1),
              onNext: () => _goToStep(_index + 1),
              onSelect: _goToStep,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBook(AgoraBookPalette palette) {
    final target = _target;
    if (target == null) {
      if (_index == -1) {
        return AgoraBookCover(
          palette: palette,
          onOpen: _openCover,
        );
      }
      return AgoraBookShell(
        palette: palette,
        child: _page(context, _index, palette),
      );
    }

    final coverTransition = _index == -1 || target == -1;
    if (coverTransition) {
      final stepIndex = _index == -1 ? target : _index;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (stepIndex >= 0)
            Positioned.fill(
              child: AgoraBookShell(
                palette: palette,
                child: _page(context, stepIndex, palette),
              ),
            ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _flip,
              builder: (context, _) {
                return _TurnedSurface(
                  progress: _flip.value,
                  palette: palette,
                  curved: false,
                  edgeColor: palette.foil,
                  front: AgoraBookCover(
                    palette: palette,
                    onOpen: () {},
                  ),
                  back: AgoraBookCoverBack(palette: palette),
                );
              },
            ),
          ),
        ],
      );
    }

    final from = math.min(_index, target);
    final to = math.max(_index, target);
    return AgoraBookShell(
      palette: palette,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _page(context, to, palette),
          AnimatedBuilder(
            animation: _flip,
            builder: (context, _) {
              return _TurnedSurface(
                progress: _flip.value,
                palette: palette,
                curved: true,
                edgeColor: palette.paperLight,
                front: _page(context, from, palette),
                back: _PaperBack(palette: palette),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _page(BuildContext context, int index, AgoraBookPalette palette) {
    final total = _pageCount;
    if (index >= widget.steps.length) {
      return widget.extraPageBuilder!(context, palette, index, total);
    }
    return AgoraBookGuidePage(
      index: index,
      total: total,
      step: widget.steps[index],
      palette: palette,
      onImageTap: widget.onImageTap,
    );
  }
}

class _TurnedSurface extends StatelessWidget {
  const _TurnedSurface({
    required this.progress,
    required this.palette,
    required this.curved,
    required this.edgeColor,
    required this.front,
    required this.back,
  });

  final double progress;
  final AgoraBookPalette palette;
  final bool curved;
  final Color edgeColor;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final backOpacity = _smoothstep(0.58, 0.92, p);
    final fade = 1 - _smoothstep(0.94, 1, p);
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        front,
        if (backOpacity > 0)
          Opacity(
            opacity: backOpacity,
            child: back,
          ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: math.sin(math.pi * p) * 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      edgeColor.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    if (curved) {
      content = ClipPath(
        clipper: _PageTurnClipper(p),
        child: content,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FlipShadowPainter(palette, p),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: fade,
            child: Transform(
              alignment: Alignment.centerLeft,
              transform: agoraPageTurnTransform(p),
              child: content,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaperBack extends StatelessWidget {
  const _PaperBack({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.pageBack, palette.paperDark],
        ),
      ),
      child: CustomPaint(
        painter: _PaperBackPainter(palette),
      ),
    );
  }
}

class _PaperBackPainter extends CustomPainter {
  const _PaperBackPainter(this.palette);

  final AgoraBookPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..strokeWidth = 0.5
      ..color = palette.paperEdge.withValues(alpha: 0.24);
    for (var y = 13.0; y < size.height; y += 9) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final random = math.Random(0xBAC4);
    for (var i = 0; i < 9; i++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width,
            random.nextDouble() * size.height),
        0.8 + random.nextDouble() * 2.4,
        Paint()..color = palette.mutedInk.withValues(alpha: 0.035),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperBackPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _FlipShadowPainter extends CustomPainter {
  const _FlipShadowPainter(this.palette, this.progress);

  final AgoraBookPalette palette;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    final strength = math.sin(math.pi * p);
    if (strength <= 0.001) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            palette.ink.withValues(alpha: 0.18 * strength),
            palette.ink.withValues(alpha: 0.055 * strength),
            Colors.transparent,
          ],
          stops: const [0, 0.38, 0.84],
        ).createShader(rect),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.82, 0, size.width * 0.18, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            palette.ink.withValues(alpha: 0.12 * strength),
          ],
        ).createShader(
          Rect.fromLTWH(size.width * 0.82, 0, size.width * 0.18, size.height),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _FlipShadowPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.palette != palette;
}

class _PageTurnClipper extends CustomClipper<Path> {
  const _PageTurnClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final bend = math.sin(math.pi * progress.clamp(0.0, 1.0));
    if (bend < 0.01) {
      return Path()..addRect(Offset.zero & size);
    }
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width - 1, 0)
      ..quadraticBezierTo(
        size.width + 2.2 * bend,
        size.height * 0.38,
        size.width - 1.2 * bend,
        size.height * 0.64,
      )
      ..quadraticBezierTo(
        size.width + 1.6 * bend,
        size.height * 0.84,
        size.width - 1,
        size.height,
      )
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant _PageTurnClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _BookControls extends StatelessWidget {
  const _BookControls({
    required this.cover,
    required this.page,
    required this.total,
    required this.busy,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final bool cover;
  final int page;
  final int total;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (cover) {
      return SizedBox(
        height: 38,
        child: Center(
          child: Text(
            '共 $total 步 · 左右滑动阅读',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('agoraBookPrev'),
            tooltip: '上一页',
            onPressed: !busy ? onPrevious : null,
            iconSize: 18,
            color: Colors.white70,
            disabledColor: Colors.white24,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < total; i++)
                  GestureDetector(
                    key: ValueKey('agoraBookDot_$i'),
                    onTap: busy ? null : () => onSelect(i),
                    child: Container(
                      width: i == page ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == page
                            ? const Color(0xFFD8B26B)
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text(
                    '左右滑动翻页',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white54, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('agoraBookNext'),
            tooltip: '下一页',
            onPressed: !busy && page < total - 1 ? onNext : null,
            iconSize: 18,
            color: Colors.white70,
            disabledColor: Colors.white24,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
