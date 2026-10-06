import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/glass/glass_config.dart';

/// 玻璃质感滑杆轨道（视觉模拟：半透明渐变 + 顶部高光 + 已播放段光晕，
/// 不用 BackdropFilter——拖动时逐帧模糊开销大，易掉帧）。
///
/// 颜色取自 [SliderThemeData.activeTrackColor]/[inactiveTrackColor]，
/// shape 只负责玻璃化处理（渐变、高光、外发光），保证音量/亮度柱换
/// accent 色（黄/紫）时无需改 shape。
class GlassSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const GlassSliderTrackShape();

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }
    final Color? activeColor = isEnabled
        ? sliderTheme.activeTrackColor
        : sliderTheme.disabledActiveTrackColor;
    final Color? inactiveColor = isEnabled
        ? sliderTheme.inactiveTrackColor
        : sliderTheme.disabledInactiveTrackColor;
    if (activeColor == null || inactiveColor == null) return;

    final Canvas canvas = context.canvas;
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final double h = sliderTheme.trackHeight!;
    final Radius radius = Radius.circular(h / 2);
    final bool isLTR = textDirection == TextDirection.ltr;

    // 已播放段：LTR = 左→thumb；RTL = thumb→右
    final double activeLeft =
        isLTR ? trackRect.left : math.max(thumbCenter.dx, trackRect.left);
    final double activeRight =
        isLTR ? math.min(thumbCenter.dx, trackRect.right) : trackRect.right;
    final Rect activeRect =
        Rect.fromLTRB(activeLeft, trackRect.top, activeRight, trackRect.bottom);

    // 1. 已播放段外发光（画在轨道底下，模拟玻璃折射溢光）
    if (activeRect.width > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect.inflate(1.5), radius),
        Paint()
          ..color = activeColor.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // 2. 未播放段整条作底：上亮下暗半透明渐变
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(inactiveColor, Colors.white, 0.22)!,
            inactiveColor,
            Color.lerp(inactiveColor, Colors.black, 0.18)!,
          ],
        ).createShader(trackRect),
    );

    // 3. 已播放段：accent 上亮下深 + 叠白，圆头跟随 thumb
    if (activeRect.width > 0.5) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(activeColor, Colors.white, 0.30)!,
              activeColor,
              Color.lerp(activeColor, Colors.black, 0.12)!,
            ],
          ).createShader(activeRect),
      );
    }

    // 4. 顶部高光线（整条轨道 clip 后画 1px，玻璃口沿高光）
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(trackRect, radius));
    final Rect highlightRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      trackRect.width,
      math.max(1, h * 0.18),
    );
    canvas.drawRect(
      highlightRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [GlassConfig.highlightTop, GlassConfig.highlightBottom],
        ).createShader(highlightRect)
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.restore();
  }
}

/// 玻璃 thumb：accent 圆点 + 主色光晕 + 顶部高光，按下时微放大
/// （activationAnimation 驱动）。
class GlassSliderThumbShape extends SliderComponentShape {
  const GlassSliderThumbShape({this.radius = 8});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Color enabledColor =
        sliderTheme.thumbColor ?? const Color(0xFF6366F1);
    final Color color = Color.lerp(
      sliderTheme.disabledThumbColor ?? enabledColor,
      enabledColor,
      enableAnimation.value,
    )!;
    final Canvas canvas = context.canvas;
    final double t = activationAnimation.value;
    final double r = radius * (1 + 0.10 * t);

    // 主色光晕
    canvas.drawCircle(
      center,
      r + 6,
      Paint()
        ..color = color.withValues(alpha: 0.30 + 0.20 * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8),
    );
    // 圆体（上亮下深玻璃渐变）
    final Rect bodyRect = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.38)!,
            color,
            Color.lerp(color, Colors.black, 0.16)!,
          ],
        ).createShader(bodyRect),
    );
    // 顶部高光弧
    final Path highlight = Path()
      ..addArc(
        Rect.fromCircle(center: center, radius: r - 1.6),
        math.pi * 1.08,
        math.pi * 0.84,
      );
    canvas.drawPath(
      highlight,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// 播放器滑杆统一玻璃主题（主进度条 / 音量亮度滑杆 / 音量亮度竖柱）。
///
/// - [trackHeight] 默认 6（原 3px 加粗一倍）；[thumbRadius] 默认 8
/// - [glassEnabled]=false（设置页关闭玻璃 UI）回退旧纯色观，避免
///   与全局降级风格冲突
SliderThemeData glassSliderTheme({
  Color accent = const Color(0xFF6366F1),
  double trackHeight = 6,
  double thumbRadius = 8,
  double overlayRadius = 14,
  bool glassEnabled = true,
}) {
  if (!glassEnabled) {
    return SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: Colors.white24,
      thumbColor: accent,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: thumbRadius),
      trackHeight: 3,
      overlayShape: RoundSliderOverlayShape(overlayRadius: overlayRadius),
      overlayColor: accent.withValues(alpha: 0.25),
    );
  }
  return SliderThemeData(
    activeTrackColor: accent,
    inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
    disabledActiveTrackColor: accent,
    disabledInactiveTrackColor: Colors.white24,
    trackHeight: trackHeight,
    trackShape: const GlassSliderTrackShape(),
    thumbColor: accent,
    disabledThumbColor: accent,
    thumbShape: GlassSliderThumbShape(radius: thumbRadius),
    overlayShape: RoundSliderOverlayShape(overlayRadius: overlayRadius),
    overlayColor: accent.withValues(alpha: 0.25),
  );
}
