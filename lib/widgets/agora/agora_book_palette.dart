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

  /// 698 N48：**书皮跟随背景色**（暗基调 + 背景色相派生 + 金点缀调和）：
  /// 皮革 = 背景色调调暗深皮革（L 0.14、S 钳 0.45）；烫字 = 暖金基
  /// 向背景色相调和 25%（金不孤立、与背景同氛围）；纸页同色相深纸；
  /// 内页文字米金；丝带酒红点睛。memo 同 tone 不重算（687 防重建）。
  static AgoraBookPalette fromTone(Color? tone) {
    if (tone == _memoTone && _memoPalette != null) return _memoPalette!;
    final src = HSLColor.fromColor(tone ?? defaultAccent);
    // 皮革：背景色相深皮革。
    final leather = HSLColor.fromAHSL(
      1,
      src.hue,
      src.saturation.clamp(0.15, 0.45),
      0.14,
    ).toColor();
    // 烫金调和：暖金基向背景色相 25%。
    Color goldMix(Color gold, double l, double sat) {
      final target = HSLColor.fromAHSL(1, src.hue, sat, l).toColor();
      return Color.lerp(gold, target, 0.25)!;
    }

    final palette = AgoraBookPalette(
      leatherLight: _shift(leather, lightness: 0.07, saturation: -0.02),
      leather: leather,
      leatherDark: _shift(leather, lightness: -0.075, saturation: 0.02),
      leatherWorn: _shift(leather, lightness: 0.17, saturation: -0.18),
      foil: goldMix(const Color(0xFFD4AF37), 0.72, 0.45),
      foilBright: goldMix(const Color(0xFFE8C87A), 0.80, 0.40),
      foilDim: goldMix(const Color(0xFFB9A77E), 0.55, 0.25),
      paperLight: _shift(leather, lightness: 0.10, saturation: -0.05),
      paper: _shift(leather, lightness: 0.06, saturation: -0.06),
      paperDark: _shift(leather, lightness: 0.02, saturation: -0.07),
      paperEdge: _shift(leather, lightness: 0.22, saturation: -0.15),
      pageBack: _shift(leather, lightness: 0.03, saturation: -0.07),
      ink: const Color(0xFFEDE3C8), // 内页文字米金
      mutedInk: goldMix(const Color(0xFFB9A77E), 0.62, 0.20),
      ribbon: const Color(0xFF8E3F37), // 丝带酒红点睛
    );
    _memoTone = tone;
    _memoPalette = palette;
    return palette;
  }

  static Color? _memoTone;
  static AgoraBookPalette? _memoPalette;

  /// 清 memo（测试用）。
  static void debugResetMemo() {
    _memoTone = null;
    _memoPalette = null;
  }

  /// 698 N46：**黑金书皮**（暗版）——近黑皮革 + 香槟/亮金烫字、
  /// 深色纸页金字（书皮不跟主题色，明暗固定）。
  static const AgoraBookPalette blackGold = AgoraBookPalette(
    leatherLight: Color(0xFF1E1A14),
    leather: Color(0xFF0E0D0B),
    leatherDark: Color(0xFF080706),
    leatherWorn: Color(0xFF2A241A),
    foil: Color(0xFFE8C87A), // 烫字=香槟金（标题）
    foilBright: Color(0xFFD4AF37), // 点缀亮金
    foilDim: Color(0xFFB9A77E), // 次文字金灰
    paperLight: Color(0xFF1C1913),
    paper: Color(0xFF161410),
    paperDark: Color(0xFF100E0A),
    paperEdge: Color(0xFF4A3F2C), // 金调描边
    pageBack: Color(0xFF12100C),
    ink: Color(0xFFE8C87A), // 内页文字=香槟金
    mutedInk: Color(0xFFB9A77E),
    ribbon: Color(0xFF8E3F37),
  );

  /// 698 N46：**白金书皮**（亮版）——暖白皮革 + 深金烫字、
  /// 暖白纸页深金字。
  static const AgoraBookPalette whiteGold = AgoraBookPalette(
    leatherLight: Color(0xFFFFFDF8),
    leather: Color(0xFFF7F4EE),
    leatherDark: Color(0xFFE8E2D6),
    leatherWorn: Color(0xFFD8CFC0),
    foil: Color(0xFF8A6D2F), // 烫字=深金（标题）
    foilBright: Color(0xFFB8860B), // 点缀深金
    foilDim: Color(0xFF6E6455), // 次文字暖灰
    paperLight: Color(0xFFFFFDF8),
    paper: Color(0xFFFAF6EE),
    paperDark: Color(0xFFF0EADC),
    paperEdge: Color(0xFFD8CFC0),
    pageBack: Color(0xFFF0EADC),
    ink: Color(0xFF8A6D2F), // 内页文字=深金
    mutedInk: Color(0xFF6E6455),
    ribbon: Color(0xFF8E3F37),
  );

  /// 明暗解析书皮：暗版黑金 / 亮版白金（N46 固定，不跟主题色）。
  static AgoraBookPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? blackGold : whiteGold;

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
