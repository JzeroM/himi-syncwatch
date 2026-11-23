import 'package:flutter/material.dart';

/// 导航共享色板（698 N32）：主题色渐变滴/浮块与深图标配色——②款流体
/// 液态、③款悬浮方块同源（视觉家族一致）。
class NavPalette {
  NavPalette._();

  /// 滴/浮块渐变回退（主题色 null = 跟随默认底色 → 银白玻璃渐变）。
  static const Color dropFallbackLight = Color(0xFFF4F5F8);
  static const Color dropFallbackDeep = Color(0xFFC6CAD3);

  /// 深图标压亮底回退（N32：同构视频「深图标压亮底」）。
  static const Color inkFallback = Color(0xFF3A3F47);

  /// 滴/浮块渐变（**跟随主题色**——顶左 = 主题色提亮 55%、
  /// 底右 = 主题色本色；null 回退银白玻璃渐变）。
  static List<Color> dropGradient(int? themeColorValue) {
    if (themeColorValue == null) {
      return const [dropFallbackLight, dropFallbackDeep];
    }
    final accent = Color(themeColorValue);
    return [Color.lerp(Colors.white, accent, 0.55)!, accent];
  }

  /// 浮块内深图标色（主题色加深 60%；null 回退深灰）。
  static Color dropInkColor(int? themeColorValue) {
    if (themeColorValue == null) return inkFallback;
    return Color.lerp(Color(themeColorValue), Colors.black, 0.6)!;
  }
}
