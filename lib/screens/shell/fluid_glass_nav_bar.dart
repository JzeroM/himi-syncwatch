import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 流体液态导航（698 N17-N21，样式注册表第②款）：Dribbble「Bottom
/// Navigation Micro Interaction」**整条 1:1 复刻**（用户拍板 N21：
/// 形状/配色/材质/动效全照搬视频，仅图标用我们自己的；颜色风格后续再调）。
///
/// **N21 复刻色板（视频帧实测取色）**：
/// - 液滴 = 实心粉渐变（核心 RGB 233,114,197、底缘 240,107,208），
///   顶左 `dropPinkLight` → 底右 `dropPinkDeep`，完全不透明；
/// - 条体 = 磨砂半透明白 30%（视频 146,131,189 ≈ 白 30% 叠底观感）；
/// - 环 = 细白环（常驻细环 + 400ms 点击涟漪，视频 f18-f25）。
///
/// **N21 不再有自定义玻璃感**：此款式与「液态玻璃」开关解耦（用户
/// 拍板：先实现一样效果，后面再调整颜色/风格）。
///
/// **拉丝 = blur + 硬阈值**（jurajkusnier/fluid-bottom-navigation
/// 源码 1:1：`BlurEffect + ColorMatrix(0,0,0,50,-5000)`）。N21 根因
/// 修复：Flutter [ColorFilter.matrix] 偏移列是 **0..255 制**，此前
/// 按 0..1 制写 -19.6 → 实际阈值 0.0015 → 整个模糊场全过阈值
/// （真机「巨型白圈/奶雾」）；现 jurajkusnier 原值直用（阈值 0.392、
/// 过渡带 0.02 极硬边）+ σ15 校准（静止互不粘连、近触才厚颈拉丝）
/// + 绘制半径补偿（轮廓落在视觉尺寸）。
///
/// **三滴常驻分裂（jurajkusnier 机制）**：三颗子滴一直存在，收起叠
/// 母滴位置被 blur 融成「一滴」；展开 = 这颗滴裂开飞散（区间错峰
/// 0/0.1/0.2 → 0.8/0.9/1.0，FastOutSlowIn，左→中→右）。
///
/// 其余机制：＋ 旋转 225°（≡45° 视觉成 × 带拧劲）；中央空滴展开
/// 缩没（0.5-0.85）→ 展开态中央只剩 ×+细环（视频 f45）；图标随滴
/// 飞、透明度线性错峰渐显（0.2/0.3/0.4 → 0.7/0.8/0.9）；卫星小液滴
/// （视频 f39）。条形 = 透镜叶形（顶缘八字拱/底缘微下拱）+ 凹口弧与
/// 母滴同心恒距 4dp（视频像素实测）。
class FluidGlassNavBar extends StatefulWidget {
  const FluidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  // ── 复刻色板（视频实测取色，698 N21，守卫直查）──────────────────

  /// 液滴粉渐变顶左亮色（≈ RGB 245,184,227）。
  static const Color dropPinkLight = Color(0xFFF5B8E3);

  /// 液滴粉渐变底右深色（≈ RGB 226,94,190）。
  static const Color dropPinkDeep = Color(0xFFE25EBE);

  /// 条体磨砂白叠色（视频条体 146,131,189 ≈ 白 30% 叠底）。
  static const double barFrostAlpha = 0.30;

  // ── 几何常量（视频像素实测，守卫直查）───────────────────────────

  /// 导航条高（两端厚度；中央因底拱略厚）。
  static const double navHeight = ShellNavBar.navHeight;

  /// 凹口上方飞行区高（展开三钮/命中区；盒子高 = navHeight + flyZone）。
  static const double flyZone = 96;

  /// 中央滴直径（收起态 = 三子滴融合体的视觉直径；展开态 = 细环直径）。
  static const double motherSize = 38;

  /// 子滴直径（展开落位，≈母滴 1.37×，视频实测 74/54）。
  static const double childSize = 52;

  /// 子滴/母滴直径比（守卫：≈1.37 档）。
  static const double childScaleRatio = childSize / motherSize;

  /// 母滴圆心 y（条顶坐标系；中央滴悬浮出条顶 ~7dp）。
  static const double motherCenterY = 12;

  /// 凹口弧与母滴的恒定间距（同心 R+gap，处处等距）。
  static const double notchGap = 4;

  /// 凹口弧半径 = 母滴 R + [notchGap]（与母滴严格同心，守卫恒距）。
  static const double notchRadius = motherSize / 2 + notchGap;

  /// 顶缘八字拱高（中央峰 → 两端缓落，视频 6px/80 厚等比 ≈ 4dp）。
  static const double topArch = 4;

  /// 底缘下拱高（中央微垂，视频 5px/80 等比 ≈ 3.5dp）。
  static const double botArch = 3.5;

  /// 子滴圆心高于母滴圆心的量。
  static const double childRise = 63;

  /// 中心子滴额外上浮（视频中心滴略高）。
  static const double centerExtraRise = 11;

  /// 子滴横向间距（±）。
  static const double childSpread = 92;

  /// 卫星小液滴半径（视频 f39 细节）。
  static const double satelliteRadius = 5;

  // ── 液桥参数（jurajkusnier 1:1，守卫直查）────────────────────────

  /// metaball blur σ（σ/子滴视觉半径 ≈0.58；静止互不粘连、近触厚颈）。
  static const double gooBlurSigma = 15;

  /// 阈值矩阵 alpha 行 = jurajkusnier Android 原值 `0,0,0,50,-5000`
  /// **原样直用**（[ColorFilter.matrix] 偏移列 0..255 制；阈值 0.392、
  /// 过渡带 0.02 极硬边）。N21 根因：此前误按 0..1 制写 -19.6，
  /// 实际阈值 0.0015 → 整个模糊场全过阈值（巨型白圈/奶雾）。
  static const List<double> gooAlphaRow = [0, 0, 0, 50, -5000];

  /// goo 绘制半径补偿：阈值切回视觉尺寸
  /// （blur 后等照度轮廓 r' = √(R²-0.988σ²) ⇒ R = √(r²+0.988σ²)）。
  @visibleForTesting
  static double gooRadius(double visualR) =>
      math.sqrt(visualR * visualR + 0.988 * gooBlurSigma * gooBlurSigma);

  // ── 动效时间线（归一化 t∈[0,1]，jurajkusnier 区间 + 视频时长）────

  /// 展开 1150ms；收回 850ms。
  static const Duration expandDuration = Duration(milliseconds: 1150);
  static const Duration collapseDuration = Duration(milliseconds: 850);

  /// 点击涟漪时长（jurajkusnier 400ms，sin 脉冲）。
  static const Duration clickDuration = Duration(milliseconds: 400);

  /// 三子滴飞行区间（jurajkusnier 错峰：0/0.1/0.2 → 0.8/0.9/1.0，
  /// 左→中→右；**起点 <1 → 收起时三滴常驻叠母滴融合**）。
  static const List<double> splitStarts = [0.0, 0.1, 0.2];
  static const List<double> splitEnds = [0.8, 0.9, 1.0];

  /// 中央「空滴」缩没区间（jurajkusnier 0.5-0.85）。
  static const double shrinkStart = 0.5;
  static const double shrinkEnd = 0.85;

  /// ＋ 旋转 225° 区间（jurajkusnier 0.35-0.65；225°≡45° 视觉成 ×）。
  static const double iconRotateStart = 0.35;
  static const double iconRotateEnd = 0.65;
  static const double iconRotateDegrees = 225;

  /// 子滴图标渐显区间（jurajkusnier 错峰 0.2/0.3/0.4 → 0.7/0.8/0.9）。
  static const List<double> iconFadeStarts = [0.2, 0.3, 0.4];
  static const List<double> iconFadeEnds = [0.7, 0.8, 0.9];

  /// 卫星液滴飞行/淡出（视频 f39 细节）。
  static const double satelliteStart = 0.55;
  static const double satelliteEnd = 0.78;
  static const double satelliteFadeStart = 0.70;
  static const double satelliteFadeEnd = 0.84;

  /// 归一化区间映射（@visibleForTesting：时间线语义单测直查）。
  @visibleForTesting
  static double interval(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

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

  /// 母滴圆心（条顶坐标系）。
  @visibleForTesting
  static Offset motherCenter({required double totalWidth}) =>
      Offset(totalWidth / 2, motherCenterY);

  /// 凹口胶囊路径（条顶坐标系）：**透镜叶形**——顶缘八字拱（二次贝塞尔
  /// 中央峰）、底缘微下拱（二次贝塞尔中央垂）、两端半圆帽、中央
  /// **与母滴同心的凹口弧**（[notchRadius]，恒距 [notchGap]，从母滴
  /// 水平中心线绕底包裹下半圆；肩部 8dp S 弯相切顺入顶缘）。
  ///
  /// 左右严格镜像（右段 = 左段反向参数化），「八字」对称。
  @visibleForTesting
  static Path notchBarPath({required Size size}) {
    final cx = size.width / 2;
    const mcy = motherCenterY;
    const nr = notchRadius;
    final endTopY = topArch;
    final endBotY = size.height;
    final endR = (endBotY - endTopY) / 2;
    final leftEndX = endR;
    final rightEndX = size.width - endR;
    final notchRect = Rect.fromCircle(
      center: Offset(cx, mcy),
      radius: nr,
    );

    final path = Path()..moveTo(leftEndX, endTopY);
    // 顶缘左段：八字拱（端部 endTopY → 中段峰 ≈0 → 肩部 2）。
    path.quadraticBezierTo(cx - 60, -3, cx - nr - 8, 2);
    // 左肩 S 弯：水平切出 → 竖直切入凹口弧起点（与弧相切）。
    path.cubicTo(
      cx - nr, 2,
      cx - nr, mcy - 7,
      cx - nr, mcy,
    );
    // 凹口弧：与母滴同心（R+gap 恒距），绕底包裹下半圆
    //（π → 0 经 π/2 底部，sweep -π）。
    path.arcTo(notchRect, math.pi, -math.pi, false);
    // 右肩 S 弯（左段镜像反向）。
    path.cubicTo(
      cx + nr, mcy - 7,
      cx + nr, 2,
      cx + nr + 8, 2,
    );
    // 顶缘右段（左段镜像反向）。
    path.quadraticBezierTo(cx + 60, -3, rightEndX, endTopY);
    // 右端半圆帽（顶 → 右 → 底）。
    path.arcTo(
      Rect.fromCircle(
        center: Offset(rightEndX, (endTopY + endBotY) / 2),
        radius: endR,
      ),
      -math.pi / 2,
      math.pi,
      false,
    );
    // 底缘：微向下拱（中央垂 botArch）。
    path.quadraticBezierTo(cx, endBotY + 2 * botArch, leftEndX, endBotY);
    // 左端半圆帽（底 → 左 → 顶），闭合。
    path.arcTo(
      Rect.fromCircle(
        center: Offset(leftEndX, (endTopY + endBotY) / 2),
        radius: endR,
      ),
      math.pi / 2,
      math.pi,
      false,
    );
    path.close();
    return path;
  }

  // ── 测试钥匙（守卫直查）─────────────────────────────────────────

  /// 凹口胶囊（磨砂皮肤容器）。
  static const Key barKey = ValueKey('fluidNotchBar');

  /// gooey 液层（单层：jurajkusnier 链 = blur + 阈值）。
  static const Key gooKey = ValueKey('fluidGooLayer');

  /// 液滴逐滴钥匙（goo 层）。
  static const Key dropMotherKey = ValueKey('fluidDropMother');
  static const List<Key> dropChildKeys = [
    ValueKey('fluidDropChild0'),
    ValueKey('fluidDropChild1'),
    ValueKey('fluidDropChild2'),
  ];
  static const Key dropSatKey = ValueKey('fluidDropSat');

  /// 中央悬浮钮（＋↔×）。
  static const Key centerKey = ValueKey('fluidCenterButton');

  /// 三动作钮命中层（左→右：Emby / 声网 / 设置）。
  static const List<Key> actionKeys = [
    ValueKey('fluidActionEmby'),
    ValueKey('fluidActionVoice'),
    ValueKey('fluidActionSettings'),
  ];

  /// 动作钮 → 壳层分支下标（Emby=2 / 声网=3 / 设置=4，ShellNavBar.tab 组）。
  @visibleForTesting
  static int actionBranch(int i) => 2 + i;

  @override
  State<FluidGlassNavBar> createState() => _FluidGlassNavBarState();
}

/// 单个液滴的动画状态（goo 层与视觉层同源，几何只算一次）。
class _DropState {
  const _DropState({
    required this.key,
    required this.center,
    required this.radius,
    this.opacity = 1,
  });

  final Key key;
  final Offset center;

  /// 视觉半径（goo 层用 [FluidGlassNavBar.gooRadius] 补偿绘制）。
  final double radius;

  final double opacity;
}

/// 液滴几何（纯函数：goo 层与视觉层同源，jurajkusnier 机制）。
///
/// 三滴常驻：收起叠母滴融合成一滴、展开错峰裂开（区间 + FastOutSlowIn，
/// 无过冲无拉伸——液桥形变全交给 blur+阈值滤镜，源码同款）。
List<_DropState> _computeDrops(double t, double totalWidth) {
  final m = FluidGlassNavBar.motherCenter(totalWidth: totalWidth);
  final rM = FluidGlassNavBar.motherSize / 2;
  final rC = FluidGlassNavBar.childSize / 2;
  final out = <_DropState>[];

  // 中央「空滴」：展开缩没（jurajkusnier scale 1-Linear(0.5,0.85,p)）。
  final shrink = 1 -
      FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.shrinkStart,
        FluidGlassNavBar.shrinkEnd,
      );
  if (shrink > 0.02) {
    out.add(_DropState(
      key: FluidGlassNavBar.dropMotherKey,
      center: m,
      radius: rM * shrink,
    ));
  }

  // 三子滴常驻：位置 = 母滴→目标 × FastOutSlowIn(区间)；直径恒定。
  for (var i = 0; i < 3; i++) {
    final p = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.splitStarts[i],
      FluidGlassNavBar.splitEnds[i],
    );
    final e = Curves.fastOutSlowIn.transform(p);
    final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
    out.add(_DropState(
      key: FluidGlassNavBar.dropChildKeys[i],
      center: Offset.lerp(m, target, e)!,
      radius: rC,
    ));
  }

  // 卫星小液滴（飞散 + 淡出，视频 f39 细节）。
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
      m + const Offset(8, -8),
      FluidGlassNavBar.satelliteTarget(totalWidth: totalWidth),
      sat,
    )!;
    out.add(_DropState(
      key: FluidGlassNavBar.dropSatKey,
      center: pos,
      radius: FluidGlassNavBar.satelliteRadius * (0.6 + 0.4 * fade),
      opacity: fade.clamp(0.0, 1.0),
    ));
  }
  return out;
}

class _FluidGlassNavBarState extends State<FluidGlassNavBar>
    with TickerProviderStateMixin {
  /// 主时序（展开/收起，reverse 即反序吸收）。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluidGlassNavBar.expandDuration,
    reverseDuration: FluidGlassNavBar.collapseDuration,
  );

  /// 点击涟漪（jurajkusnier 400ms sin 脉冲：scale 2→1→2、alpha 0→1→0）。
  late final AnimationController _click = AnimationController(
    vsync: this,
    duration: FluidGlassNavBar.clickDuration,
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
    _click.dispose();
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
    _click.forward(from: 0); // 点击涟漪（环脉冲，视频 f18-f25）
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
    return SizedBox(
      // 盒子含飞行区：展开三钮在凹口上方，命中不被 54 高盒子截断；
      // 空白区不命中（hitTestSelf false）→ 手势穿透给正文滚动。
      height: FluidGlassNavBar.flyZone + FluidGlassNavBar.navHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: Listenable.merge([_controller, _click]),
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // 绘制层：磨砂条 + gooey 液体 + 环 + 图标（Clip.none 上溢）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: FluidGlassNavBar.navHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _bar(totalWidth),
                      _gooLayer(t, totalWidth),
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size(totalWidth, FluidGlassNavBar.navHeight),
                          painter: _RingPainter(
                            t: t,
                            clickT: _click.value,
                            totalWidth: totalWidth,
                          ),
                        ),
                      ),
                      _lobes(totalWidth),
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

  // ── 磨砂条（视频 146,131,189 ≈ 白 30% 叠底；叶形 + 同心凹口）─────

  Widget _bar(double totalWidth) {
    final path = FluidGlassNavBar.notchBarPath(
      size: Size(totalWidth, FluidGlassNavBar.navHeight),
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
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: ColoredBox(
                  color: Colors.white.withValues(
                      alpha: FluidGlassNavBar.barFrostAlpha),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // 叶形缘描边（视频条体亮边）。
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RimPainter(path),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── gooey 液层（jurajkusnier 链：blur + 硬阈值，粉渐变实心滴）────

  Widget _gooLayer(double t, double totalWidth) {
    final drops = _computeDrops(t, totalWidth);
    final children = <Widget>[
      for (final d in drops)
        Positioned(
          left: d.center.dx - FluidGlassNavBar.gooRadius(d.radius),
          top: d.center.dy - FluidGlassNavBar.gooRadius(d.radius),
          width: FluidGlassNavBar.gooRadius(d.radius) * 2,
          height: FluidGlassNavBar.gooRadius(d.radius) * 2,
          child: DecoratedBox(
            key: d.key,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.45, -0.5),
                colors: d.opacity >= 1
                    ? const [
                        FluidGlassNavBar.dropPinkLight,
                        FluidGlassNavBar.dropPinkDeep,
                      ]
                    : [
                        FluidGlassNavBar.dropPinkLight
                            .withValues(alpha: d.opacity),
                        FluidGlassNavBar.dropPinkDeep
                            .withValues(alpha: d.opacity),
                      ],
              ),
            ),
          ),
        ),
    ];

    // metaball：blur 软化 alpha + 阈值矩阵硬化 → 重叠粘连、分离断颈。
    // 阈值行 = jurajkusnier Android 原值 0,0,0,50,-5000（0..255 制）。
    return Positioned.fill(
      child: IgnorePointer(
        child: KeyedSubtree(
          key: FluidGlassNavBar.gooKey,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix([
              1, 0, 0, 0, 0,
              0, 1, 0, 0, 0,
              0, 0, 1, 0, 0,
              ...FluidGlassNavBar.gooAlphaRow,
            ]),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: FluidGlassNavBar.gooBlurSigma,
                sigmaY: FluidGlassNavBar.gooBlurSigma,
              ),
              child: Stack(clipBehavior: Clip.none, children: children),
            ),
          ),
        ),
      ),
    );
  }

  // ── 左右两瓣（首页 / 收藏，图标用我们自己的）───────────────────────

  Widget _lobes(double totalWidth) {
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

  // ── 图标层（jurajkusnier 双层语义：液体 gooey、图标清晰随滴飞）────

  static const List<Shadow> _iconShadows = [
    Shadow(color: Color(0x59000000), blurRadius: 4),
  ];

  Widget _icons(double t, double totalWidth) {
    // ＋↔×：旋转 225°（≡45° 视觉成 ×，225 带「拧」劲）。
    final rot = Curves.fastOutSlowIn.transform(
      FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.iconRotateStart,
        FluidGlassNavBar.iconRotateEnd,
      ),
    );
    final m = FluidGlassNavBar.motherCenter(totalWidth: totalWidth);
    final children = <Widget>[
      Positioned(
        left: m.dx - 12,
        top: m.dy - 12,
        width: 24,
        height: 24,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: rot *
                FluidGlassNavBar.iconRotateDegrees *
                math.pi /
                180,
            child: const Icon(Icons.add,
                size: 24, color: Colors.white, shadows: _iconShadows),
          ),
        ),
      ),
    ];
    // 子滴图标（我们的 tabIcons）：随滴位置飞、透明度线性错峰渐显。
    for (var i = 0; i < 3; i++) {
      final p = FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.splitStarts[i],
        FluidGlassNavBar.splitEnds[i],
      );
      final e = Curves.fastOutSlowIn.transform(p);
      final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
      final pos = Offset.lerp(m, target, e)!;
      final opacity = FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.iconFadeStarts[i],
        FluidGlassNavBar.iconFadeEnds[i],
      );
      children.add(
        Positioned(
          left: pos.dx - 12,
          top: pos.dy - 12,
          width: 24,
          height: 24,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Icon(
                ShellNavBar.tabIcons[FluidGlassNavBar.actionBranch(i)],
                size: 24,
                color:
                    widget.currentIndex == FluidGlassNavBar.actionBranch(i)
                        ? Colors.white
                        : Colors.white70,
                shadows: _iconShadows,
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
        (FluidGlassNavBar.splitStarts[i] + FluidGlassNavBar.splitEnds[i]) / 2;
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

/// 叶形缘描边（视频条体亮边）。
class _RimPainter extends CustomPainter {
  const _RimPainter(this.path);

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) => oldDelegate.path != path;
}

/// 环视觉层：常驻细环 + 点击涟漪环（jurajkusnier Circle 机制，视频 f18-f25）。
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.t,
    required this.clickT,
    required this.totalWidth,
  });

  final double t;
  final double clickT;
  final double totalWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final m = FluidGlassNavBar.motherCenter(totalWidth: totalWidth);
    final rM = FluidGlassNavBar.motherSize / 2;

    // 常驻细环（jurajkusnier Circle(primary α0.5, 0.5)：Ø=母滴）。
    canvas.drawCircle(
      m,
      rM,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    // 点击涟漪环（400ms sin 脉冲：scale 2→1→2、alpha 0→1→0）。
    if (clickT > 0 && clickT < 1) {
      final s = math.sin(math.pi * clickT);
      canvas.drawCircle(
        m,
        rM * (2 - s),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.55 * s),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.clickT != clickT ||
      oldDelegate.totalWidth != totalWidth;
}
