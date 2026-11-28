import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/core/himi_text.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

/// 悬浮方块导航（698 N32-N35，样式注册表第③款）：Dribbble「Floating
/// Navigation Bar」动效 1:1（视频逐帧实测）。
///
/// **N35 定稿**：
/// - **槽位分配**：Emby/收藏/首页/声网/设置（[slotBranches]，首页居中
///   **默认锁定**）；两端各留 [slotMargin] 凹口安全余量，首/末命中区
///   扩到条端；barPath 几何同源（无飞边叠线）；
/// - **切换动效 = 图标位移接力**（视频实测）：目标槽图标点亮 → 平移
///   **升起**进浮块 → 到达切换**描边→填充**（tabIcons↔tabSelectedIcons）
///   → 旧图标**降落**回原槽变描边暗色；标签文字随胶囊平移过渡；
/// - **立体饱满感**：玻璃水滴镜片（折射厚度/折射率上调=中间鼓）+ 径向
///   高光斑 + 底部内阴影弧 + 菲涅尔缘；玻璃关平涂同步；
/// - **点击/拖动双交互**：点击切换；横向拖动浮块跟手平移（凹口实时
///   跟随、经过槽点亮预览），松手吸附最近槽触发接力动效。

/// 玻璃 quality（698 N74d/N76）：Impeller 可用 → premium 真透底
/// （BackdropFilter）；否则 standard 截帧。安卓已全端开启 Impeller
/// （Manifest meta-data，iOS/鸿蒙引擎自带），手机三端 + TV 同管线。
lg.GlassQuality get _navGlassQuality =>
    (!kIsWeb && ui.ImageFilter.isShaderFilterSupported)
        ? lg.GlassQuality.premium
        : lg.GlassQuality.standard;

class SquircleNavBar extends ConsumerStatefulWidget {
  const SquircleNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// 条高（N34 加高）。
  static const double navHeight = 62;

  /// 条体在盒内的顶部偏移（浮块悬顶余量）。
  static const double barTop = 14;

  /// 浮块尺寸/圆角。
  static const double block = 44;
  static const double blockRadius = 14;

  /// 条体圆角。
  static const double barRadius = 18;

  /// 凹口与浮块/标签的恒定可见间距。
  static const double notchGap = 7;

  /// 浮块垂直落位（块心在条上缘下方 8）。
  static const double blockCenterY = 8;

  /// 标签骑跨条体下缘（中心 = 条下缘）。
  static double get labelCenterY => navHeight;

  /// 标签胶囊尺寸。
  static const double labelHeight = 20;
  static const double labelHalfHeight = 10;

  /// 盒高 = 悬顶余量 + 条高 + 标签下缘余量。
  static const double boxHeight = barTop + navHeight + 12;

  /// 顶凹口水平半宽（= 浮块半宽 + 恒距）。
  static double get blockNotchRadius => block / 2 + notchGap;

  /// 槽位安全余量（N35：两端各留——浮块半宽 + 恒距 + 条圆角，端部槽
  /// 凹口轮廓完整不碰圆角区）。
  static const double slotMargin = block / 2 + notchGap + barRadius; // 47

  /// 视觉槽 → 壳层分支（N35：首页↔Emby 交换、首页居中默认锁定）。
  @visibleForTesting
  static const List<int> slotBranches = [2, 1, 0, 3, 4];

  /// 分支 → 视觉槽。
  static int slotOfBranch(int branch) =>
      slotBranches.indexOf(branch).clamp(0, slotBranches.length - 1);

  /// 槽位区宽度（条宽 − 两端余量）。
  static double slotWidthOf(double totalWidth) =>
      (totalWidth - 2 * slotMargin) / slotBranches.length;

  /// 槽心 x。
  static double slotCx(int slot, double totalWidth) =>
      slotMargin + slotWidthOf(totalWidth) * (slot + 0.5);

  /// 最近槽（拖动松手吸附用）。
  static int nearestSlot(double x, double totalWidth) {
    final sw = slotWidthOf(totalWidth);
    return ((x - slotMargin) / sw - 0.5).round().clamp(0, 4);
  }

  /// 跳槽时长 / 标签延迟 / 升起接力时长。
  static const Duration slideDuration = Duration(milliseconds: 420);
  static const Duration labelLag = Duration(milliseconds: 40);
  static const Duration liftDuration = Duration(milliseconds: 420);

  /// 浮块层/条体层测试钥匙。
  static const Key blockKey = ValueKey('squircleBlock');
  static const Key barKey = ValueKey('squircleBar');

  /// 条体路径：圆角矩形 + 顶凹口（浮块外扩轮廓）+ 底凹口（标签胶囊外扩
  /// 轮廓）。凹口入口与轮廓同源坐标（N35：无飞边）。
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
    // 入口与轮廓同源（N35）：入口 = 轮廓最宽点，钳位整组同移。
    final shift = blockCx < slotMargin
        ? (slotMargin - blockCx)
        : (blockCx > w - slotMargin ? (w - slotMargin - blockCx) : 0.0);
    final bcx = blockCx + shift;
    final tx1 = bcx - topHalf;
    final tx2 = bcx + topHalf;

    path.moveTo(r, 0);
    if (tx2 - tx1 > 4 && tx1 >= r - 0.5 && tx2 <= w - r + 0.5) {
      path.lineTo(tx1, 0);
      path.lineTo(tx1, topArcCy);
      path.arcTo(
        Rect.fromCircle(
          center: Offset(tx1 + topCornerR, topArcCy),
          radius: topCornerR,
        ),
        math.pi,
        -math.pi / 2,
        false,
      );
      path.lineTo(tx2 - topCornerR, topDepth);
      path.arcTo(
        Rect.fromCircle(
          center: Offset(tx2 - topCornerR, topArcCy),
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

    // ── 底凹口（标签胶囊外扩轮廓）：角 r17 半圆帽 ──
    final botCornerR = labelHalfHeight + notchGap; // 17
    final botHalf = math.max(labelHalfWidth + notchGap, botCornerR);
    final lShift = labelCx < slotMargin
        ? (slotMargin - labelCx)
        : (labelCx > w - slotMargin ? (w - slotMargin - labelCx) : 0.0);
    final bcx2 = labelCx + lShift;
    final bx1 = bcx2 + botHalf;
    final bx2 = bcx2 - botHalf;
    if (bx1 - bx2 > 4 && bx2 >= r - 0.5 && bx1 <= w - r + 0.5) {
      path.lineTo(bx1, h);
      path.arcTo(
        Rect.fromCircle(
          center: Offset(bx1 - botCornerR, h),
          radius: botCornerR,
        ),
        0,
        -math.pi / 2,
        false,
      );
      path.lineTo(bx2 + botCornerR, h - botCornerR);
      path.arcTo(
        Rect.fromCircle(
          center: Offset(bx2 + botCornerR, h),
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

  /// 标签胶囊实测宽度。
  static double labelWidthOf(String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + 24;
  }

  /// 玻璃水滴镜片参数（立体饱满感：折射厚度/折射率上调 = 中间鼓）。
  @visibleForTesting
  static lg.LiquidGlassSettings lensSettings() {
    return lg.AnimatedGlassIndicator.baseIndicatorSettings.copyWith(
      glassColor: Colors.white.withValues(alpha: 0.08),
      blur: 0.01,
      refractiveIndex: 1.4,
      thickness: 5.0,
      lightIntensity: 0.85,
    );
  }

  @override
  ConsumerState<SquircleNavBar> createState() => _SquircleNavBarState();
}

class _SquircleNavBarState extends ConsumerState<SquircleNavBar>
    with TickerProviderStateMixin {
  /// 浮块平移（跳槽弹滑）。
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: SquircleNavBar.slideDuration,
    reverseDuration: SquircleNavBar.slideDuration,
  );

  /// 图标位移接力（升起/降落，N35）。
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: SquircleNavBar.liftDuration,
  );

  /// 起跳分支 → 落位分支。
  int _from = 0;
  int _to = 0;

  /// 拖动跟手位置（非空 = 拖动中，浮块 x 跟手）。
  double? _dragX;

  /// 拖动预览槽（经过点亮）。
  int? _dragSlot;

  @override
  void initState() {
    super.initState();
    // N35：默认锁定首页（壳层初始分支 = 首页 → 浮块停中心槽）。
    _from = widget.currentIndex;
    _to = widget.currentIndex;
    _lift.value = 1;
  }

  @override
  void didUpdateWidget(covariant SquircleNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != _to) {
      _from = _to;
      _to = widget.currentIndex;
      _slide.forward(from: 0);
      _lift.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _selectTab(int i) {
    if (i == _to && _lift.value >= 1) return;
    _from = _to;
    _to = i;
    _slide.forward(from: 0);
    _lift.forward(from: 0);
    widget.onSelect(i);
  }

  void _onDragStart(DragStartDetails d, double totalWidth) {
    _dragX = d.localPosition.dx.clamp(
      SquircleNavBar.slotCx(0, totalWidth),
      SquircleNavBar.slotCx(4, totalWidth),
    );
    _dragSlot = SquircleNavBar.nearestSlot(_dragX!, totalWidth);
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d, double totalWidth) {
    _dragX = d.localPosition.dx.clamp(
      SquircleNavBar.slotCx(0, totalWidth),
      SquircleNavBar.slotCx(4, totalWidth),
    );
    _dragSlot = SquircleNavBar.nearestSlot(_dragX!, totalWidth);
    setState(() {});
  }

  void _onDragEnd(double totalWidth) {
    final slot = SquircleNavBar.nearestSlot(_dragX ?? 0, totalWidth);
    final branch = SquircleNavBar.slotBranches[slot];
    _dragX = null;
    _dragSlot = null;
    _selectTab(branch);
  }

  @override
  Widget build(BuildContext context) {
    final glassOn = ref.watch(settingsProvider.select((s) => s.glassUi));
    return SizedBox(
      height: SquircleNavBar.boxHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _onDragStart(d, totalWidth),
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, totalWidth),
          onHorizontalDragEnd: (_) => _onDragEnd(totalWidth),
          onHorizontalDragCancel: () {
            _dragX = null;
            _dragSlot = null;
            setState(() {});
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([_slide, _lift]),
            builder: (context, _) {
              // 浮块位置：拖动跟手 > 动画值。
              final e = Curves.easeOutBack.transform(_slide.value);
              final fromSlot = SquircleNavBar.slotOfBranch(_from);
              final toSlot = SquircleNavBar.slotOfBranch(_to);
              final animBlockCx = SquircleNavBar.slotCx(fromSlot, totalWidth) *
                      (1 - e) +
                  SquircleNavBar.slotCx(toSlot, totalWidth) * e;
              final blockCx = _dragX ?? animBlockCx;
              // 标签延迟拖尾。
              final labelT = ((_slide.value *
                          SquircleNavBar.slideDuration.inMilliseconds -
                      SquircleNavBar.labelLag.inMilliseconds) /
                  (SquircleNavBar.slideDuration.inMilliseconds -
                      SquircleNavBar.labelLag.inMilliseconds))
                  .clamp(0.0, 1.0);
              final labelE = Curves.easeOutBack.transform(labelT);
              final animLabelCx =
                  SquircleNavBar.slotCx(fromSlot, totalWidth) * (1 - labelE) +
                      SquircleNavBar.slotCx(toSlot, totalWidth) * labelE;
              final labelCx = _dragX ?? animLabelCx;
              final barPath = SquircleNavBar.barPath(
                size: Size(totalWidth, SquircleNavBar.navHeight),
                blockCx: blockCx,
                labelCx: labelCx,
                labelHalfWidth: SquircleNavBar.labelWidthOf(
                        ShellNavBar.tabLabels[_to]) /
                    2,
              );
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // 条体（圆角矩形 + 上下凹口）。
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
                  // 浮块（玻璃水滴 + 立体感；图标由接力层画在其上）。
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
                            curve: const Interval(0.0, 0.5,
                                curve: Curves.easeOut),
                            reverseCurve: const Interval(0.5, 1.0),
                          ),
                        ),
                        child: _block(glassOn),
                      ),
                    ),
                  ),
                  // 命中层（首/末槽扩到条端）。
                  for (var i = 0; i < ShellNavBar.tabCount; i++)
                    _slotHit(i, totalWidth),
                  // 槽位图标层（描边形态 + 位移接力中的图标，叠浮块上）。
                  for (var i = 0; i < ShellNavBar.tabCount; i++)
                    _slotIconLayer(i, totalWidth, blockCx),
                  // 标签胶囊（文字平移过渡）。
                  Positioned(
                    left: labelCx -
                        SquircleNavBar.labelWidthOf(
                                ShellNavBar.tabLabels[_to]) /
                            2,
                    top: SquircleNavBar.barTop +
                        SquircleNavBar.labelCenterY -
                        SquircleNavBar.labelHalfHeight,
                    child: IgnorePointer(child: _label(glassOn, labelT)),
                  ),
                ],
              );
            },
          ),
        );
      }),
    );
  }

  /// 图标层（N35 位移接力）：每槽一个图标位——
  /// - _to 图标：lift 0→1 从槽位**升起**进浮块（描边→到达填充）；
  /// - _from 图标（切换中）：lift 0→1 从浮块**降落**回原槽（填充→描边）；
  /// - 其余槽：描边暗色常驻；拖动预览槽点亮。
  Widget _slotIconLayer(int slot, double totalWidth, double blockCx) {
    final branch = SquircleNavBar.slotBranches[slot];
    final liftT = _lift.value;
    final eLift = Curves.easeOutCubic.transform(liftT);
    final slotPos = Offset(
      SquircleNavBar.slotCx(slot, totalWidth),
      SquircleNavBar.barTop + SquircleNavBar.navHeight / 2,
    );
    final blockPos = Offset(
      blockCx,
      SquircleNavBar.barTop + SquircleNavBar.blockCenterY,
    );
    // 图标位置/形态。
    final bool isTo = branch == _to && _from != _to;
    final bool isFrom = branch == _from && _from != _to;
    late final Offset pos;
    late final double morph; // 0 = 描边（未选中），1 = 填充（选中）
    if (isTo) {
      // 升起：槽位 → 浮块（追踪实时块心）。
      pos = Offset.lerp(slotPos, blockPos, eLift)!;
      morph = Curves.easeIn.transform(((liftT - 0.85) / 0.15).clamp(0.0, 1.0));
    } else if (isFrom) {
      // 降落：浮块 → 原槽位。
      pos = Offset.lerp(blockPos, slotPos, eLift)!;
      morph = 1 - Curves.easeOut.transform((liftT / 0.15).clamp(0.0, 1.0));
    } else if (branch == _to) {
      // 落位态：图标在浮块（填充）。
      pos = blockPos;
      morph = 1;
    } else {
      pos = slotPos;
      morph = 0;
    }
    // 颜色：填充（块内）白；描边（槽位）白70；拖动预览点亮白。
    final previewLit = _dragSlot == slot;
    final color = Color.lerp(
      previewLit ? HimiText.primary(context) : HimiText.secondary(context),
      HimiText.primary(context),
      morph,
    )!;
    return Positioned(
      left: pos.dx - 12,
      top: pos.dy - 12,
      width: 24,
      height: 24,
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 1 - morph,
              child: Icon(ShellNavBar.tabIcons[branch], size: 22, color: color),
            ),
            if (morph > 0)
              Opacity(
                opacity: morph,
                child: Icon(ShellNavBar.tabSelectedIcons[branch],
                    size: 22, color: color),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slotHit(int slot, double totalWidth) {
    final sw = SquircleNavBar.slotWidthOf(totalWidth);
    final branch = SquircleNavBar.slotBranches[slot];
    // 首/末槽命中区扩到条端（N35：两端空白并入，全条宽可点）。
    final double left;
    final double width;
    if (slot == 0) {
      left = 0;
      width = SquircleNavBar.slotCx(0, totalWidth) + sw / 2;
    } else if (slot == ShellNavBar.tabCount - 1) {
      left = SquircleNavBar.slotCx(slot, totalWidth) - sw / 2;
      width = totalWidth - left;
    } else {
      left = SquircleNavBar.slotCx(slot, totalWidth) - sw / 2;
      width = sw;
    }
    return Positioned(
      left: left,
      top: SquircleNavBar.barTop,
      width: width,
      height: SquircleNavBar.navHeight,
      child: TvFocusable(
        onTap: () => _selectTab(branch),
        child: GestureDetector(
          key: ValueKey('squircleSlot$slot'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectTab(branch),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// 浮块本体（玻璃水滴 + 立体感：高光斑/内阴影；图标由接力层画）。
  Widget _block(bool glassOn) {
    final lens = glassOn
        ? GlassEffect(
            shape: const lg.LiquidRoundedSuperellipse(
              borderRadius: SquircleNavBar.blockRadius,
            ),
            settings: SquircleNavBar.lensSettings(),
            quality: _navGlassQuality,
            interactionIntensity: 1.0,
            // N36：边缘区收敛（44×44 上 edgeZone 20 占半高 → 收 10）。
            edgeZone: 10,
            clipExpansion: const EdgeInsets.all(8),
            rimThickness: 1.5,
            ambientRim: 0.12,
            baseAlphaMultiplier: 0.08,
            edgeAlphaMultiplier: 0.2,
            child: const SizedBox.expand(),
          )
        : DecoratedBox(
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(SquircleNavBar.blockRadius),
              ),
              color: Colors.white.withValues(alpha: 0.14),
            ),
          );
    return DecoratedBox(
      key: SquircleNavBar.blockKey,
      decoration: const BoxDecoration(),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(SquircleNavBar.blockRadius),
        child: Stack(
          children: [
            Positioned.fill(child: lens),
            // 立体感：径向高光斑（顶左亮鼓）。
            const Positioned.fill(child: _GlossLayer()),
            // 立体感：底部内阴影弧（下缘收暗）。
            const Positioned.fill(child: _InnerShadowLayer()),
          ],
        ),
      ),
    );
  }

  /// 标签胶囊（玻璃水滴 + 立体感 + 文字平移过渡）。
  Widget _label(bool glassOn, double labelT) {
    // 文字平移过渡：旧文（_from）淡出、新文（_to）淡入（非瞬间换字）。
    final textFade = Curves.easeIn
        .transform(((labelT - 0.25) / 0.5).clamp(0.0, 1.0));
    // N36：盒宽与 Positioned 定位同源（labelWidthOf(_to)）——双文
    // crossfade 绝对居中不撑盒，标签中心恒 = 浮块中心（错位修复）。
    final width = SquircleNavBar.labelWidthOf(ShellNavBar.tabLabels[_to]);
    final lens = glassOn
        ? GlassEffect(
            shape: const lg.LiquidRoundedSuperellipse(
              borderRadius: SquircleNavBar.labelHalfHeight,
            ),
            settings: SquircleNavBar.lensSettings(),
            quality: _navGlassQuality,
            interactionIntensity: 1.0,
            // N36：参数按小尺寸收敛（edgeZone 20≥胶囊高 → 玻璃糊满
            // 全形体 =「空心框/贴到条上」根因）。
            edgeZone: 4,
            clipExpansion: const EdgeInsets.all(2),
            rimThickness: 1.2,
            ambientRim: 0.12,
            baseAlphaMultiplier: 0.08,
            edgeAlphaMultiplier: 0.2,
            child: const SizedBox.expand(),
          )
        : DecoratedBox(
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(SquircleNavBar.labelHalfHeight),
              ),
              color: Colors.white.withValues(alpha: 0.14),
            ),
          );
    return SizedBox(
      width: width,
      height: SquircleNavBar.labelHeight,
      child: lg.InheritedLiquidGlass(
        settings: SquircleNavBar.lensSettings(),
        quality: _navGlassQuality,
        avoidsRefraction: false,
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(SquircleNavBar.labelHalfHeight),
          child: Stack(
            children: [
              Positioned.fill(child: lens),
              const Positioned.fill(child: _GlossLayer()),
              const Positioned.fill(child: _InnerShadowLayer()),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_from != _to && textFade < 1)
                      Opacity(
                        opacity: 1 - textFade,
                        child: Text(
                          ShellNavBar.tabLabels[_from],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: HimiText.primary(context),
                          ),
                        ),
                      ),
                    Opacity(
                      opacity: _from == _to ? 1 : textFade,
                      child: Text(
                        ShellNavBar.tabLabels[_to],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: HimiText.primary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 立体高光斑（顶左柔光 → 中间亮鼓）。
class _GlossLayer extends StatelessWidget {
  const _GlossLayer();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.5, -0.6),
          radius: 0.9,
          colors: [Color(0x59FFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 1.0],
        ),
      ),
    );
  }
}

/// 立体内阴影（下缘收暗弧 → 饱满鼓感）。
class _InnerShadowLayer extends StatelessWidget {
  const _InnerShadowLayer();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 1.25),
          radius: 1.1,
          colors: [Color(0x1F000000), Color(0x00000000)],
          stops: [0.0, 1.0],
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

/// 条缘玻璃 rim（沿凹口路径描亮边——唯一名义边）。
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
