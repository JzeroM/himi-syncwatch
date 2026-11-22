import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 流体液态导航（698 N17，样式注册表第②款）：Dribbble「Bottom Navigation
/// Micro Interaction」同款**悬浮凹口 + 水滴分裂**动效——用户上传视频
/// （`.clawbench/uploads/01d7efc…mp4`）逐帧 1:1 分解复刻，全玻璃纯白零彩色。
///
/// **视频逐帧规格**（30fps 实测，展开 0.9s / 收回 0.7s）：
/// - 涟漪环蓄力（0-160ms）：细环 1.9R 向内收缩贴上母滴，越收越亮，
///   在母滴边缘亮成白环，随后化作淡波向外散去；
/// - 母滴预拉伸（160-230ms）：向斜上方拉成倾斜胶囊（蓄力弹射）；
/// - gooey 拉丝分裂（230-430ms）：子滴从母滴拉出，metaball 细颈
///   粘连→变细→断裂；左上 Emby → 正上声网 → 右上设置 错峰弹出；
/// - ＋ 旋转 45° 成 ×（~300ms）；卫星小液滴飞散淡出（纯液体细节）；
///   子滴**图标落位后才淡入**（飞行中是纯液滴）；
/// - 展开态：母滴变**空心玻璃环 + ×**，三子滴扇形落位（中心略高）；
/// - 收回（0.7s）严格反序：× 亮环 → 右→中→左 飞回 gooey 吸收
///   → 最后一滴椭圆过冲回落凹口弹性回稳。
///
/// **形状**：胶囊条 + 顶缘中央弧形凹口（cos 谷，母滴半嵌）+ 悬浮玻璃圆钮；
/// 子滴 Ø≈母滴 1.35×（视频像素实测 74/54）。
///
/// **双玻璃形态（N5-G，随「液态玻璃」开关）**：开 = 液态玻璃（折射胶囊 +
/// 液滴高光/光晕，goo 层半透 0.92）；关 = 轻量磨砂（模糊 + 半透明 +
/// 描边，goo 层 0.82）。**纯玻璃白，零彩色**（用户拍板）。
class FluidGlassNavBar extends ConsumerStatefulWidget {
  const FluidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  // ── 几何常量（698 N17，守卫测试直查）─────────────────────────────

  /// 导航条高（与玻璃水滴款同档）。
  static const double navHeight = ShellNavBar.navHeight;

  /// 凹口上方飞行区高（展开三钮/命中区；盒子高 = navHeight + flyZone）。
  static const double flyZone = 96;

  /// 母滴直径（悬浮圆钮）。
  static const double motherSize = 46;

  /// 子滴直径 ≈ 母滴 1.35×（视频实测 74/54）。
  static const double childSize = 62;

  /// 子滴/母滴直径比（守卫：1.35 档）。
  static const double childScaleRatio = childSize / motherSize;

  /// 母滴圆心（相对条顶）。
  static const double motherCenterY = 14;

  /// 子滴圆心高于母滴圆心的量（视频 1.48×Ø）。
  static const double childRise = 68;

  /// 中心子滴额外上浮（视频中心高 15px ≈ 0.28×Ø）。
  static const double centerExtraRise = 13;

  /// 子滴横向间距（±，中线两侧）。
  static const double childSpread = 108;

  /// 卫星小液滴半径（约子滴 1/5，视频细节）。
  static const double satelliteRadius = 6;

  // ── 动效时间线（归一化 t∈[0,1]，守卫测试直查）───────────────────

  /// 展开总时长（视频 ~0.9s）；收回走 reverseDuration（视频 ~0.7s）。
  static const Duration expandDuration = Duration(milliseconds: 900);
  static const Duration collapseDuration = Duration(milliseconds: 700);

  /// 三子滴飞行区间（错峰 0.13 / 0.10，左→中→右）。
  static const List<double> childStarts = [0.20, 0.33, 0.42];
  static const List<double> childEnds = [0.58, 0.71, 0.82];

  /// 涟漪环：内收蓄力 → 白环 → 淡波外散。
  static const double ringShrinkStart = 0.00;
  static const double ringShrinkEnd = 0.18;
  static const double ringWaveStart = 0.18;
  static const double ringWaveEnd = 0.42;

  /// ＋↔× 旋转区间（45°）。
  static const double iconRotateStart = 0.18;
  static const double iconRotateEnd = 0.36;

  /// 母滴空心化（实心滴 → 玻璃环）。
  static const double hollowStart = 0.28;
  static const double hollowEnd = 0.52;

  /// 卫星液滴飞行/淡出。
  static const double satelliteStart = 0.50;
  static const double satelliteEnd = 0.74;
  static const double satelliteFadeStart = 0.66;
  static const double satelliteFadeEnd = 0.80;

  /// 子滴图标淡入（落位后才出现，视频规格）。
  static const double childIconStart = 0.58;
  static const double childIconEnd = 0.80;

  /// 归一化区间映射（@visibleForTesting：时间线语义单测直查）。
  @visibleForTesting
  static double interval(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  /// 三角脉冲（a 起、peak 峰、b 落）：母滴预拉伸用。
  @visibleForTesting
  static double triangle(double t, double a, double peak, double b) {
    if (t <= a || t >= b) return 0;
    return t < peak ? (t - a) / (peak - a) : (b - t) / (b - peak);
  }

  /// 子滴 i 落位目标（条顶坐标系；i: 0=Emby 左上 / 1=声网 正上 / 2=设置 右上）。
  @visibleForTesting
  static Offset childTarget(int i, {required double totalWidth}) {
    final cx = totalWidth / 2;
    final spread = math.min(childSpread, (totalWidth - childSize) / 2 - 4);
    final dx = switch (i) { 0 => -spread, 2 => spread, _ => 0.0 };
    final dy = -childRise - (i == 1 ? centerExtraRise : 0);
    return Offset(cx + dx, motherCenterY + dy);
  }

  /// 卫星液滴飞行终点（条顶坐标系）。
  @visibleForTesting
  static Offset satelliteTarget({required double totalWidth}) =>
      Offset(totalWidth / 2 + 74, motherCenterY - 52);

  /// 凹口胶囊路径（条顶坐标系；cos 谷平滑相切于平顶边，守卫/绘制同源）。
  @visibleForTesting
  static Path notchBarPath({
    required Size size,
    required double dip,
    required double halfWidth,
  }) {
    final cx = size.width / 2;
    final r = size.height / 2;
    final path = Path()..moveTo(r, 0);
    // 顶边：直线 → cos 谷（谷底深 dip，|x-cx|<halfWidth 内平滑下凹）→ 直线
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = cx - halfWidth + (2 * halfWidth) * i / steps;
      final y = dip * (1 + math.cos(math.pi * (x - cx) / halfWidth)) / 2;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width - r, size.height),
          radius: Radius.circular(r), clockwise: true)
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(r, 0),
          radius: Radius.circular(r), clockwise: true)
      ..close();
    return path;
  }

  // ── 测试钥匙（守卫直查）─────────────────────────────────────────

  /// 凹口胶囊（玻璃/磨砂皮肤容器）。
  static const Key barKey = ValueKey('fluidNotchBar');

  /// gooey 液层（母滴/子滴/卫星滴 metaball）。
  static const Key gooKey = ValueKey('fluidGooLayer');

  /// 中央悬浮钮（＋↔×）。
  static const Key centerKey = ValueKey('fluidCenterButton');

  /// 三动作钮命中层（左→右：Emby / 声网 / 设置）。
  static const List<Key> actionKeys = [
    ValueKey('fluidActionEmby'),
    ValueKey('fluidActionVoice'),
    ValueKey('fluidActionSettings'),
  ];

  /// 高光层钥匙（开=fluidSpecular / 关=fluidMatte，双玻璃形态判别）。
  static const Key specularKey = ValueKey('fluidSpecular');
  static const Key matteKey = ValueKey('fluidMatte');

  /// 动作钮 → 壳层分支下标（Emby=2 / 声网=3 / 设置=4，ShellNavBar.tab 组）。
  @visibleForTesting
  static int actionBranch(int i) => 2 + i;

  @override
  ConsumerState<FluidGlassNavBar> createState() => _FluidGlassNavBarState();
}

class _FluidGlassNavBarState extends ConsumerState<FluidGlassNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluidGlassNavBar.expandDuration,
    reverseDuration: FluidGlassNavBar.collapseDuration,
  );

  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // 外部选中动作分支（Emby/声网/设置）→ 自动展开，激活态可见。
    if (widget.currentIndex >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setExpanded(true));
    }
  }

  @override
  void didUpdateWidget(covariant FluidGlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex >= 2 && !_expanded) _setExpanded(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
    if (value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _selectAction(int i) {
    widget.onSelect(FluidGlassNavBar.actionBranch(i));
    _setExpanded(false);
  }

  void _selectTab(int i) {
    widget.onSelect(i);
    _setExpanded(false);
  }

  @override
  Widget build(BuildContext context) {
    final glassOn = ref.watch(settingsProvider.select((s) => s.glassUi));

    return SizedBox(
      // 盒子含飞行区：展开三钮在凹口上方，命中不被 54 高盒子截断；
      // 空白区不命中（hitTestSelf false）→ 手势穿透给正文滚动。
      height: FluidGlassNavBar.flyZone + FluidGlassNavBar.navHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 绘制层：凹口胶囊 + gooey 液体 + 图标（Clip.none 上溢飞行区）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: FluidGlassNavBar.navHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _bar(glassOn, totalWidth),
                      _goo(t, totalWidth, glassOn),
                      IgnorePointer(
                        child: CustomPaint(
                          key: glassOn
                              ? FluidGlassNavBar.specularKey
                              : FluidGlassNavBar.matteKey,
                          size: Size(totalWidth, FluidGlassNavBar.navHeight),
                          painter: _LiquidVisualPainter(
                            t: t,
                            totalWidth: totalWidth,
                            glassOn: glassOn,
                          ),
                        ),
                      ),
                      _lobes(t, totalWidth),
                      _icons(t, totalWidth),
                    ],
                  ),
                ),
                // 命中层：中央钮 + 三动作钮（外层 Stack 直接子级 → 飞行区可点）。
                _centerHit(totalWidth),
                for (var i = 0; i < 3; i++) _actionHit(i, totalWidth),
              ],
            );
          },
        );
      }),
    );
  }

  // ── 凹口胶囊（双玻璃皮肤）────────────────────────────────────────

  Widget _bar(bool glassOn, double totalWidth) {
    final path = FluidGlassNavBar.notchBarPath(
      size: Size(totalWidth, FluidGlassNavBar.navHeight),
      dip: 26,
      halfWidth: 44,
    );
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: FluidGlassNavBar.navHeight,
      child: KeyedSubtree(
        key: FluidGlassNavBar.barKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipPath(
              clipper: _NotchClipper(path),
              child: glassOn
                  ? const GlassContainer(
                      borderRadius: BorderRadius.all(Radius.circular(25)),
                      padding: EdgeInsets.zero,
                      child: SizedBox.expand(),
                    )
                  : const _FrostedBar(),
            ),
            // 凹口缘描边（全路径 1px 白 0.28，玻璃/磨砂同款轮廓）。
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RimPainter(path, glassOn: glassOn),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── gooey 液层（metaball：blur + alpha 阈值，重叠自动粘连/断裂）────

  Widget _goo(double t, double totalWidth, bool glassOn) {
    final cx = totalWidth / 2;
    final mcy = FluidGlassNavBar.motherCenterY;
    final rM = FluidGlassNavBar.motherSize / 2;
    final rC = FluidGlassNavBar.childSize / 2;

    final drops = <Widget>[];

    // 母滴（预拉伸：向左上子滴方向倾斜胶囊；空心化由视觉层环体现）。
    final warp = FluidGlassNavBar.triangle(t, 0.14, 0.22, 0.34);
    final t1 = FluidGlassNavBar.childTarget(0, totalWidth: totalWidth);
    final angle = math.atan2(t1.dy - mcy, t1.dx - cx);
    drops.add(
      Positioned(
        left: cx - rM,
        top: mcy - rM,
        width: rM * 2,
        height: rM * 2,
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scaleX: 1 + 0.45 * warp,
            scaleY: 1 - 0.22 * warp,
            child: Transform.rotate(
              angle: -angle,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 三子滴：弹性甩出 + 飞行中液态拉伸（沿运动方向）。
    for (var i = 0; i < 3; i++) {
      final p = FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.childStarts[i],
        FluidGlassNavBar.childEnds[i],
      );
      if (p <= 0) continue;
      final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
      final eased = Curves.elasticOut.transform(p);
      final pos = Offset.lerp(Offset(cx, mcy), target, eased)!;
      final dir = math.atan2(target.dy - mcy, target.dx - cx);
      final k = math.sin(math.pi * p.clamp(0.0, 1.0)) * 0.30;
      drops.add(
        Positioned(
          left: pos.dx - rC,
          top: pos.dy - rC,
          width: rC * 2,
          height: rC * 2,
          child: Transform.rotate(
            angle: dir,
            child: Transform.scale(
              scaleX: 1 + k,
              scaleY: 1 - 0.6 * k,
              child: Transform.rotate(
                angle: -dir,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 卫星小液滴（飞散 + 淡出，视频液体细节）。
    final sat = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.satelliteStart,
      FluidGlassNavBar.satelliteEnd,
    );
    if (sat > 0 && sat < 1) {
      final fade = 1 -
          FluidGlassNavBar.interval(
            t,
            FluidGlassNavBar.satelliteFadeStart,
            FluidGlassNavBar.satelliteFadeEnd,
          );
      final pos = Offset.lerp(
        Offset(cx + 8, mcy - 8),
        FluidGlassNavBar.satelliteTarget(totalWidth: totalWidth),
        sat,
      )!;
      final rS = FluidGlassNavBar.satelliteRadius * (0.6 + 0.4 * fade);
      drops.add(
        Positioned(
          left: pos.dx - rS,
          top: pos.dy - rS,
          width: rS * 2,
          height: rS * 2,
          child: Opacity(
            opacity: fade,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
    }

    // metaball：blur 软化 alpha + 阈值矩阵硬化 → 重叠粘连、分离断颈。
    return Positioned.fill(
      child: IgnorePointer(
        child: KeyedSubtree(
          key: FluidGlassNavBar.gooKey,
          child: Opacity(
            opacity: glassOn ? 0.92 : 0.82,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                1, 0, 0, 0, 0,
                0, 1, 0, 0, 0,
                0, 0, 1, 0, 0,
                0, 0, 0, 18, -7, // alpha 阈值（gooey 粘连）
              ]),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Stack(clipBehavior: Clip.none, children: drops),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 左右两瓣（首页 / 收藏）───────────────────────────────────────

  Widget _lobes(double t, double totalWidth) {
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(child: _lobeTab(0, selected: widget.currentIndex == 0)),
          SizedBox(width: FluidGlassNavBar.motherSize + 16),
          Expanded(child: _lobeTab(1, selected: widget.currentIndex == 1)),
        ],
      ),
    );
  }

  Widget _lobeTab(int i, {required bool selected}) {
    return TvFocusable(
      onTap: () => _selectTab(i),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectTab(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? ShellNavBar.tabSelectedIcons[i]
                  : ShellNavBar.tabIcons[i],
              size: 22,
              color: selected ? Colors.white : Colors.white70,
            ),
            const SizedBox(height: 2),
            Text(
              ShellNavBar.tabLabels[i],
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.white : Colors.white70,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 图标层（＋/× 旋转 + 子滴图标淡入）───────────────────────────

  Widget _icons(double t, double totalWidth) {
    final rot = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.iconRotateStart,
      FluidGlassNavBar.iconRotateEnd,
    );
    final iconOp = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.childIconStart,
      FluidGlassNavBar.childIconEnd,
    );
    final children = <Widget>[
      // ＋↔×：一枚 + 图标旋转 45° 即 ×（视频同机制）。
      Positioned(
        left: totalWidth / 2 - 14,
        top: FluidGlassNavBar.motherCenterY - 14,
        width: 28,
        height: 28,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: rot * math.pi / 4,
            child: const Icon(Icons.add, size: 28, color: Colors.white),
          ),
        ),
      ),
    ];
    for (var i = 0; i < 3; i++) {
      final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
      children.add(
        Positioned(
          left: target.dx - 13,
          top: target.dy - 13,
          width: 26,
          height: 26,
          child: IgnorePointer(
            child: Opacity(
              opacity: iconOp,
              child: Icon(
                ShellNavBar.tabIcons[FluidGlassNavBar.actionBranch(i)],
                size: 26,
                color: widget.currentIndex ==
                        FluidGlassNavBar.actionBranch(i)
                    ? Colors.white
                    : Colors.white70,
              ),
            ),
          ),
        ),
      );
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  // ── 命中层 ─────────────────────────────────────────────────────

  Widget _centerHit(double totalWidth) {
    return Positioned(
      left: totalWidth / 2 - 30,
      top: FluidGlassNavBar.flyZone + FluidGlassNavBar.motherCenterY - 30,
      width: 60,
      height: 60,
      child: TvFocusable(
        onTap: () => _setExpanded(!_expanded),
        child: GestureDetector(
          key: FluidGlassNavBar.centerKey,
          behavior: HitTestBehavior.opaque,
          onTap: () => _setExpanded(!_expanded),
        ),
      ),
    );
  }

  Widget _actionHit(int i, double totalWidth) {
    final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
    final visible = _controller.value >
        (FluidGlassNavBar.childStarts[i] + FluidGlassNavBar.childEnds[i]) / 2;
    return Positioned(
      left: target.dx - FluidGlassNavBar.childSize / 2,
      top: FluidGlassNavBar.flyZone + target.dy -
          FluidGlassNavBar.childSize / 2,
      width: FluidGlassNavBar.childSize,
      height: FluidGlassNavBar.childSize,
      child: IgnorePointer(
        ignoring: !visible || !_expanded,
        child: TvFocusable(
          onTap: () => _selectAction(i),
          child: GestureDetector(
            key: FluidGlassNavBar.actionKeys[i],
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectAction(i),
          ),
        ),
      ),
    );
  }
}

/// 凹口胶囊裁剪（[FluidGlassNavBar.notchBarPath] 同源路径）。
class _NotchClipper extends CustomClipper<Path> {
  const _NotchClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_NotchClipper oldClipper) => oldClipper.path != path;
}

/// 凹口缘描边（玻璃/磨砂同轮廓；玻璃态微亮）。
class _RimPainter extends CustomPainter {
  const _RimPainter(this.path, {required this.glassOn});

  final Path path;
  final bool glassOn;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: glassOn ? 0.32 : 0.28),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.glassOn != glassOn;
}

/// 轻量磨砂胶囊皮肤（「液态玻璃」关：模糊 + 半透明，零折射计算）。
class _FrostedBar extends StatelessWidget {
  const _FrostedBar();

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: ColoredBox(
        color: Colors.white.withValues(alpha: 0.10),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 液滴视觉层：涟漪环（内收蓄力 + 淡波外散）+ 液滴高光/光晕（玻璃态）。
class _LiquidVisualPainter extends CustomPainter {
  const _LiquidVisualPainter({
    required this.t,
    required this.totalWidth,
    required this.glassOn,
  });

  final double t;
  final double totalWidth;
  final bool glassOn;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = totalWidth / 2;
    final mcy = FluidGlassNavBar.motherCenterY;
    final rM = FluidGlassNavBar.motherSize / 2;

    // 涟漪环：内收蓄力（1.9R → 1.02R，越收越亮）。
    final shrink = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.ringShrinkStart,
      FluidGlassNavBar.ringShrinkEnd,
    );
    final shrinkFade =
        1 - FluidGlassNavBar.interval(t, 0.18, 0.30);
    if (shrink > 0 && shrinkFade > 0) {
      final radius = rM * (1.9 - 0.88 * Curves.easeOut.transform(shrink));
      canvas.drawCircle(
        Offset(cx, mcy),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + 2.0 * shrink
          ..color = Colors.white.withValues(alpha: 0.55 * shrinkFade + 0.35 * shrink * shrinkFade),
      );
    }
    // 淡波外散。
    final wave = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.ringWaveStart,
      FluidGlassNavBar.ringWaveEnd,
    );
    if (wave > 0 && wave < 1) {
      canvas.drawCircle(
        Offset(cx, mcy),
        rM * (1.05 + 0.7 * wave),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.35 * (1 - wave)),
      );
    }

    // 母滴高光/光晕（玻璃态；磨砂态仅淡光晕）。
    _dropGlow(canvas, Offset(cx, mcy), rM, glassOn ? 1 : 0.5);
    for (var i = 0; i < 3; i++) {
      final p = FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.childStarts[i],
        FluidGlassNavBar.childEnds[i],
      );
      if (p <= 0) continue;
      final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
      final eased = Curves.elasticOut.transform(p);
      final pos = Offset.lerp(Offset(cx, mcy), target, eased)!;
      _dropGlow(canvas, pos, FluidGlassNavBar.childSize / 2, glassOn ? 1 : 0.5);
    }
    // 卫星液滴微光。
    final sat = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.satelliteStart,
      FluidGlassNavBar.satelliteEnd,
    );
    if (sat > 0 && sat < 1) {
      final pos = Offset.lerp(
        Offset(cx + 8, mcy - 8),
        FluidGlassNavBar.satelliteTarget(totalWidth: totalWidth),
        sat,
      )!;
      _dropGlow(canvas, pos, FluidGlassNavBar.satelliteRadius, 0.6);
    }
  }

  void _dropGlow(Canvas canvas, Offset c, double r, double strength) {
    // 外圈柔光。
    canvas.drawCircle(
      c,
      r + 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withValues(alpha: 0.10 * strength),
    );
    if (strength >= 1) {
      // 玻璃态高光弧（左上月牙）。
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.72),
        math.pi * 0.85,
        math.pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }
  }

  @override
  bool shouldRepaint(_LiquidVisualPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.totalWidth != totalWidth ||
      oldDelegate.glassOn != glassOn;
}
