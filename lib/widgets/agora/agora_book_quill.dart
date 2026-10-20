import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';

class AgoraBookQuill extends StatefulWidget {
  const AgoraBookQuill({
    super.key,
    required this.palette,
    required this.enabled,
    required this.onTap,
  });

  final AgoraBookPalette palette;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<AgoraBookQuill> createState() => _AgoraBookQuillState();
}

class _AgoraBookQuillState extends State<AgoraBookQuill> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '跳到配置页',
      child: Tooltip(
        message: widget.enabled ? '跳到配置页' : '已在配置页',
        child: GestureDetector(
          key: const ValueKey('agoraQuillButton'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
          onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
          onTapCancel: widget.enabled ? () => _setPressed(false) : null,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1 : 0.42,
            duration: const Duration(milliseconds: 180),
            child: AnimatedScale(
              scale: _pressed ? 0.965 : 1,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: Transform.rotate(
                angle: -0.032,
                child: CustomPaint(
                  painter: _QuillPainter(widget.palette),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuillPainter extends CustomPainter {
  const _QuillPainter(this.palette);

  final AgoraBookPalette palette;

  static const _shaftStart = Offset(50, 39);
  static const _shaftControl = Offset(124, 24);
  static const _shaftEnd = Offset(204, 29);
  static const _vaneEnd = 0.975;
  static const _maxHalfWidth = 25.0;
  static const _steelLight = Color(0xFFD8DEE4);
  static const _steel = Color(0xFF9CA7B2);
  static const _steelDark = Color(0xFF59636E);
  static const _vaneDeep = Color(0xFF5B4734);
  static const _vaneMid = Color(0xFF8F7256);
  static const _vaneLight = Color(0xFFC1A986);
  static const _vaneSheen = Color(0xFFEAD5B2);

  @override
  void paint(Canvas canvas, Size size) {
    const designWidth = 224.0;
    final scale = math.min(size.width / designWidth, size.height / 64);
    canvas.save();
    canvas.translate(
      (size.width - designWidth * scale) / 2,
      (size.height - 64 * scale) / 2,
    );
    canvas.scale(scale);
    _paintVane(canvas);
    _paintRachis(canvas);
    _paintNib(canvas);
    canvas.restore();
  }

  Offset _shaft(double t) {
    final mt = 1 - t;
    return _shaftStart * (mt * mt) +
        _shaftControl * (2 * mt * t) +
        _shaftEnd * (t * t);
  }

  Offset _tangent(double t) {
    final d = (_shaftControl - _shaftStart) * (2 * (1 - t)) +
        (_shaftEnd - _shaftControl) * (2 * t);
    final length = d.distance;
    return length == 0 ? const Offset(1, 0) : d / length;
  }

  Offset _normal(double t) {
    final tangent = _tangent(t);
    return Offset(-tangent.dy, tangent.dx);
  }

  double _vaneSpan(double t) {
    final progress = (t / _vaneEnd).clamp(0.0, 1.0);
    final base = math
        .pow(
          Curves.easeInOutCubic.transform(
            (progress / 0.40).clamp(0.0, 1.0),
          ),
          1.08,
        )
        .toDouble();
    final body =
        math.pow(math.sin(math.pi * math.pow(progress, 1.10)), 0.52).toDouble();
    final tip = 1 - 0.62 * math.pow(progress, 3.6).toDouble();
    return base * body * tip;
  }

  Offset _barbPoint(
    double t,
    int side, {
    required double lengthFactor,
    required double sweep,
  }) {
    final center = _shaft(t);
    final normal = _normal(t) * side.toDouble();
    final tangent = _tangent(t);
    final length = _maxHalfWidth * _vaneSpan(t) * lengthFactor;
    return center + normal * length + tangent * (length * sweep);
  }

  Path _silhouette({double lengthScale = 1, double sweep = 0.96}) {
    const samples = 72;
    final upper = <Offset>[];
    final lower = <Offset>[];
    for (var i = 0; i <= samples; i++) {
      final t = _vaneEnd * i / samples;
      final span = _vaneSpan(t);
      final center = _shaft(t);
      final normal = _normal(t);
      final tangent = _tangent(t);
      final length = _maxHalfWidth * span * lengthScale;
      upper.add(center + normal * length + tangent * (length * sweep));
      lower.add(center - normal * length + tangent * (length * sweep));
    }
    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (var i = 1; i < upper.length; i++) {
      path.lineTo(upper[i].dx, upper[i].dy);
    }
    for (var i = lower.length - 1; i >= 0; i--) {
      path.lineTo(lower[i].dx, lower[i].dy);
    }
    return path..close();
  }

  void _paintVane(Canvas canvas) {
    final silhouette = _silhouette(lengthScale: 0.97, sweep: 1.02);
    final bounds = Rect.fromLTWH(16, 4, 182, 56);
    canvas.drawPath(
      Path()
        ..moveTo(52, 44)
        ..quadraticBezierTo(126, 31, 208, 34),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );

    canvas.saveLayer(Rect.fromLTWH(8, 0, 204, 64), Paint());
    canvas.drawPath(
      silhouette,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _vaneMid.withValues(alpha: 0.34),
            _vaneDeep.withValues(alpha: 0.21),
            _vaneDeep.withValues(alpha: 0.12),
          ],
          stops: const [0, 0.52, 1],
        ).createShader(bounds),
    );

    final random = math.Random(0x51F7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var side = -1; side <= 1; side += 2) {
      for (var i = 0; i <= 178; i++) {
        final t = 0.012 + (_vaneEnd - 0.022) * i / 178;
        final span = _vaneSpan(t);
        if (span <= 0.008) continue;
        final center = _shaft(t);
        final normal = _normal(t) * side.toDouble();
        final tangent = _tangent(t);
        final length =
            _maxHalfWidth * span * (0.97 + random.nextDouble() * 0.08);
        final sweep = 1.00 + random.nextDouble() * 0.42;
        final end = center + normal * length + tangent * (length * sweep);
        final control = center +
            normal * (length * 0.53) +
            tangent * (length * sweep * 0.43);
        final warm = random.nextDouble();
        final color = warm > 0.90
            ? _vaneSheen
            : warm > 0.64
                ? _vaneLight
                : warm > 0.24
                    ? _vaneMid
                    : _vaneDeep;
        paint
          ..strokeWidth = 0.44 + random.nextDouble() * 0.32
          ..color = color.withValues(
            alpha: 0.30 + random.nextDouble() * 0.26,
          );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
          paint,
        );
      }
    }

    for (var side = -1; side <= 1; side += 2) {
      for (var i = 0; i <= 122; i++) {
        final t = 0.025 + (_vaneEnd - 0.09) * i / 122;
        final span = _vaneSpan(t);
        if (span <= 0.014) continue;
        final center = _shaft(t);
        final normal = _normal(t) * side.toDouble();
        final tangent = _tangent(t);
        final length =
            _maxHalfWidth * span * (0.30 + random.nextDouble() * 0.27);
        final end = center +
            normal * length +
            tangent * (length * (1.00 + random.nextDouble() * 0.32));
        paint
          ..strokeWidth = 0.42 + random.nextDouble() * 0.30
          ..color = (random.nextBool() ? _vaneSheen : _vaneLight).withValues(
            alpha: 0.20 + random.nextDouble() * 0.17,
          );
        canvas.drawLine(center, end, paint);
      }
    }

    _paintSplits(canvas);
    canvas.restore();
  }

  void _paintSplits(Canvas canvas) {
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final split in const [
      (0.34, 1, 1.2, 0.26),
      (0.54, -1, 0.9, 0.36),
      (0.70, 1, 0.7, 0.42),
    ]) {
      final t = split.$1;
      final side = split.$2;
      final width = split.$3;
      final innerFactor = split.$4;
      final outer = _barbPoint(
        t,
        side,
        lengthFactor: 1.04,
        sweep: 0.98,
      );
      final inner = _barbPoint(
        t + 0.018,
        side,
        lengthFactor: innerFactor,
        sweep: 0.62,
      );
      final control =
          Offset.lerp(inner, outer, 0.52)! + _normal(t) * (side * 0.8);
      clear.strokeWidth = width;
      canvas.drawPath(
        Path()
          ..moveTo(outer.dx, outer.dy)
          ..quadraticBezierTo(control.dx, control.dy, inner.dx, inner.dy),
        clear,
      );
    }
  }

  void _paintRachis(Canvas canvas) {
    const samples = 40;
    final upper = <Offset>[];
    final lower = <Offset>[];
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final width = 1.05 * (1 - t) + 0.26;
      final normal = _normal(t);
      upper.add(_shaft(t) + normal * width);
      lower.add(_shaft(t) - normal * width);
    }
    final path = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (var i = 1; i <= samples; i++) {
      path.lineTo(upper[i].dx, upper[i].dy);
    }
    for (var i = samples; i >= 0; i--) {
      path.lineTo(lower[i].dx, lower[i].dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.paperLight,
            palette.paperLight,
            palette.paper,
          ],
        ).createShader(const Rect.fromLTWH(48, 22, 160, 20)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45
        ..color = palette.ink.withValues(alpha: 0.48),
    );
    canvas.drawLine(
      _shaft(0.06) - const Offset(0, 0.45),
      _shaft(0.97) - const Offset(0, 0.45),
      Paint()
        ..color = palette.paperLight.withValues(alpha: 0.62)
        ..strokeWidth = 0.32,
    );

    final tip = _shaft(1);
    final forward = _tangent(1);
    final normal = _normal(1);
    final point = tip + forward * 3.4;
    final tipPath = Path()
      ..moveTo(tip.dx + normal.dx * 0.5, tip.dy + normal.dy * 0.5)
      ..quadraticBezierTo(
        point.dx + normal.dx * 0.18,
        point.dy + normal.dy * 0.18,
        point.dx,
        point.dy,
      )
      ..quadraticBezierTo(
        point.dx - normal.dx * 0.18,
        point.dy - normal.dy * 0.18,
        tip.dx - normal.dx * 0.5,
        tip.dy - normal.dy * 0.5,
      )
      ..close();
    canvas.drawPath(
      tipPath,
      Paint()..color = palette.paperLight,
    );
  }

  void _paintNib(Canvas canvas) {
    final root = _shaft(0.02);
    final tangent = _tangent(0.02);
    final angle = math.atan2(tangent.dy, tangent.dx);
    final path = Path()
      ..moveTo(-2.5, -2.5)
      ..cubicTo(1, -2.8, 4.5, -2.9, 7, -2.7)
      ..cubicTo(9, -4.3, 12, -5.05, 15.5, -4.8)
      ..cubicTo(24, -3.9, 34, -1.35, 43, 0.3)
      ..cubicTo(34, 1.5, 24, 3.7, 16, 4.7)
      ..cubicTo(12, 5.1, 9, 4.4, 7, 2.8)
      ..cubicTo(4.5, 2.9, 1, 2.8, -2.5, 2.55)
      ..close();

    canvas.save();
    canvas.translate(root.dx, root.dy);
    canvas.rotate(angle);
    canvas.scale(-1, 1);

    canvas.drawPath(
      path.shift(const Offset(0.9, 2.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );

    final socket = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-13.4, -3.25, 10.0, 6.5),
      const Radius.circular(1.4),
    );
    canvas.drawRRect(
      socket,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.foilBright,
            palette.foil,
            palette.foilDim,
            palette.foil,
          ],
          stops: const [0, 0.3, 0.78, 1],
        ).createShader(const Rect.fromLTWH(-13.4, -3.25, 10, 6.5)),
    );
    for (final x in const [-10.9, -8.0]) {
      canvas.drawLine(
        Offset(x, -2.7),
        Offset(x, 2.7),
        Paint()
          ..color = palette.ink.withValues(alpha: 0.38)
          ..strokeWidth = 0.55,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4.6, -3.55, 1.6, 7.1),
        const Radius.circular(0.7),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.foilBright,
            palette.foil,
            palette.foilDim,
          ],
        ).createShader(const Rect.fromLTWH(-4.6, -3.55, 1.6, 7.1)),
    );
    canvas.drawLine(
      const Offset(-0.8, -3.8),
      const Offset(-0.8, 3.8),
      Paint()
        ..color = palette.ink.withValues(alpha: 0.42)
        ..strokeWidth = 0.55,
    );

    final bounds = const Rect.fromLTWH(-3, -5.4, 48, 10.8);
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            _steelLight,
            _steelLight,
            _steel,
            _steel,
            _steelDark,
          ],
          stops: const [0, 0.22, 0.48, 0.78, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = const Color(0xFF2D3640).withValues(alpha: 0.74),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-1.5, -2.5)
        ..cubicTo(5, -2.6, 12, -4.4, 15.5, -4.4)
        ..cubicTo(24, -3.4, 34, -0.9, 41.5, 0.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.52
        ..color = Colors.white.withValues(alpha: 0.62),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-1, 2.4)
        ..cubicTo(5, 2.5, 11, 4.3, 16, 4.3)
        ..cubicTo(24, 3.2, 33, 1.1, 40.5, 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.42
        ..color = const Color(0xFF2D3640).withValues(alpha: 0.42),
    );
    canvas.drawPath(
      Path()
        ..moveTo(8, -2.0)
        ..quadraticBezierTo(11.5, -2.6, 15.5, -1.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.4
        ..color = const Color(0xFF2D3640).withValues(alpha: 0.52),
    );
    canvas.drawCircle(
      const Offset(21, -0.9),
      0.34,
      Paint()..color = Colors.white.withValues(alpha: 0.50),
    );
    canvas.drawLine(
      const Offset(0.8, 0.1),
      const Offset(14.6, 0.15),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.48
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      const Offset(15.6, 0.08),
      1.45,
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    canvas.drawCircle(
      const Offset(15.6, 0.08),
      1.45,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.4
        ..color = const Color(0xFF2D3640).withValues(alpha: 0.55),
    );
    canvas.drawLine(
      const Offset(15.6, 0.12),
      const Offset(43.0, 0.32),
      Paint()
        ..color = const Color(0xFF1B2229).withValues(alpha: 0.96)
        ..strokeWidth = 0.75,
    );
    canvas.drawLine(
      const Offset(17.0, 0.62),
      const Offset(38.5, 0.72),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.24)
        ..strokeWidth = 0.32,
    );
    canvas.drawLine(
      const Offset(42.8, 0.26),
      const Offset(44.2, 0.34),
      Paint()
        ..color = const Color(0xFF1E242B).withValues(alpha: 0.90)
        ..strokeWidth = 0.85
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _QuillPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
