import 'dart:ui';

import 'package:flutter/material.dart';

/// 液态玻璃视觉参数与布局预留量。
///
/// 保真度 A 近似方案：背景模糊 + 饱和增强 + 半透明着色 + 高光描边，
/// 不做真实折射着色器，保证中低端设备可用。
class GlassConfig {
  const GlassConfig._();

  /// 背景模糊半径（逻辑像素）。
  static const double blurSigma = 20;

  /// 模糊后叠加的饱和度增强系数。
  static const double saturation = 1.6;

  /// 面板着色（底部导航胶囊 / 顶栏胶囊 / 浮动底栏）。
  static const Color panelTint = Color(0x401A1D23);

  /// 页面顶栏着色（渐变上深下浅）。
  static const Color barTint = Color(0x401A1D23);
  static const Color barTintSoft = Color(0x261A1D23);

  /// 关闭玻璃后的降级纯色。
  static const Color fallbackColor = Color(0xF01A1D24);

  /// 高光描边基色（约 20% 白）。
  static const Color rimColor = Color(0x33FFFFFF);

  /// 内侧高光渐变（顶部更亮，底部渐隐）。
  static const Color highlightTop = Color(0x8CFFFFFF);
  static const Color highlightBottom = Color(0x00FFFFFF);

  /// 玻璃厚度暗线（外亮线内侧的 0.5px 折射暗边）。
  static const Color innerRimColor = Color(0x33000000);

  /// 悬浮投影（让玻璃面板与背景产生距离感）。
  static const List<BoxShadow> panelShadow = [
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  /// 底部导航在每个标签页内容区预留的高度（不含安全区）。
  static const double shellBottomReserve = 96;

  /// 模糊 + 饱和增强合成滤镜。
  static ImageFilter filter({
    double sigma = blurSigma,
    double sat = saturation,
  }) {
    return ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      inner: ColorFilter.matrix(saturationMatrix(sat)),
    );
  }

  /// 标准饱和度矩阵（4x5，行主序）。
  static List<double> saturationMatrix(double s) {
    return <double>[
      0.213 + 0.787 * s,
      0.715 - 0.715 * s,
      0.072 - 0.072 * s,
      0,
      0,
      0.213 - 0.213 * s,
      0.715 + 0.285 * s,
      0.072 - 0.072 * s,
      0,
      0,
      0.213 - 0.213 * s,
      0.715 - 0.715 * s,
      0.072 + 0.928 * s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// 顶栏玻璃下方内容的起始纵向位置（需配合 extendBodyBehindAppBar）。
  static double topInsetOf(BuildContext context) {
    return MediaQuery.of(context).padding.top + kToolbarHeight + 8;
  }

  /// 标签页内容区底部预留（含安全区，viewPadding 不受 removePadding 影响）。
  static double bottomReserveOf(BuildContext context) {
    return shellBottomReserve + MediaQuery.viewPaddingOf(context).bottom;
  }
}
