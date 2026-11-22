import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 流体液态导航（698 N17/N18，样式注册表第②款）：Dribbble「Bottom
/// Navigation Micro Interaction」同款**悬浮凹口 + 水滴分裂**动效——
/// 用户上传视频逐帧 1:1 分解复刻 + N18 真机反馈修正。
///
/// **N18 修正（真机两轮反馈）**：
/// - 液滴改**玻璃白**（半透明 + rim + 高光月牙 + 底部内影，非实心白块）；
/// - 比例缩小（母滴 Ø38 / 子滴 Ø52，比值 ≈1.37 与视频一致）；
/// - 条形 = **透镜叶形轮廓**：顶缘八字拱（中央高、两端缓落）+
///   底缘微下拱（中央厚 ~7dp）；**凹口弧与母滴严格同心**（R+4dp 恒距），
///   正好包裹母滴下半部分；
/// - **高级拉丝（premium filament）**：双层 metaball（core+halo 光晕）、
///   动态 whisker 细丝（16→2.5dp 指数收细，行程 75% 才 pinch-off）、
///   体积守恒收腰、断丝回弹 + 微液滴、收回探丝（reverse 自然
///   tendril-first）、高光沿丝、玻璃液滴；
/// - 放慢灵动：展开 1150ms / 收回 850ms / 错峰 ~120ms、easeOutBack
///   单次过冲、子滴从母滴「长出」（起步 scale 0.4→1）、落位微弹。
///
/// **动效骨架（视频逐帧规格）**：涟漪环内收蓄力 → 母滴预拉伸 →
/// gooey 拉丝分裂（左上 Emby → 正上声网 → 右上设置 错峰）→ ＋旋 45°
/// 成 × → 卫星小液滴飞散 → 图标落位后淡入 → 收回反序吸收（右→中→左）。
///
/// **双玻璃形态（N5-G）**：开 = 液态玻璃（折射胶囊 + 液体 α0.32 +
/// halo 光晕 + 高光月牙）；关 = 轻量磨砂（模糊胶囊 + 液体 α0.48）。
/// 纯玻璃白零彩色。
class FluidGlassNavBar extends ConsumerStatefulWidget {
  const FluidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  // ── 几何常量（698 N17/N18，守卫测试直查）─────────────────────────

  /// 导航条高（两端厚度；中央因底拱略厚）。
  static const double navHeight = ShellNavBar.navHeight;

  /// 凹口上方飞行区高（展开三钮/命中区；盒子高 = navHeight + flyZone）。
  static const double flyZone = 96;

  /// 母滴直径（悬浮玻璃圆钮，N18 缩比 46→38）。
  static const double motherSize = 38;

  /// 子滴直径（N18 缩比 62→52；比值 ≈1.37 与视频实测一致）。
  static const double childSize = 52;

  /// 子滴/母滴直径比（守卫：≈1.37 档）。
  static const double childScaleRatio = childSize / motherSize;

  /// 母滴圆心 y（条顶坐标系；母滴悬浮出条顶 ~7dp）。
  static const double motherCenterY = 12;

  /// 凹口弧与母滴的恒定间距（同心 R+gap，处处等距）。
  static const double notchGap = 4;

  /// 凹口弧半径 = 母滴 R + [notchGap]（与母滴严格同心，守卫恒距）。
  static const double notchRadius = motherSize / 2 + notchGap;

  /// 顶缘八字拱高（中央峰 → 两端缓落，视频 6px/80 厚等比 ≈ 4dp）。
  static const double topArch = 4;

  /// 底缘下拱高（中央微垂，视频 5px/80 等比 ≈ 3.5dp）。
  static const double botArch = 3.5;

  /// 子滴圆心高于母滴圆心的量（视频 1.65×Ø 等比）。
  static const double childRise = 63;

  /// 中心子滴额外上浮（视频 0.28×Ø 等比）。
  static const double centerExtraRise = 11;

  /// 子滴横向间距（±；N18 收紧 108→92，滴间净距 ≈0.77×Ø 与视频同档）。
  static const double childSpread = 92;

  /// 卫星小液滴半径（视频细节）。
  static const double satelliteRadius = 5;

  // ── 动效时间线（归一化 t∈[0,1]，守卫测试直查）───────────────────

  /// 展开 1150ms（N18 放慢：900→1150）；收回 850ms（700→850）。
  static const Duration expandDuration = Duration(milliseconds: 1150);
  static const Duration collapseDuration = Duration(milliseconds: 850);

  /// 三子滴飞行区间（错峰 ≈120ms，左→中→右）。
  static const List<double> childStarts = [0.18, 0.285, 0.39];
  static const List<double> childEnds = [0.62, 0.725, 0.83];

  /// 涟漪环：内收蓄力 → 白环 → 淡波外散。
  static const double ringShrinkStart = 0.00;
  static const double ringShrinkEnd = 0.16;
  static const double ringWaveStart = 0.16;
  static const double ringWaveEnd = 0.38;

  /// ＋↔× 旋转区间（45°）。
  static const double iconRotateStart = 0.15;
  static const double iconRotateEnd = 0.33;

  /// 母滴空心化（实心滴 → 玻璃环，展开态视频同款）。
  static const double hollowStart = 0.26;
  static const double hollowEnd = 0.50;

  /// 卫星液滴飞行/淡出。
  static const double satelliteStart = 0.55;
  static const double satelliteEnd = 0.78;
  static const double satelliteFadeStart = 0.70;
  static const double satelliteFadeEnd = 0.84;

  /// 子滴图标淡入（落位后才出现，视频规格）。
  static const double childIconStart = 0.60;
  static const double childIconEnd = 0.82;

  // ── 拉丝参数（698 N18 高级拉丝，守卫直查）───────────────────────

  /// whisker 细丝 pinch-off 行程位（75% 行程才断，晚于 metaball 断距）。
  static const double wirePinch = 0.75;

  /// 细丝根部宽（dp，起飞时）。
  static const double wireWidthRoot = 16;

  /// 细丝断口宽（dp，pinch 前发丝级）。
  static const double wireWidthTip = 2.5;

  /// 细丝宽度（行程 p 单调指数收细：16 → 2.5dp；p≥wirePinch 无丝）。
  @visibleForTesting
  static double wireWidth(double p) {
    if (p <= 0 || p >= wirePinch) return 0;
    final k = p / wirePinch;
    return wireWidthRoot *
        math.pow(wireWidthTip / wireWidthRoot, k).toDouble();
  }

  /// 液体透明度档（折射 0.32 / 磨砂 0.48，守卫：玻璃透感非实心白）。
  @visibleForTesting
  static double liquidOpacity(bool glassOn) => glassOn ? 0.32 : 0.48;

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

  /// 凹口胶囊（玻璃/磨砂皮肤容器）。
  static const Key barKey = ValueKey('fluidNotchBar');

  /// gooey 液层 core（实体）/ halo（边缘光晕，双层 metaball）。
  static const Key gooKey = ValueKey('fluidGooLayer');
  static const Key gooHaloKey = ValueKey('fluidGooHalo');

  /// 液滴/细丝逐滴钥匙（core 层）。
  static const Key dropMotherKey = ValueKey('fluidDropMother');
  static const List<Key> dropChildKeys = [
    ValueKey('fluidDropChild0'),
    ValueKey('fluidDropChild1'),
    ValueKey('fluidDropChild2'),
  ];
  static const Key dropSatKey = ValueKey('fluidDropSat');
  static const List<Key> wireKeys = [
    ValueKey('fluidWire0'),
    ValueKey('fluidWire1'),
    ValueKey('fluidWire2'),
  ];

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

/// 单个液滴/细丝的动画状态（goo 层与视觉层同源，几何只算一次）。
class _DropState {
  const _DropState({
    required this.key,
    required this.center,
    required this.radius,
    this.angle = 0,
    this.stretchK = 0,
    this.opacity = 1,
    this.wireLen = 0,
  });

  final Key key;
  final Offset center;

  /// 圆滴半径；细丝为胶囊半宽（长度另见 [wireLen]）。
  final double radius;

  /// 拉伸轴角（液态拉伸/细丝方向）。
  final double angle;

  /// 体积守恒拉伸量（沿轴 1+k / 垂轴 1-0.6k）。
  final double stretchK;

  final double opacity;

  /// 细丝长度（>0 即细丝胶囊）。
  final double wireLen;

  bool get isWire => wireLen > 0;
}

/// 液滴/细丝几何（纯函数：goo 层与视觉层同源，698 N18）。
///
/// 拉丝七技法：长出三拍（grow）/ 体积守恒收腰（stretchK）/ whisker 细丝
/// （wireWidth 指数收细 + 75% pinch-off）/ 断丝回弹（bump）/ 断点微液滴 /
/// 收回探丝（reverse 时细丝先现后粗，tendril-first）/ 落位微弹。
List<_DropState> _computeDrops(double t, double totalWidth) {
  final m = FluidGlassNavBar.motherCenter(totalWidth: totalWidth);
  final rM = FluidGlassNavBar.motherSize / 2;
  final rC = FluidGlassNavBar.childSize / 2;
  final out = <_DropState>[];

  double progressOf(int i) => FluidGlassNavBar.interval(
        t,
        FluidGlassNavBar.childStarts[i],
        FluidGlassNavBar.childEnds[i],
      );

  // 断丝回弹（pinch 窗口 15% 行程内的表面张力微弹）。
  double bumpOf(double p) => 0.04 *
      math.sin(
          math.pi * ((p - FluidGlassNavBar.wirePinch) / 0.15).clamp(0.0, 1.0));

  // 母滴（预拉伸 + 断丝回弹 + 空心化透明度）。
  final warp = FluidGlassNavBar.triangle(t, 0.12, 0.20, 0.32);
  final t1 = FluidGlassNavBar.childTarget(0, totalWidth: totalWidth);
  final wAngle = math.atan2(t1.dy - m.dy, t1.dx - m.dx);
  final hollow = FluidGlassNavBar.interval(
    t,
    FluidGlassNavBar.hollowStart,
    FluidGlassNavBar.hollowEnd,
  );
  out.add(_DropState(
    key: FluidGlassNavBar.dropMotherKey,
    center: m,
    radius: rM * (1 + bumpOf(progressOf(0))),
    angle: wAngle,
    stretchK: 0.45 * warp,
    opacity: 1 - 0.85 * hollow,
  ));

  for (var i = 0; i < 3; i++) {
    final p = progressOf(i);
    if (p <= 0) continue;
    final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
    final eased = Curves.easeOutBack.transform(p.clamp(0.0, 1.0));
    final pos = Offset.lerp(m, target, eased.clamp(0.0, 1.15))!;
    final dir = math.atan2(target.dy - m.dy, target.dx - m.dx);
    // 长出三拍：起飞前 30% 行程内 0.4→1（从母滴「长出」）。
    final grow =
        0.4 + 0.6 * Curves.easeOut.transform((p / 0.3).clamp(0.0, 1.0));
    // 落位微弹（末段 15% 行程 1→1.05→1）。
    final settle = p > 0.85 ? 1 + 0.05 * math.sin(math.pi * (p - 0.85) / 0.15) : 1.0;
    final k = math.sin(math.pi * p.clamp(0.0, 1.0)) * 0.30;
    out.add(_DropState(
      key: FluidGlassNavBar.dropChildKeys[i],
      center: pos,
      radius: rC * grow * (1 + bumpOf(p)) * settle,
      angle: dir,
      stretchK: k,
    ));

    // whisker 细丝：行程 18%~75% 存在（reverse 即收回探丝）。
    if (p > 0.18 && p < FluidGlassNavBar.wirePinch) {
      final w = FluidGlassNavBar.wireWidth(p);
      final dist = (pos - m).distance;
      final len = math.max(dist - rM * 0.55 - rC * 0.55 * grow, w * 1.5);
      out.add(_DropState(
        key: FluidGlassNavBar.wireKeys[i],
        center: Offset.lerp(m, pos, 0.5)!,
        radius: w / 2,
        angle: dir,
        wireLen: len,
      ));
    }

    // 断丝微液滴（pinch 后 17% 行程内在断点淡出飞散）。
    if (p > FluidGlassNavBar.wirePinch && p < 0.92) {
      final fade = 1 - (p - FluidGlassNavBar.wirePinch) / 0.17;
      final dirV = (pos - m) / (pos - m).distance;
      out.add(_DropState(
        key: ValueKey('fluidPinch$i'),
        center: m + dirV * ((pos - m).distance * 0.55 + (1 - fade) * 14),
        radius: 3 * fade.clamp(0.2, 1.0),
        opacity: fade.clamp(0.0, 1.0),
      ));
    }
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
                // 绘制层：凹口胶囊 + gooey 液体 + 视觉 + 图标（Clip.none 上溢）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: FluidGlassNavBar.navHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _bar(glassOn, totalWidth),
                      _gooLayer(t, totalWidth, glassOn, halo: true),
                      _gooLayer(t, totalWidth, glassOn, halo: false),
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

  // ── 凹口胶囊（双玻璃皮肤）────────────────────────────────────────

  Widget _bar(bool glassOn, double totalWidth) {
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
              child: glassOn
                  ? const GlassContainer(
                      borderRadius: BorderRadius.all(Radius.circular(25)),
                      padding: EdgeInsets.zero,
                      child: SizedBox.expand(),
                    )
                  : const _FrostedBar(),
            ),
            // 凹口缘描边（全路径 1px 白，玻璃/磨砂同款轮廓）。
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

  // ── gooey 液层（双层 metaball：halo 柔光 / core 实体）────────────

  Widget _gooLayer(double t, double totalWidth, bool glassOn,
      {required bool halo}) {
    final drops = _computeDrops(t, totalWidth);
    final children = <Widget>[
      for (final d in drops)
        if (d.isWire)
          Positioned(
            left: d.center.dx - d.wireLen / 2,
            top: d.center.dy - d.radius,
            width: d.wireLen,
            height: d.radius * 2,
            child: Transform.rotate(
              angle: d.angle,
              child: DecoratedBox(
                key: halo ? null : d.key,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: d.opacity),
                  borderRadius: BorderRadius.all(Radius.circular(d.radius)),
                ),
              ),
            ),
          )
        else
          Positioned(
            left: d.center.dx - d.radius,
            top: d.center.dy - d.radius,
            width: d.radius * 2,
            height: d.radius * 2,
            child: Transform.rotate(
              angle: d.angle,
              child: Transform.scale(
                scaleX: 1 + d.stretchK,
                scaleY: 1 - 0.6 * d.stretchK,
                child: DecoratedBox(
                  key: halo ? null : d.key,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: d.opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
    ];

    // metaball：blur 软化 alpha + 阈值矩阵硬化 → 重叠粘连、分离断颈。
    // halo 层（σ13 柔阈值）给边缘光晕，core 层（σ7 紧阈值）画实体。
    return Positioned.fill(
      child: IgnorePointer(
        child: KeyedSubtree(
          key: halo ? FluidGlassNavBar.gooHaloKey : FluidGlassNavBar.gooKey,
          child: Opacity(
            opacity: halo
                ? (glassOn ? 0.14 : 0.10)
                : FluidGlassNavBar.liquidOpacity(glassOn),
            child: ColorFiltered(
              colorFilter: halo
                  ? const ColorFilter.matrix([
                      1, 0, 0, 0, 0,
                      0, 1, 0, 0, 0,
                      0, 0, 1, 0, 0,
                      0, 0, 0, 8, -2, // 柔阈值（光晕）
                    ])
                  : const ColorFilter.matrix([
                      1, 0, 0, 0, 0,
                      0, 1, 0, 0, 0,
                      0, 0, 1, 0, 0,
                      0, 0, 0, 18, -7, // 紧阈值（实体 gooey）
                    ]),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: halo ? 13 : 7,
                  sigmaY: halo ? 13 : 7,
                ),
                child: Stack(clipBehavior: Clip.none, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 左右两瓣（首页 / 收藏）───────────────────────────────────────

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

  // ── 图标层（＋/× 旋转 + 子滴图标淡入；玻璃上白字加暗投影）─────────

  static const List<Shadow> _iconShadows = [
    Shadow(color: Color(0x59000000), blurRadius: 4),
  ];

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
        left: totalWidth / 2 - 12,
        top: FluidGlassNavBar.motherCenterY - 12,
        width: 24,
        height: 24,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: rot * math.pi / 4,
            child: const Icon(Icons.add,
                size: 24, color: Colors.white, shadows: _iconShadows),
          ),
        ),
      ),
    ];
    for (var i = 0; i < 3; i++) {
      final target = FluidGlassNavBar.childTarget(i, totalWidth: totalWidth);
      children.add(
        Positioned(
          left: target.dx - 12,
          top: target.dy - 12,
          width: 24,
          height: 24,
          child: IgnorePointer(
            child: Opacity(
              opacity: iconOp,
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

/// 液滴视觉层：rim 描边 + 高光月牙 + 底部内影 + 丝轴高光 + 涟漪环
/// （玻璃质感的「厚度」，goo 层只管形）。
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
    final shrinkFade = 1 - FluidGlassNavBar.interval(t, 0.16, 0.28);
    if (shrink > 0 && shrinkFade > 0) {
      final radius = rM * (1.9 - 0.88 * Curves.easeOut.transform(shrink));
      canvas.drawCircle(
        Offset(cx, mcy),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 + 2.0 * shrink
          ..color = Colors.white.withValues(alpha: 0.55 * shrinkFade),
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

    // 母滴空心环（展开态玻璃环，视频同款）。
    final hollow = FluidGlassNavBar.interval(
      t,
      FluidGlassNavBar.hollowStart,
      FluidGlassNavBar.hollowEnd,
    );
    if (hollow > 0) {
      canvas.drawCircle(
        Offset(cx, mcy),
        rM,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: 0.55 * hollow),
      );
    }

    // 液滴玻璃质感：rim + 高光月牙 + 底部内影（含细丝轴高光）。
    for (final d in _computeDrops(t, totalWidth)) {
      _dropGlass(canvas, d);
    }
  }

  void _dropGlass(Canvas canvas, _DropState d) {
    canvas.save();
    canvas.translate(d.center.dx, d.center.dy);
    canvas.rotate(d.angle);
    canvas.scale(1 + d.stretchK, 1 - 0.6 * d.stretchK);
    final r = d.radius;
    if (d.isWire) {
      // 丝 rim + 轴向高光（玻璃反光沿丝拉长变细）。
      final half = d.wireLen / 2;
      final rect = Rect.fromLTRB(-half, -r, half, r);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.35 * d.opacity),
      );
      canvas.drawLine(
        Offset(-half * 0.8, -r * 0.35),
        Offset(half * 0.8, -r * 0.35),
        Paint()
          ..strokeWidth = math.max(r * 0.35, 0.6)
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.40 * d.opacity),
      );
    } else {
      // rim 描边（玻璃边缘）。
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.55 * d.opacity),
      );
      if (glassOn && d.opacity > 0.5) {
        // 高光月牙（左上，玻璃反光）。
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: r * 0.72),
          math.pi * 0.85,
          math.pi * 0.55,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.45 * d.opacity),
        );
      }
      // 底部内影（液体厚度）。
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: r * 0.82),
        math.pi * 0.15,
        math.pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withValues(alpha: 0.10 * d.opacity),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidVisualPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.totalWidth != totalWidth ||
      oldDelegate.glassOn != glassOn;
}
