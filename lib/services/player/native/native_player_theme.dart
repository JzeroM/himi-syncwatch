import 'dart:ui' show Color;

/// 原生播放器控制层视觉规格（Android / 鸿蒙共用）。
///
/// 数值全部对齐 Flutter 播放页（手机横屏 / TV 两套），是原生控制层的
/// 唯一视觉真相源；Kotlin / ArkTS 侧按同名常量落地（见
/// `docs/native_player_plan.md` §视觉规格）。
///
/// 说明：
/// - 颜色用 `0xAARRGGBB`；
/// - 尺寸单位：Android 为 dp、鸿蒙为 vp，均与 Flutter 逻辑像素 1:1；
/// - 面板/胶囊背景在 Android 跨窗口无法真模糊，用 tint + rim 近似，
///   鸿蒙用 `backgroundBlurStyle` 真模糊。
abstract final class NativePlayerTheme {
  NativePlayerTheme._();

  // ── 基础色 ────────────────────────────────────────────────
  /// 主题强调色（滑杆/角标/选中态）。
  static const Color accent = Color(0xFF6366F1);

  /// 强调色 30%（解码面板选中行底）。
  static const Color accentSoft = Color(0x4D6366F1);

  /// 纯白（主文本/图标）。
  static const Color white = Color(0xFFFFFFFF);

  /// 白 70%（时间/网速/倍速文本）。
  static const Color white70 = Color(0xB3FFFFFF);

  /// 白 54%（面板描述/次级信息）。
  static const Color white54 = Color(0x8AFFFFFF);

  /// 白 38%（段标题/禁用图标）。
  static const Color white38 = Color(0x62FFFFFF);

  /// 白 24%（不可用按钮）。
  static const Color white24 = Color(0x3DFFFFFF);

  // ── 玻璃 / 浮层 ───────────────────────────────────────────
  /// 面板着色（12% 深色膜）。
  static const Color panelTint = Color(0x1F1A1D23);

  /// 关闭液态玻璃时的降级底（10%）。
  static const Color fallbackTint = Color(0x1A1A1D23);

  /// 高光描边（30% 白）。
  static const Color rim = Color(0x4DFFFFFF);

  /// 解码模式面板实底（`#1E1E2E`）。
  static const Color decodePanel = Color(0xFF1E1E2E);

  /// 解码模式面板当前值文字（`#A5B4FC`）。
  static const Color decodeCurrentText = Color(0xFFA5B4FC);

  /// TV 进度条焦点环（`#C1C2FE`）。
  static const Color focusRing = Color(0xFFC1C2FE);

  /// 片头片尾居中玻璃卡投影。
  static const Color shadow = Color(0x4A000000);

  // ── 圆角 ──────────────────────────────────────────────────
  static const double radiusPanel = 16;
  static const double radiusChip = 10;
  static const double radiusCard = 18;
  static const double radiusDecode = 8;
  static const double radiusBadge = 9;

  // ── 液态玻璃（对齐 Flutter GlassConfig / liquid_glass_widgets）──
  /// 背景模糊半径（Flutter GlassConfig.blurSigma = 20）。
  static const double glassBlurRadius = 20;

  /// 背景饱和度增益（Flutter GlassConfig.saturation = 1.6）。
  static const double glassSaturation = 1.6;

  /// 顶部高光带（菲涅尔近似，Flutter GlassConfig.highlightTop）。
  static const Color glassHighlightTop = Color(0xB3FFFFFF);

  /// 底部高光渐隐端（Flutter GlassConfig.highlightBottom）。
  static const Color glassHighlightBottom = Color(0x00FFFFFF);

  /// 内缘暗描边（Flutter GlassConfig.innerRimColor）。
  static const Color glassInnerRim = Color(0x33000000);

  /// 折射带宽度（dp）：面板边缘的凸透镜折射观感带。
  static const double glassRefractionBand = 10;

  /// 折射带放大系数（边缘放大 = 液态玻璃典型折射观感）。
  static const double glassRefractionZoom = 1.12;

  /// 采样模糊降采样比（采样帧缩小 N 倍再拉大 = 软模糊）。
  static const int glassBlurDownsample = 4;

  // ── 顶栏 ──────────────────────────────────────────────────
  static const double topBarHeight = 48;
  static const double topIconSize = 22;
  static const double topChipIconSize = 18;
  static const double titleSize = 16;
  static const double titleWeight = 600;
  static const double captionSize = 12;

  /// 内核/字幕样式/解码胶囊内边距。
  static const double chipPadH = 9;
  static const double chipPadV = 6;

  /// TV 时钟：右距 12，尺寸 100×48。
  static const double clockWidth = 100;
  static const double clockHeight = 48;
  static const double clockRight = 12;
  static const double clockFontSize = 13;

  // ── 底栏 ──────────────────────────────────────────────────
  /// Logo 尺寸 240×44。
  static const double logoWidth = 240;
  static const double logoHeight = 44;

  /// 时间文本列宽（`56/78`）。
  static const double timeCellWidth = 56;
  static const double timeCellWidthWide = 78;

  /// 进度条：track 6、thumb 8。
  static const double seekTrackHeight = 6;
  static const double seekThumbRadius = 8;

  /// TV 进度条焦点环：3px + blur 14 / spread 1.5。
  static const double seekFocusRingWidth = 3;
  static const double seekFocusBlur = 14;
  static const double seekFocusSpread = 1.5;

  /// 播放组：上一个 28 / 播放 36 / 下一个 28。
  static const double transportSideSize = 28;
  static const double transportPlaySize = 36;
  static const double transportGap = 8;

  /// 右侧图标 24、间距 20。
  static const double controlIconSize = 24;
  static const double controlGap = 20;

  /// 角标：9px 字、`#6366F1` 圆底。
  static const double badgeFontSize = 9;
  static const double badgeMinSize = 14;

  /// 锁钮 22。
  static const double lockIconSize = 22;

  // ── 面板 ──────────────────────────────────────────────────
  /// 右侧浮层：宽度 clamp(0.42×屏宽, 260, 320)。
  static const double panelWidthRatio = 0.42;
  static const double panelMinWidth = 260;
  static const double panelMaxWidth = 320;

  /// 右侧浮层相对边距：right 12、top = safeTop + 48、bottom = 116 + safeBottom。
  static const double panelRight = 12;
  static const double panelTopOffset = 48;
  static const double panelBottomOffset = 116;

  /// 面板内边距 h16 v12、圆角 16。
  static const double panelPadH = 16;
  static const double panelPadV = 12;

  /// 面板标题 15 加粗；选项行 14。
  static const double panelTitleSize = 15;
  static const double panelOptionSize = 14;

  /// 选中项对勾占位槽宽 18。
  static const double panelCheckSlot = 18;

  // ── 显示调节 ──────────────────────────────────────────────
  /// 行 = 标签 44 / 滑杆 / 数值 48；padding h16 v10。
  static const double adjustLabelWidth = 44;
  static const double adjustValueWidth = 48;
  static const double adjustRowPadH = 16;
  static const double adjustRowPadV = 10;

  /// 段标题 11 white38。
  static const double sectionTitleSize = 11;

  // ── 解码模式 ──────────────────────────────────────────────
  static const double decodePanelWidth = 180;
  static const double decodeTitleSize = 13;
  static const double decodeValueSize = 12;
  static const double decodeDescSize = 10;
  static const double decodeRadioSize = 16;

  // ── 片头片尾卡 ────────────────────────────────────────────
  static const double segmentCardWidth = 360;
  static const double segmentTitleSize = 16;
  static const double segmentRowIconSize = 22;
  static const double segmentRowTitleSize = 14;
  static const double segmentRowHintSize = 11;
  static const double segmentChevronSize = 18;

  // ── 动效 ──────────────────────────────────────────────────
  /// 控件显隐动画时长（ms）。
  static const int controlsFadeMs = 200;

  /// 自动隐藏延时（ms）：全模式 5 秒。
  static const int autoHideMs = 5000;

  /// 面板项选中色（强调色）。
  static Color get selectedText => accent;
}
