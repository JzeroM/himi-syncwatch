import 'dart:ui';

class TmdbDiscStickerShape {
  const TmdbDiscStickerShape._({
    required this.progress,
    required this.direction,
  });

  factory TmdbDiscStickerShape.fromOffset(double offset) {
    final distance = offset.abs().clamp(0.0, 1.0);
    final eased = distance * distance * (3 - 2 * distance);
    return TmdbDiscStickerShape._(
      progress: eased,
      direction: offset == 0 ? 0 : offset.sign,
    );
  }

  final double progress;
  final double direction;

  double get topWidthFactor => _lerp(0.60, 0.47, progress);
  double get bottomWidthFactor => _lerp(1.00, 0.94, progress);
  double get contentScaleX => 1 - 0.03 * progress;
  double get contentSkewX => direction * 0.03 * progress;

  Path buildClipPath(Size size) {
    final w = size.width;
    final h = size.height;
    final p = progress;
    final topHalf = w * topWidthFactor / 2;
    final bottomHalf = w * bottomWidthFactor / 2;
    final topSag = _lerp(h * 0.05, h * 0.11, p);
    final bottomSag = _lerp(h * 0.04, h * 0.07, p);
    final sideBend = _lerp(w * 0.02, w * 0.05, p);
    final innerBias = w * 0.018 * p;
    final mirror = direction > 0;
    final cx = w / 2;

    final topLeft = cx - topHalf;
    final topRight = cx + topHalf - innerBias * 0.6;
    final bottomLeft = cx - bottomHalf;
    final bottomRight = cx + bottomHalf - innerBias;

    double x(double value) => mirror ? w - value : value;

    return Path()
      ..moveTo(x(topLeft), 0)
      ..quadraticBezierTo(
        x((topLeft + topRight) / 2),
        topSag * 2,
        x(topRight),
        0,
      )
      ..quadraticBezierTo(
        x(bottomRight + sideBend),
        h * 0.46,
        x(bottomRight),
        h - bottomSag,
      )
      ..quadraticBezierTo(
        x((bottomLeft + bottomRight) / 2),
        h + bottomSag,
        x(bottomLeft),
        h - bottomSag,
      )
      ..quadraticBezierTo(
        x(bottomLeft - sideBend),
        h * 0.46,
        x(topLeft),
        0,
      )
      ..close();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
