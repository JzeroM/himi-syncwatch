import 'dart:math' as math;
import 'dart:ui' as ui;

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
            // 698 N64：整体立体投影（双层——接触阴影 + 环境投影）。
            Positioned.fill(
              top: 4,
              left: 4,
              right: 2,
              bottom: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 34,
                      spreadRadius: 3,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
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
    // 698 N63：磨砂玻璃封面（恒定中性）——三层立体：
    // BackdropFilter 玻璃 + 左上柔光 + 右下内阴影 + 双描边（玻璃厚度感）。
    return Container(
      key: const ValueKey('agoraBookCoverSurface'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 磨砂玻璃底（透出背景光场）。
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: ColoredBox(
                color: Colors.white.withValues(alpha: 0.10),
                child: const SizedBox.expand(),
              ),
            ),
            // 左上柔光高光（受光面）。
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.7, -0.8),
                  radius: 1.1,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            // 右下内阴影弧（鼓面感）。
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.7, 0.9),
                  radius: 1.2,
                  colors: [
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            // 内描边（玻璃厚度第二线）。
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06), width: 3),
              ),
            ),
            Positioned.fill(
              child: child,
            ),
            // 698 N68：装订（参考图 1:1）——双丝环穿孔单 painter 严格对位。
            Positioned(
              top: -6,
              left: 26,
              right: 26,
              child: const BindingRings(),
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
                'AGORA · SETUP NOTE',
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
                        '上滑翻开',
                        style: TextStyle(
                          color: palette.foil,
                          fontSize: 11,
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
    // 698 N64：简洁线性「连接」图标（声网语义，白描线——替代徽章）。
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Icon(
        Icons.draw, // 698 N65：钢笔线条（笔记本+羽毛笔主题）
        size: 34,
        color: Colors.white.withValues(alpha: 0.88),
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

/// 698 N68：装订（参考图 1:1）——**双股细丝圆拱穿圆孔**，单 painter
/// 严格对位（环心=孔心）：丝从孔穿出绕拱穿回相邻孔（螺旋连续）、
/// 受光/背光分段、孔口接触阴影+口缘高光+孔内丝截面。
class BindingRings extends StatelessWidget {
  const BindingRings({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: CustomPaint(
        size: const Size(double.infinity, 26),
        painter: _BindingPainter(),
      ),
    );
  }
}

class _BindingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const count = 6;
    final step = size.width / count;
    const holeR = 3.2; // 孔半径
    const archY = 11.0; // 孔心 y
    // ① 孔（深色圆孔 + 口缘高光 + 接触阴影）。
    for (var i = 0; i < count; i++) {
      final cx = step * (i + 0.5);
      final c = Offset(cx, archY);
      canvas.drawCircle(
          c,
          holeR,
          Paint()
            ..color = const Color(0xFF8A8A90)
            ..style = PaintingStyle.fill);
      // 口缘高光（左上环口）。
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: holeR),
          -2.2,
          1.6,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0x66FFFFFF));
    }
    // ② 双股丝拱（每股 2px，间距 2.5px；受光/背光分段）。
    for (var i = 0; i < count; i++) {
      final cx = step * (i + 0.5);
      for (var wire = 0; wire < 2; wire++) {
        final r = 8.5 + wire * 2.8;
        final cy = archY;
        // 受光段（左上）。
        canvas.drawArc(
            Rect.fromCircle(center: Offset(cx, cy), radius: r),
            -2.6,
            1.9,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFFF4F4F6));
        // 背光段（右下）。
        canvas.drawArc(
            Rect.fromCircle(center: Offset(cx, cy), radius: r),
            -0.7,
            1.9,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round
              ..color = const Color(0xFF8E8E96));
      }
      // 孔内丝截面（脚端小亮点——丝穿进孔）。
      canvas.drawCircle(
          Offset(cx - 2.2, archY + 1),
          1.1,
          Paint()..color = const Color(0xFFE8E8EC));
      canvas.drawCircle(
          Offset(cx + 2.2, archY + 1),
          1.1,
          Paint()..color = const Color(0xFFB0B0B8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

