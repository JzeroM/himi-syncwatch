import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/nav_palette.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 悬浮方块导航（698 N32，样式注册表第③款）：Dribbble「Floating
/// Navigation Bar」**动效 1:1 复刻**（视频逐帧实测：跳槽弹滑 + 图标接力 +
/// 标签胶囊跟随），材质换项目液态玻璃（条体 = ①款同源 GlassContainer
/// 双形态；浮块/标签 = 主题色渐变，深图标压亮底）。
///
/// **几何**：条高 54 + 浮块悬浮条上方（navHeight 区内叠放）；5 槽 =
/// 首页/收藏/Emby/声网/设置（ShellNavBar.tab 组 0..4，A 案无中央主钮）。
///
/// **动效**（视频实测）：
/// - 跳槽弹滑：浮块 + 标签胶囊弹向目标槽（easeOutBack 轻过冲 420ms，
///   标签延迟 40ms 拖出「甩」感）；
/// - 图标接力：目标槽图标**先亮**（主题色）→ 浮块飞行中段交叉淡化为
///   目标项图标 → 源槽图标回落灰；
/// - 落位弹一下（scale 1.0→1.06→1.0）。
class SquircleNavBar extends ConsumerStatefulWidget {
  const SquircleNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// 条高（①款同源）。
  static const double navHeight = ShellNavBar.navHeight;

  /// 浮块尺寸/圆角（视频 squircle）。
  static const double block = 44;
  static const double blockRadius = 14;

  /// 条体圆角（698 N33：圆角矩形——端部不是半圆胶囊）。
  static const double barRadius = 18;

  /// 凹口与浮块/标签的**恒定可见间距**（698 N33 用户拍板「有间距的」）。
  static const double notchGap = 7;

  /// 浮块/标签垂直落位（块心在条心上方；标签骑跨条体下缘）。
  static const double blockCenterY = 8;
  static const double labelCenterY = 54;

  /// 盒高 = 浮块悬顶余量 + 条高 + 标签下缘余量（N33，防标签被屏幕裁切）。
  static const double boxHeight = 80;

  /// 顶凹口半径（= 浮块半宽 + 恒距，守卫直查）。
  static double get blockNotchRadius => block / 2 + notchGap;

  /// 跳槽时长 / 标签延迟（视频实测）。
  static const Duration slideDuration = Duration(milliseconds: 420);
  static const Duration labelLag = Duration(milliseconds: 40);

  /// 浮块层/条体层测试钥匙。
  static const Key blockKey = ValueKey('squircleBlock');
  static const Key barKey = ValueKey('squircleBar');

  /// 条体路径（698 N33）：圆角矩形 + **顶缘凹口托浮块 + 底缘凹口托标签**。
  /// 恒距几何（用户拍板「和凹槽有间距的」）：凹口入口宽 = 形体半宽 +
  /// [notchGap]、凹深 = 形体半高 + [notchGap]——形体缘与凹口弧全程
  /// 间距 [notchGap]（切线竖直进入/水平触底，U 形贴合）。
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

    // ── 顶凹口（托浮块）：U 形下凹，缘距 7dp ──
    // 入口宽 = 块半宽 + 7；凹深 = 块底（blockCenterY + 块半高）+ 7。
    final topHalfSpan = block / 2 + notchGap;
    final topDepth = blockCenterY + block / 2 + notchGap;
    // 入口钳位到圆角区内（窄屏边缘槽凹口收窄但不消失，N33 边界守卫）。
    final tx1 = (blockCx - topHalfSpan).clamp(r, w - r);
    final tx2 = (blockCx + topHalfSpan).clamp(r, w - r);

    path.moveTo(r, 0);
    if (tx2 - tx1 > 4) {
      path.lineTo(tx1, 0);
      // 左半 U：竖直切入 → 水平触底（cubic 切线控制）。
      path.cubicTo(
        tx1, topDepth * 0.55,
        blockCx - (blockCx - tx1) * 0.45, topDepth,
        blockCx, topDepth,
      );
      // 右半 U（镜像）。
      path.cubicTo(
        blockCx + (tx2 - blockCx) * 0.45, topDepth,
        tx2, topDepth * 0.55,
        tx2, 0,
      );
    }
    path.lineTo(w - r, 0);
    path.arcToPoint(Offset(w, r), radius: Radius.circular(r));
    path.lineTo(w, h - r);
    path.arcToPoint(Offset(w - r, h), radius: Radius.circular(r));

    // ── 底凹口（托标签）：U 形上凹，缘距 7dp ──
    // 入口宽 = 标签半宽 + 7；凹深 = 标签半高 + 7（标签中心在条下缘）。
    final botHalfSpan = labelHalfWidth + notchGap;
    final botDepth = labelHalfHeight + notchGap;
    final bx1 = (labelCx + botHalfSpan).clamp(r, w - r);
    final bx2 = (labelCx - botHalfSpan).clamp(r, w - r);
    if (bx1 - bx2 > 4) {
      path.lineTo(bx1, h);
      path.cubicTo(
        bx1, h - botDepth * 0.55,
        labelCx + (bx1 - labelCx) * 0.45, h - botDepth,
        labelCx, h - botDepth,
      );
      path.cubicTo(
        labelCx - (labelCx - bx2) * 0.45, h - botDepth,
        bx2, h - botDepth * 0.55,
        bx2, h,
      );
    }
    path.lineTo(r, h);
    path.arcToPoint(Offset(0, h - r), radius: Radius.circular(r));
    path.lineTo(0, r);
    path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
    path.close();
    return path;
  }

  /// 标签胶囊高度（凹口深度 = 半高 + gap 用）。
  static const double labelHeight = 20;
  static const double labelHalfHeight = 10;

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
    // 698 N32：浮块/标签渐变跟随主题色（null 回退银白）。
    final themeColor = ref.watch(settingsProvider.select((s) => s.themeColor));
    return SizedBox(
      height: SquircleNavBar.boxHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final slotWidth = totalWidth / ShellNavBar.tabCount;
        // 标签宽度（= 浮块跳槽到该槽时标签胶囊的实测宽，凹口半径用）。
        final labelHalfWidth =
            SquircleNavBar.labelWidthOf(ShellNavBar.tabLabels[_to]) / 2;
        return AnimatedBuilder(
          animation: _slide,
          builder: (context, _) {
            // 浮块位置：easeOutBack 轻过冲（视频跳槽弹滑）。
            final e = Curves.easeOutBack.transform(_slide.value);
            final blockCx =
                (slotWidth * (_from + 0.5) * (1 - e) + slotWidth * (_to + 0.5) * e);
            // 标签延迟 40ms 拖尾（视频「甩」感）。
            final labelT = ((_slide.value * SquircleNavBar.slideDuration.inMilliseconds -
                        SquircleNavBar.labelLag.inMilliseconds) /
                    (SquircleNavBar.slideDuration.inMilliseconds -
                        SquircleNavBar.labelLag.inMilliseconds))
                .clamp(0.0, 1.0);
            final labelE = Curves.easeOutBack.transform(labelT);
            final labelCx =
                (slotWidth * (_from + 0.5) * (1 - labelE) + slotWidth * (_to + 0.5) * labelE);
            // N33：条体路径随跳槽实时重算（凹口跟随浮块/标签）。
            final barPath = SquircleNavBar.barPath(
              size: Size(totalWidth, SquircleNavBar.navHeight),
              blockCx: blockCx,
              labelCx: labelCx,
              labelHalfWidth: labelHalfWidth,
            );
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 条体（N33：圆角矩形 + 上下凹口；①款同源 GlassContainer）。
                Positioned(
                  left: 0,
                  top: 14,
                  width: totalWidth,
                  height: SquircleNavBar.navHeight,
                  child: IgnorePointer(
                    child: ClipPath(
                      clipper: _BarClipper(barPath),
                      child: Stack(
                        children: [
                          const Positioned.fill(
                            child: GlassContainer(
                              key: SquircleNavBar.barKey,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(25)),
                              padding: EdgeInsets.zero,
                              showShadow: false,
                              child: SizedBox.expand(),
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
                // 槽位图标（未选中灰 / 目标先亮）。
                for (var i = 0; i < ShellNavBar.tabCount; i++)
                  _slotIcon(i, slotWidth),
                // 命中层（每槽 1/5 条宽 × 满高，N29 无死区）。
                for (var i = 0; i < ShellNavBar.tabCount; i++)
                  _slotHit(i, slotWidth),
                // 标签胶囊（N33：骑跨条体下缘，嵌底凹口，恒距 7dp）。
                Positioned(
                  left: labelCx - labelHalfWidth,
                  top: 14 + SquircleNavBar.labelCenterY -
                      SquircleNavBar.labelHalfHeight,
                  child: IgnorePointer(
                    child: _label(themeColor),
                  ),
                ),
                // 浮块（N33：主体悬条上方，底部叠入顶凹口，恒距 7dp）。
                Positioned(
                  left: blockCx - SquircleNavBar.block / 2,
                  top: 14 + SquircleNavBar.blockCenterY -
                      SquircleNavBar.block / 2,
                  width: SquircleNavBar.block,
                  height: SquircleNavBar.block,
                  child: IgnorePointer(
                    child: ScaleTransition(
                      scale: Tween(begin: 1.0, end: 1.06).animate(
                        CurvedAnimation(
                          parent: _slide,
                          curve: const Interval(0.0, 0.5,
                              curve: Curves.easeOut),
                          reverseCurve: const Interval(0.5, 1.0),
                        ),
                      ),
                      child: _block(themeColor),
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

  /// 槽位图标：未选中灰白；目标槽（飞行中）主题色先亮；浮块内图标为主。
  Widget _slotIcon(int i, double slotWidth) {
    final active = i == _to;
    return Positioned(
      left: slotWidth * i,
      top: 14,
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
      top: 14,
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

  /// 浮块：主题色渐变 squircle + 深图标（视频「深图标压亮底」）。
  /// 图标接力：飞行中段交叉淡化（_from 图标 → _to 图标）。
  Widget _block(int? themeColor) {
    return DecoratedBox(
      key: SquircleNavBar.blockKey,
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SquircleNavBar.blockRadius),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: NavPalette.dropGradient(themeColor),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: _relayIcon(themeColor),
      ),
    );
  }

  /// 图标接力（视频：飞行中段交叉淡化）。
  Widget _relayIcon(int? themeColor) {
    final ink = NavPalette.dropInkColor(themeColor);
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

  /// 标签胶囊（主题色渐变，文案 = tab 组）。
  Widget _label(int? themeColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: NavPalette.dropGradient(themeColor),
        ),
      ),
      child: Text(
        ShellNavBar.tabLabels[_to],
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
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

/// 条缘玻璃 rim（沿凹口路径描亮边，视频同款玻璃折光缘）。
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
