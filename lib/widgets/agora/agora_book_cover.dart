import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';

class AgoraBookCover extends StatelessWidget {
  const AgoraBookCover({
    super.key,
    required this.palette,
    required this.onOpen,
  });

  final AgoraBookPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '翻开声网接入指南',
      child: GestureDetector(
        key: const ValueKey('agoraBookCover'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              top: 4,
              left: 4,
              right: 2,
              bottom: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.52),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              left: 16,
              top: 8,
              bottom: -4,
              right: -3,
              child: _ClosedPageBlock(palette: palette),
            ),
            Positioned.fill(
              right: 9,
              bottom: 7,
              child: _CoverBoard(
                palette: palette,
                child: _CoverContent(palette: palette),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AgoraBookShell extends StatelessWidget {
  const AgoraBookShell({
    super.key,
    required this.palette,
    required this.child,
  });

  final AgoraBookPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: 8,
          left: 4,
          right: 2,
          bottom: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.46),
                  blurRadius: 26,
                  spreadRadius: 1,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          top: 2,
          left: 1,
          right: 0,
          bottom: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              gradient: palette.coverGradient,
              border: Border.all(
                color: palette.leatherDark,
                width: 1.2,
              ),
            ),
          ),
        ),
        Positioned.fill(
          left: 23,
          top: 7,
          right: 5,
          bottom: 6,
          child: IgnorePointer(
            child: _OpenPageBlock(palette: palette),
          ),
        ),
        Positioned.fill(
          left: 28,
          top: 10,
          right: 10,
          bottom: 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: child,
          ),
        ),
        Positioned(
          left: 0,
          top: 5,
          bottom: 6,
          width: 24,
          child: IgnorePointer(child: _Spine(palette: palette)),
        ),
      ],
    );
  }
}

class _CoverBoard extends StatelessWidget {
  const _CoverBoard({
    required this.palette,
    required this.child,
  });

  final AgoraBookPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agoraBookCoverSurface'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: palette.coverGradient,
        border: Border.all(
          color: palette.leatherDark,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.42),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: palette.leatherWorn.withValues(alpha: 0.20),
            blurRadius: 1,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x16FFFFFF), Color(0x00000000)],
                ),
              ),
            ),
            CustomPaint(painter: _AgedCoverPainter(palette)),
            Positioned.fill(
              left: 25,
              child: child,
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 26,
              child: _Spine(palette: palette),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverContent extends StatelessWidget {
  const _CoverContent({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'HIMI · FIELD NOTES',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foilDim,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.3,
                ),
              ),
              const Spacer(),
              Center(
                child: _CoverEmblem(palette: palette),
              ),
              const SizedBox(height: 15),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '声网接入指南',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.paperLight,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.2,
                    shadows: const [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 2,
                        offset: Offset(0, 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              _FoilDivider(palette: palette),
              const SizedBox(height: 8),
              Text(
                '四步完成声网配置',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.foil,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.8,
                ),
              ),
              const Spacer(),
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: palette.foilDim.withValues(alpha: 0.75),
                    ),
                    color: Colors.black.withValues(alpha: 0.10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 13,
                        color: palette.foil,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '轻触封面翻开',
                        style: TextStyle(
                          color: palette.foil,
                          fontSize: 10.5,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
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

class _CoverEmblem extends StatelessWidget {
  const _CoverEmblem({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            palette.leatherLight.withValues(alpha: 0.65),
            palette.leatherDark.withValues(alpha: 0.55),
          ],
        ),
        border: Border.all(color: palette.foilDim, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.foil.withValues(alpha: 0.50),
                width: 0.8,
              ),
            ),
          ),
          Icon(
            Icons.auto_stories_outlined,
            size: 30,
            color: palette.foil,
          ),
        ],
      ),
    );
  }
}

class _FoilDivider extends StatelessWidget {
  const _FoilDivider({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 1,
          color: palette.foilDim.withValues(alpha: 0.70),
        ),
        const SizedBox(width: 7),
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 5,
            height: 5,
            color: palette.foil.withValues(alpha: 0.80),
          ),
        ),
        const SizedBox(width: 7),
        Container(
          width: 38,
          height: 1,
          color: palette.foilDim.withValues(alpha: 0.70),
        ),
      ],
    );
  }
}

class _Spine extends StatelessWidget {
  const _Spine({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(17),
        ),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            palette.leatherDark,
            palette.leatherLight,
            palette.leatherDark,
          ],
          stops: const [0, 0.42, 1],
        ),
        border: Border(
          right: BorderSide(
            color: palette.leatherDark.withValues(alpha: 0.9),
          ),
        ),
      ),
      child: Stack(
        children: [
          for (final top in const [0.16, 0.48, 0.80])
            Positioned.fill(
              left: 2,
              right: 2,
              child: Align(
                alignment: Alignment(0, top * 2 - 1),
                child: Container(
                  height: 3,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: palette.leatherDark.withValues(alpha: 0.72),
                    border: Border(
                      top: BorderSide(
                        color: palette.leatherWorn.withValues(alpha: 0.28),
                        width: 0.7,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            height: 4,
            child: _HeadBand(palette: palette),
          ),
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            height: 4,
            child: _HeadBand(palette: palette),
          ),
          Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                'HIMI',
                style: TextStyle(
                  color: palette.foilDim,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadBand extends StatelessWidget {
  const _HeadBand({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.paperEdge,
            palette.foilDim,
            palette.paperEdge,
          ],
        ),
      ),
    );
  }
}

class _ClosedPageBlock extends StatelessWidget {
  const _ClosedPageBlock({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agoraBookClosedPageBlock'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.paperLight, palette.paperEdge],
        ),
        border: Border.all(
          color: palette.paperDark,
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: ClipRRect(
        key: const ValueKey('agoraBookClosedPageClip'),
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _PageBlockPainter(palette, closed: true),
        ),
      ),
    );
  }
}

class _OpenPageBlock extends StatelessWidget {
  const _OpenPageBlock({required this.palette});

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agoraBookOpenPageBlock'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.paperLight, palette.paperEdge],
        ),
      ),
      child: ClipRRect(
        key: const ValueKey('agoraBookOpenPageClip'),
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(
          painter: _PageBlockPainter(palette, closed: false),
        ),
      ),
    );
  }
}

class _PageBlockPainter extends CustomPainter {
  const _PageBlockPainter(this.palette, {required this.closed});

  final AgoraBookPalette palette;
  final bool closed;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..strokeWidth = 0.7
      ..color = palette.paperEdge.withValues(alpha: 0.55);
    for (var y = 5.0; y < size.height; y += 4.2) {
      canvas.drawLine(
        Offset(closed ? 1 : 0, y),
        Offset(size.width - 1, y),
        line,
      );
    }
    final edge = Paint()
      ..strokeWidth = 0.8
      ..color = palette.paperDark.withValues(alpha: 0.75);
    canvas.drawLine(
      Offset(size.width - 1.2, 3),
      Offset(size.width - 1.2, size.height - 3),
      edge,
    );
    canvas.drawLine(
      Offset(3, size.height - 1.2),
      Offset(size.width - 3, size.height - 1.2),
      edge,
    );
  }

  @override
  bool shouldRepaint(covariant _PageBlockPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.closed != closed;
}

class _AgedCoverPainter extends CustomPainter {
  const _AgedCoverPainter(this.palette);

  final AgoraBookPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final wear = _PaletteWear(size, palette);
    wear.paintMottles(canvas, count: 26);
    wear.paintGrain(canvas, count: 96);
    wear.paintCornerScuffs(canvas);

    final borderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
      const Radius.circular(12),
    );
    canvas.drawRRect(
      borderRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.foilDim.withValues(alpha: 0.78),
            palette.foil.withValues(alpha: 0.42),
            palette.foilDim.withValues(alpha: 0.72),
          ],
        ).createShader(borderRect.outerRect),
    );
    canvas.drawRRect(
      borderRect.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..color = palette.foilDim.withValues(alpha: 0.34),
    );

    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = palette.foil.withValues(alpha: 0.50);
    const corner = 18.0;
    final corners = <Offset>[
      Offset(14, 14),
      Offset(size.width - 14, 14),
      Offset(14, size.height - 14),
      Offset(size.width - 14, size.height - 14),
    ];
    for (var i = 0; i < corners.length; i++) {
      final c = corners[i];
      final sx = i.isEven ? 1.0 : -1.0;
      final sy = i < 2 ? 1.0 : -1.0;
      canvas.drawLine(c, c + Offset(corner * sx, 0), cornerPaint);
      canvas.drawLine(c, c + Offset(0, corner * sy), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AgedCoverPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _PaletteWear {
  _PaletteWear(this.size, this.palette);

  final Size size;
  final AgoraBookPalette palette;

  void paintMottles(Canvas canvas, {required int count}) {
    final random = math.Random(0x51A7 + count);
    for (var i = 0; i < count; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final radius = 10 + random.nextDouble() * 46;
      final dark = random.nextBool();
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(dx, dy),
          width: radius * (1.1 + random.nextDouble()),
          height: radius * (0.5 + random.nextDouble()),
        ),
        Paint()
          ..color = (dark ? palette.leatherDark : palette.leatherWorn)
              .withValues(alpha: 0.018 + random.nextDouble() * 0.035),
      );
    }
  }

  void paintGrain(Canvas canvas, {required int count}) {
    final random = math.Random(0xA6E3);
    final paint = Paint()..strokeWidth = 0.55;
    for (var i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final length = 0.7 + random.nextDouble() * 2.8;
      paint.color =
          (random.nextBool() ? palette.leatherWorn : palette.leatherDark)
              .withValues(alpha: 0.03 + random.nextDouble() * 0.05);
      canvas.drawLine(
        Offset(x, y),
        Offset(x + length, y + (random.nextDouble() - 0.5)),
        paint,
      );
    }
  }

  void paintCornerScuffs(Canvas canvas) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = palette.leatherWorn.withValues(alpha: 0.22);
    const points = <Offset>[
      Offset(6, 12),
      Offset(12, 6),
      Offset(6, 20),
      Offset(20, 6),
      Offset(-6, 12),
      Offset(-12, 6),
      Offset(-6, 20),
      Offset(-20, 6),
      Offset(6, -12),
      Offset(12, -6),
      Offset(6, -20),
      Offset(20, -6),
      Offset(-6, -12),
      Offset(-12, -6),
      Offset(-6, -20),
      Offset(-20, -6),
    ];
    final anchors = <Offset>[
      Offset(0, 0),
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      for (var j = 0; j < 4; j++) {
        final p = points[i * 4 + j];
        canvas.drawLine(
          anchor + p,
          anchor + p + Offset(i.isEven ? 4 : -4, i < 2 ? 3 : -3),
          paint,
        );
      }
    }
  }
}

class AgoraBookCoverBack extends StatelessWidget {
  const AgoraBookCoverBack({
    super.key,
    required this.palette,
  });

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agoraBookCoverBack'),
      decoration: BoxDecoration(
        gradient: palette.coverGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.leatherDark, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 16, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paperDark,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: palette.paperEdge.withValues(alpha: 0.8),
            ),
          ),
          child: CustomPaint(
            painter: _CoverBackLiningPainter(palette),
          ),
        ),
      ),
    );
  }
}

class _CoverBackLiningPainter extends CustomPainter {
  const _CoverBackLiningPainter(this.palette);

  final AgoraBookPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..strokeWidth = 0.5
      ..color = palette.paperEdge.withValues(alpha: 0.32);
    for (var y = 14.0; y < size.height; y += 10) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final random = math.Random(0xC0FFEE);
    for (var i = 0; i < 8; i++) {
      canvas.drawCircle(
        Offset(random.nextDouble() * size.width,
            random.nextDouble() * size.height),
        1 + random.nextDouble() * 3,
        Paint()..color = palette.mutedInk.withValues(alpha: 0.035),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CoverBackLiningPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
