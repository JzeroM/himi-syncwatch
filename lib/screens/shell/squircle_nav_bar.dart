import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

/// 悬浮方块导航（698 N32-N34，样式注册表第③款）：Dribbble「Floating
/// Navigation Bar」动效 1:1（跳槽弹滑 + 图标接力 + 标签胶囊跟随）。
///
/// **N34 材质/几何定稿**：
/// - 条体 = 圆角矩形（r18、高 62 加高）+ **上下凹口 = 浮块/标签外扩轮廓**
///   （缘距恒 7dp：圆角矩形外扩 7 = 圆角矩形、胶囊外扩 7 = 胶囊，与形体
///   边缘全程平行）；GlassContainer 双形态玻璃 + 沿路径单线 rim（无椭圆
///   残留）；
/// - 浮块/标签 = **①款同源 GlassEffect 玻璃水滴**（LiquidBlobLens 同
///   管线：真折射镜片 + 菲涅尔亮边）——**不跟随主题色**（无色中性玻璃），
///   图标白色；玻璃关 = 平涂磨砂近似；
/// - 5 槽 = 首页/收藏/Emby/声网/设置（ShellNavBar.tab 组 0..4）。
///
/// **动效**（视频实测）：跳槽弹滑（easeOutBack 420ms）+ 标签延迟 40ms
/// 拖尾 + 图标接力（飞行中段交叉淡化）+ 落位 scale 弹跳。
class SquircleNavBar extends ConsumerStatefulWidget {
  const SquircleNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// 条高（N34 加高：54 → 62）。
  static const double navHeight = 62;

  /// 条体在盒内的顶部偏移（浮块悬顶余量）。
  static const double barTop = 14;

  /// 浮块尺寸/圆角（视频 squircle）。
  static const double block = 44;
  static const double blockRadius = 14;

  /// 条体圆角（圆角矩形——端部不是半圆胶囊）。
  static const double barRadius = 18;

  /// 凹口与浮块/标签的**恒定可见间距**（用户拍板「有间距的」）。
  static const double notchGap = 7;

  /// 浮块垂直落位（块心在条上缘下方 8 → 底部叠入条体）。
  static const double blockCenterY = 8;

  /// 标签骑跨条体下缘（中心 = 条下缘）。
  static double get labelCenterY => navHeight;

  /// 标签胶囊尺寸。
  static const double labelHeight = 20;
  static const double labelHalfHeight = 10;

  /// 盒高 = 悬顶余量 + 条高 + 标签下缘余量（防标签被屏幕裁切）。
  static const double boxHeight = barTop + navHeight + 12;

  /// 顶凹口水平半宽（= 浮块半宽 + 恒距，守卫直查）。
  static double get blockNotchRadius => block / 2 + notchGap;

  /// 跳槽时长 / 标签延迟（视频实测）。
  static const Duration slideDuration = Duration(milliseconds: 420);
  static const Duration labelLag = Duration(milliseconds: 40);

  /// 浮块层/条体层测试钥匙。
  static const Key blockKey = ValueKey('squircleBlock');
  static const Key barKey = ValueKey('squircleBar');

  /// 条体路径（N34）：圆角矩形 + **顶凹口 = 浮块外扩轮廓下半段**（58×58
  /// r21，缘距 7dp 全程平行）+ **底凹口 = 标签胶囊外扩轮廓上半段**（胶囊
  /// r17，缘距 7dp）。凹口随跳槽动画实时移动。
  static Path barPath({
    required Size size,
    required double blockCx,
    required double labelCx,
    required double labelHalfWidth,
  }) {
    final w = size.width;
    final h = size.height; // = navHeight
    final r = barRadius;
    final path = Path();

    // ── 顶凹口（浮块外扩轮廓）：半宽 29、角 r21、深 37 ──
    final topHalf = block / 2 + notchGap; // 29
    final topCornerR = blockRadius + notchGap; // 21
    final topDepth = blockCenterY + topHalf; // 37
    final topArcCy = topDepth - topCornerR; // 16
    final tx1 = (blockCx - topHalf).clamp(r, w - r);
    final tx2 = (blockCx + topHalf).clamp(r, w - r);

    path.moveTo(r, 0);
    if (tx2 - tx1 > 4) {
      path.lineTo(tx1, 0);
      path.lineTo(blockCx - topHalf, topArcCy);
      // 左下圆角（外扩轮廓圆角弧，π → π/2 逆时针）。
      path.arcTo(
        Rect.fromCircle(
          center: Offset(blockCx - topHalf + topCornerR, topArcCy),
          radius: topCornerR,
        ),
        math.pi,
        -math.pi / 2,
        false,
      );
      path.lineTo(blockCx + topHalf - topCornerR, topDepth);
      // 右下圆角（π/2 → 0）。
      path.arcTo(
        Rect.fromCircle(
          center: Offset(blockCx + topHalf - topCornerR, topArcCy),
          radius: topCornerR,
        ),
        math.pi / 2,
        -math.pi / 2,
        false,
      );
      path.lineTo(tx2, 0);
    }
    path.lineTo(w - r, 0);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r));
    path.lineTo(w, h - r);
    path.arcToPoint(Offset(w - r, h), radius: Radius.circular(r));

    // ── 底凹口（标签胶囊外扩轮廓）：半宽 labelHalfWidth+7、角 r17 ──
    final botCornerR = labelHalfHeight + notchGap; // 17（胶囊外扩）
    final botHalf = math.max(labelHalfWidth + notchGap, botCornerR);
    final bx1 = (labelCx + botHalf).clamp(r, w - r);
    final bx2 = (labelCx - botHalf).clamp(r, w - r);
    if (bx1 - bx2 > 4) {
      path.lineTo(bx1, h);
      // 右端半圆帽（0 → -π/2）。
      path.arcTo(
        Rect.fromCircle(
          center: Offset(labelCx + botHalf - botCornerR, h),
          radius: botCornerR,
        ),
        0,
        -math.pi / 2,
        false,
      );
      path.lineTo(labelCx - botHalf + botCornerR, h - botCornerR);
      // 左端半圆帽（-π/2 → -π）。
      path.arcTo(
        Rect.fromCircle(
          center: Offset(labelCx - botHalf + botCornerR, h),
          radius: botCornerR,
        ),
        -math.pi / 2,
        -math.pi / 2,
        false,
      );
      path.lineTo(bx2, h);
    }
    path.lineTo(r, h);
    path.arcToPoint(Offset(0, h - r), radius: Radius.circular(r));
    path.lineTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
    path.close();
    return path;
  }

  /// 标签胶囊实测宽度（凹口入口宽用；TextPainter 量文字 + 横向 padding）。
  static double labelWidthOf(String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 24; // 横向 padding 12×2
  }

  /// 玻璃水滴镜片参数（N34：①款 LiquidBlobLens 同源——无色中性玻璃，
  /// **不跟随主题色**；blur 0.01 为 Skia 捕获钥匙）。
  @visibleForTesting
  static lg.LiquidGlassSettings lensSettings() {
    return lg.AnimatedGlassIndicator.baseIndicatorSettings.copyWith(
      glassColor: Colors.white.withValues(alpha: 0.08),
      blur: 0.01,
    );
  }

  @override
  ConsumerState<SquircleNavBar> createState() => _SquircleNavBarState();
}

class _SquircleNavBarState extends ConsumerState<SquircleNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: SquircleNavBar.slideDuration,
    reverseDuration: SquircleNavBar.slideDuration,
  );

  /// 起跳槽 → 落位槽（跳槽期间图标接力用）。
  int _from = 0;
  int _to = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.currentIndex;
    _to = widget.currentIndex;
  }

  @override
  void didUpdateWidget(covariant SquircleNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != _to) {
      _from = _to;
      _to = widget.currentIndex;
      _slide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    if (i == _to) return;
    _from = _to;
    _to = i;
    _slide.forward(from: 0);
    widget.onSelect(i);
  }

  @override
  Widget build(BuildContext context) {
    final glassOn = ref.watch(settingsProvider.select((s) => s.glassUi));
    return SizedBox(
      height: SquircleNavBar.boxHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final slotWidth = totalWidth / ShellNavBar.tabCount;
        final labelHalfWidth =
            SquircleNavBar.labelWidthOf(ShellNavBar.tabLabels[_to]) / 2;
        return AnimatedBuilder(
          animation: _slide,
          builder: (context, _) {
            // 浮块位置：easeOutBack 轻过冲（视频跳槽弹滑）。
            final e = Curves.easeOutBack.transform(_slide.value);
            final blockCx = slotWidth * (_from + 0.5) * (1 - e) +
                slotWidth * (_to + 0.5) * e;
            // 标签延迟 40ms 拖尾（视频「甩」感）。
            final labelT = ((_slide.value *
                        SquircleNavBar.slideDuration.inMilliseconds -
                    SquircleNavBar.labelLag.inMilliseconds) /
                (SquircleNavBar.slideDuration.inMilliseconds -
                    SquircleNavBar.labelLag.inMilliseconds)).clamp(0.0, 1.0);
            final labelE = Curves.easeOutBack.transform(labelT);
            final labelCx = slotWidth * (_from + 0.5) * (1 - labelE) +
                slotWidth * (_to + 0.5) * labelE;
            // 凹口随跳槽实时重算（外扩轮廓跟随形体）。
            final barPath = SquircleNavBar.barPath(
              size: Size(totalWidth, SquircleNavBar.navHeight),
              blockCx: blockCx,
              labelCx: labelCx,
              labelHalfWidth: labelHalfWidth,
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 条体（圆角矩形 + 上下凹口；①款同源 GlassContainer）。
                Positioned(
                  left: 0,
                  top: SquircleNavBar.barTop,
                  width: totalWidth,
                  height: SquircleNavBar.navHeight,
                  child: IgnorePointer(
                    child: ClipPath(
                      clipper: _BarClipper(barPath),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GlassContainer(
                              key: SquircleNavBar.barKey,
                              // rim 与凹口路径对齐（半径 25 会露椭圆弧，
                              // N34 清线：用条体圆角，外缘单线由
                              // _BarRimPainter 沿凹口路径描）。
                              borderRadius: const BorderRadius.all(
                                  Radius.circular(SquircleNavBar.barRadius)),
                              padding: EdgeInsets.zero,
                              showShadow: false,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _BarRimPainter(barPath),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 槽位图标（未选中灰白；浮块内图标为主）。
                for (var i = 0; i < ShellNavBar.tabCount; i++)
                  _slotIcon(i, slotWidth),
                // 命中层（每槽 1/5 条宽 × 满条高，N29 无死区）。
                for (var i = 0; i < ShellNavBar.tabCount; i++)
                  _slotHit(i, slotWidth),
                // 标签胶囊（骑跨条下缘，嵌底凹口，恒距 7dp）。
                Positioned(
                  left: labelCx - labelHalfWidth,
                  top: SquircleNavBar.barTop +
                      SquircleNavBar.labelCenterY -
                      SquircleNavBar.labelHalfHeight,
                  child: IgnorePointer(
                    child: _label(glassOn),
                  ),
                ),
                // 浮块（悬条上方叠入顶凹口，恒距 7dp）。
                Positioned(
                  left: blockCx - SquircleNavBar.block / 2,
                  top: SquircleNavBar.barTop +
                      SquircleNavBar.blockCenterY -
                      SquircleNavBar.block / 2,
                  width: SquircleNavBar.block,
                  height: SquircleNavBar.block,
                  child: IgnorePointer(
                    child: ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.06).animate(
                        CurvedAnimation(
                          parent: _slide,
                          curve:
                              const Interval(0.0, 0.5, curve: Curves.easeOut),
                          reverseCurve: const Interval(0.5, 1.0),
                        ),
                      ),
                      child: _block(glassOn),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  /// 槽位图标：未选中灰白；浮块内图标为主（选中槽隐藏）。
  Widget _slotIcon(int i, double slotWidth) {
    final active = i == _to;
    return Positioned(
      left: slotWidth * i,
      top: SquircleNavBar.barTop,
      width: slotWidth,
      height: SquircleNavBar.navHeight,
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: active ? 0.0 : 1.0,
            child: Icon(
              ShellNavBar.tabIcons[i],
              size: 22,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _slotHit(int i, double slotWidth) {
    return Positioned(
      left: slotWidth * i,
      top: SquircleNavBar.barTop,
      width: slotWidth,
      height: SquircleNavBar.navHeight,
      child: TvFocusable(
        onTap: () => _selectTab(i),
        child: GestureDetector(
          key: ValueKey('squircleSlot$i'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectTab(i),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// 浮块（N34）：①款同源 GlassEffect 玻璃水滴（无色中性、图标白色）；
  /// 玻璃关 = 平涂磨砂近似。图标接力：飞行中段交叉淡化。
  Widget _block(bool glassOn) {
    final icon = Center(child: _relayIcon());
    if (!glassOn) {
      return DecoratedBox(
        key: SquircleNavBar.blockKey,
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(SquircleNavBar.blockRadius),
          ),
          color: Colors.white.withValues(alpha: 0.14),
          shadows: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: icon,
      );
    }
    final settings = SquircleNavBar.lensSettings();
    return lg.InheritedLiquidGlass(
      settings: settings,
      quality: lg.GlassQuality.standard,
      avoidsRefraction: false,
      child: DecoratedBox(
        key: SquircleNavBar.blockKey,
        decoration: const BoxDecoration(),
        child: Stack(
          children: [
            Positioned.fill(
              child: GlassEffect(
                shape: const lg.LiquidRoundedSuperellipse(
                  borderRadius: SquircleNavBar.blockRadius,
                ),
                settings: settings,
                quality: lg.GlassQuality.standard,
                interactionIntensity: 1.0,
                edgeZone: 20,
                clipExpansion: const EdgeInsets.all(12),
                rimThickness: 2.0,
                ambientRim: 0.08,
                baseAlphaMultiplier: 0.08,
                edgeAlphaMultiplier: 0.15,
                child: const SizedBox.expand(),
              ),
            ),
            icon,
          ],
        ),
      ),
    );
  }

  /// 图标接力（视频：飞行中段交叉淡化）。N34 图标白色（①款风格）。
  Widget _relayIcon() {
    const ink = Colors.white;
    final t = _slide.value;
    if (_from == _to || t >= 1) {
      return Icon(ShellNavBar.tabIcons[_to], size: 22, color: ink);
    }
    final fade = (t - 0.4).abs() < 0.4 ? 1 - ((t - 0.4).abs() / 0.4) : 0.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: t < 0.4 ? 1.0 : (1 - fade).clamp(0.0, 1.0),
          child: Icon(ShellNavBar.tabIcons[_from], size: 22, color: ink),
        ),
        Opacity(
          opacity: t < 0.4 ? 0.0 : fade.clamp(0.0, 1.0),
          child: Icon(ShellNavBar.tabIcons[_to], size: 22, color: ink),
        ),
      ],
    );
  }

  /// 标签胶囊（N34）：①款同源玻璃水滴（无色中性）；文字白色。
  /// 玻璃关 = 平涂磨砂近似。
  Widget _label(bool glassOn) {
    final text = Text(
      ShellNavBar.tabLabels[_to],
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    );
    if (!glassOn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          color: Colors.white.withValues(alpha: 0.14),
        ),
        child: text,
      );
    }
    final settings = SquircleNavBar.lensSettings();
    return SizedBox(
      width: SquircleNavBar.labelWidthOf(ShellNavBar.tabLabels[_to]),
      height: SquircleNavBar.labelHeight,
      child: lg.InheritedLiquidGlass(
        settings: settings,
        quality: lg.GlassQuality.standard,
        avoidsRefraction: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: GlassEffect(
                shape: const lg.LiquidRoundedSuperellipse(
                  borderRadius: SquircleNavBar.labelHalfHeight,
                ),
                settings: settings,
                quality: lg.GlassQuality.standard,
                interactionIntensity: 1.0,
                edgeZone: 20,
                clipExpansion: const EdgeInsets.all(12),
                rimThickness: 2.0,
                ambientRim: 0.08,
                baseAlphaMultiplier: 0.08,
                edgeAlphaMultiplier: 0.15,
                child: const SizedBox.expand(),
              ),
            ),
            Center(child: text),
          ],
        ),
      ),
    );
  }
}

/// 条体凹口裁剪（[SquircleNavBar.barPath] 同源路径）。
class _BarClipper extends CustomClipper<Path> {
  const _BarClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_BarClipper oldClipper) => oldClipper.path != path;
}

/// 条缘玻璃 rim（沿凹口路径描亮边——唯一名义边，无椭圆残留）。
class _BarRimPainter extends CustomPainter {
  const _BarRimPainter(this.path);

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.32),
    );
  }

  @override
  bool shouldRepaint(_BarRimPainter oldDelegate) => oldDelegate.path != path;
}
