import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// 液态玻璃视觉参数与布局预留量（着色/描边/投影/布局预留）。
///
/// 真折射、模糊与饱和由 liquid_glass_widgets 折射管线承担；
/// 本层只做半透明着色渐变、高光描边与悬浮投影。
class GlassConfig {
  const GlassConfig._();

  // [PATCH himi] 死代码清理：blurSigma/saturation/filter()/saturationMatrix()
  // 属于已被包折射管线取代的旧「BackdropFilter 模糊+饱和」方案，无调用方。

  /// 面板着色（底部导航胶囊 / 顶栏胶囊 / 浮动底栏），约 12% 以求透亮。
  static const Color panelTint = Color(0x1F1A1D23);

  /// 页面顶栏着色（渐变上深下浅）。
  static const Color barTint = Color(0x1F1A1D23);
  static const Color barTintSoft = Color(0x121A1D23);

  /// iOS(Impeller) 专用更淡着色：包内已走 GlassBodyMode.clear，本层 tint 再
  /// 压到约 5% → 背景更透（12% 深色膜是 iOS 看着「不透」的主因）。
  static const Color panelTintIos = Color(0x0D1A1D23);
  static const Color barTintIos = Color(0x0D1A1D23);
  static const Color barTintSoftIos = Color(0x081A1D23);

  /// 面板着色（按平台）：iOS 用更淡的 [panelTintIos]。
  static Color panelTintOf() =>
      defaultTargetPlatform == TargetPlatform.iOS ? panelTintIos : panelTint;

  /// 顶栏着色（按平台）。
  static Color barTintOf() =>
      defaultTargetPlatform == TargetPlatform.iOS ? barTintIos : barTint;

  static Color barTintSoftOf() => defaultTargetPlatform == TargetPlatform.iOS
      ? barTintSoftIos
      : barTintSoft;

  /// 关闭玻璃后的降级纯色。
  static const Color fallbackColor = Color(0xF01A1D24);

  /// 高光描边基色（约 30% 白）。
  static const Color rimColor = Color(0x4DFFFFFF);

  /// [PATCH himi] iOS 顶栏底边高光降白（30% → 16%）：清晰背景上的白硬线
  /// 是 iOS「不够透/有边框感」的观感来源之一。
  static const Color rimColorIos = Color(0x29FFFFFF);

  /// 高光描边基色（按平台）：iOS 用更淡的 [rimColorIos]。
  static Color rimColorOf() =>
      defaultTargetPlatform == TargetPlatform.iOS ? rimColorIos : rimColor;

  /// 内侧高光渐变（顶部更亮，底部渐隐）。
  static const Color highlightTop = Color(0xB3FFFFFF);
  static const Color highlightBottom = Color(0x00FFFFFF);

  /// 悬浮投影（让玻璃面板与背景产生距离感，轻量不压画面）。
  static const List<BoxShadow> panelShadow = [
    BoxShadow(
      color: Color(0x4A000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  /// [PATCH himi] iOS 悬浮投影降黑（29% → 16%，blur 16→12，offset 6→4）：
  /// iOS 走 clear 体透明，29% 黑影直接压在清晰背景上显脏、显「不透」。
  static const List<BoxShadow> panelShadowIos = [
    BoxShadow(
      color: Color(0x29000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// 悬浮投影（按平台）：iOS 用更轻的 [panelShadowIos]。
  static List<BoxShadow> panelShadowOf() =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? panelShadowIos
          : panelShadow;

  /// 底部导航在每个标签页内容区预留的高度（不含安全区）。
  static const double shellBottomReserve = 96;

  /// 顶栏玻璃下方内容的起始纵向位置（需配合 extendBodyBehindAppBar）。
  static double topInsetOf(BuildContext context) {
    return MediaQuery.of(context).padding.top + kToolbarHeight + 8;
  }

  /// 标签页内容区底部预留（含安全区，viewPadding 不受 removePadding 影响）。
  static double bottomReserveOf(BuildContext context) {
    return shellBottomReserve + MediaQuery.viewPaddingOf(context).bottom;
  }
}
