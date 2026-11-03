import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
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

  /// 面板（GlassContainer）关闭玻璃后的半透明着色底（约 90% 透明，
  /// 仅 10% 深色膜，无模糊/折射；配合 rimColor 白描边定界）。
  /// 顶栏 GlassBackdrop 例外：关闭后仍保留普通磨砂模糊。
  static const Color fallbackColor = Color(0x1A1A1D23);

  /// 弹层（操作面板/底部 sheet）着色：94% 不透明深色膜——弹层需压住
  /// 背景内容保证可读，不随全局降级改淡。
  static const Color popupTint = Color(0xF01A1D23);

  /// 弹层关闭玻璃后的降级底（与 [popupTint] 同值，保持 94% 不透明）。
  static const Color popupFallback = Color(0xF01A1D23);

  /// 高光描边基色（约 30% 白）。
  static const Color rimColor = Color(0x4DFFFFFF);

  /// 内侧高光渐变（顶部更亮，底部渐隐）。
  static const Color highlightTop = Color(0xB3FFFFFF);
  static const Color highlightBottom = Color(0x00FFFFFF);

  /// 玻璃厚度暗线（外亮线内侧的 0.5px 折射暗边）。
  static const Color innerRimColor = Color(0x33000000);

  /// 悬浮投影（让玻璃面板与背景产生距离感，轻量不压画面）。
  static const List<BoxShadow> panelShadow = [
    BoxShadow(
      color: Color(0x4A000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  /// 底部导航在每个标签页内容区预留的高度（不含安全区）。
  static const double shellBottomReserve = 96;

  // ═══════════════════════════════════════════════════════════════
  // 播放器弹层专用「白底磨砂」调色板
  // ═══════════════════════════════════════════════════════════════
  //
  // 【范围铁律】仅播放器内的弹出面板（右侧侧栏 / 解码 popover /
  // 片头片尾卡）使用；顶栏、底栏、手势提示胶囊、以及 App 其他页面
  // （设置页、缓存页、更新弹窗）**一律沿用上面的深色玻璃常量**。
  //
  // 因此这里**不修改** panelTint / popupTint / fallbackColor 等既有
  // 常量（`test/native_player_layout_test.dart` 有断言锁死 panelTint
  // 仍为 0x1F1A1D23），只新增播放器弹层专用的一组。

  /// 播放器弹层**暖白磨砂**基色（90% 不透明）。
  ///
  /// 586 由 585 的纯白基色改暖白：纯白在暗适应状态下亮度差近 20:1，
  /// 弹层一出现眼睛会本能躲闪；暖白（R>G>B 微弱偏暖）把刺眼度压下来，
  /// 同时保证黑字在任意画面上可读。
  static const Color playerPanelWhite = Color(0xE6F4F2EE);

  /// 播放器弹层竖向渐变（顶部提亮 → 基色 → 底部略透 = 菲涅尔高光近似）。
  static const Color playerPanelWhiteTop = Color(0xF2FAF8F4);
  static const Color playerPanelWhiteBottom = Color(0xD6EAE7E1);

  /// 暖白玻璃定界描边（浅底必须靠**暗**边，白描边在亮画面上会消失）。
  static const Color playerPanelRimLight = Color(0x26000000);

  /// 播放器弹层投影（比深色版更重，浅色面板需要靠投影「浮」起来）。
  static const List<BoxShadow> playerPanelShadow = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// 面板文字（586 起**取消三色分级**，只留两级）：
  /// - 主：正文一律近黑 [playerPanelTextPrimary]（选项行不再用强调色）；
  /// - 次：说明/占位黑 72% [playerPanelTextSecondary]。
  ///
  /// [playerPanelTextTertiary] 保留为别名（历史调用点仍在用），值与次同级，
  /// 避免同一面板里出现三种灰度。
  static const Color playerPanelTextPrimary = Color(0xFF1B1B1F);
  static const Color playerPanelTextSecondary = Color(0xB8000000);
  static const Color playerPanelTextTertiary = Color(0xB8000000);

  /// 暖白底分隔线（黑 12%，0.5dp；纯白底下 8% 几乎看不见）。
  static const Color playerPanelDivider = Color(0x1F000000);

  /// 播放器弹层统一排版（586）：标题 15/w600、正文 14/w500、说明 12/w500。
  ///
  /// 三端逐值对齐（安卓 `NPTheme.TEXT_*` / 鸿蒙 `NativePlayerPanel.TEXT_*`），
  /// 任一改动必须三处同步（`test/native_player_layout_test.dart` 有断言）。
  static const double playerPanelTitleSize = 15;
  static const double playerPanelTitleWeight = 600;
  static const double playerPanelBodySize = 14;
  static const double playerPanelBodyWeight = 500;
  static const double playerPanelCaptionSize = 12;
  static const double playerPanelCaptionWeight = 500;

  /// 浅色选中行底色（强调色 12%）与选中文字色。
  static const Color playerPanelSelectedBg = Color(0x1F6366F1);

  /// 浅色滑杆：轨道（黑 12%）/ 已播（强调色）/ 拇指（纯白 + 微投影）。
  static const Color playerPanelTrackInactive = Color(0x1F000000);
  static const Color playerPanelThumb = Color(0xFFFFFFFF);

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
