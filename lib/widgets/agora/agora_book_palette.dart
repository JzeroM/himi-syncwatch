import 'package:flutter/material.dart';

@immutable
class AgoraBookPalette {
  const AgoraBookPalette({
    required this.leatherLight,
    required this.leather,
    required this.leatherDark,
    required this.leatherWorn,
    required this.foil,
    required this.foilBright,
    required this.foilDim,
    required this.paperLight,
    required this.paper,
    required this.paperDark,
    required this.paperEdge,
    required this.pageBack,
    required this.ink,
    required this.mutedInk,
    required this.ribbon,
  });

  factory AgoraBookPalette.fromAccent(Color? accent) {
    final base = HSLColor.fromColor(accent ?? defaultAccent);
    final leather = HSLColor.fromAHSL(
      1,
      base.hue,
      base.saturation.clamp(0.22, 0.46),
      base.lightness.clamp(0.17, 0.27),
    ).toColor();
    return AgoraBookPalette(
      leatherLight: _shift(leather, lightness: 0.07, saturation: -0.02),
      leather: leather,
      leatherDark: _shift(leather, lightness: -0.075, saturation: 0.02),
      leatherWorn: _shift(leather, lightness: 0.17, saturation: -0.18),
      foil: const Color(0xFFC2A064),
      foilBright: const Color(0xFFE0C58C),
      foilDim: const Color(0xFF8D7447),
      paperLight: const Color(0xFFF0DFBF),
      paper: const Color(0xFFE4CFA9),
      paperDark: const Color(0xFFCDB183),
      paperEdge: const Color(0xFFB69566),
      pageBack: const Color(0xFFD9C098),
      ink: const Color(0xFF3B2A1C),
      mutedInk: const Color(0xFF6E5741),
      ribbon: const Color(0xFF8E3F37),
    );
  }

  static const Color defaultAccent = Color(0xFF6366F1);

  final Color leatherLight;
  final Color leather;
  final Color leatherDark;
  final Color leatherWorn;
  final Color foil;
  final Color foilBright;
  final Color foilDim;
  final Color paperLight;
  final Color paper;
  final Color paperDark;
  final Color paperEdge;
  final Color pageBack;
  final Color ink;
  final Color mutedInk;
  final Color ribbon;

  LinearGradient get coverGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [leatherLight, leather, leatherDark],
        stops: const [0, 0.42, 1],
      );

  LinearGradient get paperGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [paperLight, paper, paperDark],
        stops: const [0, 0.58, 1],
      );

  static Color _shift(
    Color color, {
    required double lightness,
    required double saturation,
  }) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + lightness).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + saturation).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool operator ==(Object other) {
    return other is AgoraBookPalette &&
        other.leather == leather &&
        other.paper == paper &&
        other.foil == foil;
  }

  @override
  int get hashCode => Object.hash(leather, paper, foil);
}
