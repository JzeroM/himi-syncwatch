import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/blob_lens.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

/// 流体液态导航（698 N15-F，样式注册表第②款）：**液态玻璃材质之上的弹性
/// 动效**（对齐 jurajkusnier/fluid-bottom-navigation 的观感语言）：
/// - 选中液滴 **bouncy 弹簧**过冲移动（溅弹回稳）；
/// - 飞行中按速度**拉伸形变**（squash & stretch，液滴被拽着走的液态感）；
/// - 选中图标**弹跳放大**（easeOutBack 过冲）。
///
/// **双玻璃形态（698 N5-G，随「液态玻璃」开关）**：
/// - 开 = 液态玻璃：真折射（模糊/色散/动态高光/噪点，`glassTuning` 实时
///   跟随）；
/// - 关 = 轻量磨砂：毛玻璃（模糊 σ12 + 半透明 + 1px 描边 + 微光圈，零
///   折射计算，低端机/TV 流畅）。动效是性格、玻璃是皮肤。
class FluidGlassNavBar extends ConsumerStatefulWidget {
  const FluidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// 导航整体高（与玻璃水滴款同档，698 N15-B）。
  static const double navHeight = ShellNavBar.navHeight;

  /// 液滴高。
  static const double blobHeight = ShellNavBar.blobHeight;

  /// 选中图标弹跳放大上限（1 → 1.18）。
  static const double iconBounce = 1.18;

  /// 拉伸形变强度系数（速度 × 系数喂 jelly，流体款比水滴款夸张）。
  static const double stretchGain = 1.8;

  @override
  ConsumerState<FluidGlassNavBar> createState() => _FluidGlassNavBarState();
}

class _FluidGlassNavBarState extends ConsumerState<FluidGlassNavBar> {
  /// 捕获边界（胶囊 + 图标）：液镜折射采样源。
  final _navCaptureKey = GlobalKey();

  /// 上一帧液滴位置（速度估计 → 拉伸形变）。
  double _lastBlobPos = 0;
  double _blobVelocity = 0;

  @override
  Widget build(BuildContext context) {
    final glassOn = ref.watch(settingsProvider.select((s) => s.glassUi));
    final tuning = ref.watch(glassTuningProvider);

    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth;
      final tabW = totalWidth / ShellNavBar.tabCount;

      return SizedBox(
        height: FluidGlassNavBar.navHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 捕获边界：胶囊 + 图标（液镜 backgroundKey 采样源）。
            Positioned.fill(
              child: RepaintBoundary(
                key: _navCaptureKey,
                child: Stack(
                  children: [
                    // 胶囊皮肤（N5-G 双玻璃）：开 = 真折射玻璃容器；
                    // 关 = 轻量磨砂（模糊 + 半透明 + 描边 + 微光圈）。
                    Positioned.fill(
                      child: glassOn
                          ? const GlassContainer(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(25)),
                              padding: EdgeInsets.zero,
                              child: SizedBox.expand(),
                            )
                          : const _FrostedCapsule(),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (var i = 0; i < ShellNavBar.tabCount; i++)
                            Expanded(
                              child: _FluidTab(
                                icon: i == widget.currentIndex
                                    ? ShellNavBar.tabSelectedIcons[i]
                                    : ShellNavBar.tabIcons[i],
                                label: ShellNavBar.tabLabels[i],
                                selected: i == widget.currentIndex,
                                onTap: () => widget.onSelect(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 液滴：bouncy 弹簧过冲 + 速度拉伸（直接作 Stack 子级——
            // LiquidBlobLens/_FrostedBlob 内部自带 Positioned，勿再包）。
            lg.SpringBuilder(
              spring: lg.GlassSpring.bouncy(
                duration: const Duration(milliseconds: 450),
                extraBounce: 0.12,
              ),
              value: widget.currentIndex.toDouble(),
              builder: (context, pos, _) {
                // 速度估计（每帧位置变化）→ jelly 拉伸。
                _blobVelocity =
                    ((pos - _lastBlobPos) * 60).clamp(-1.0, 1.0).toDouble();
                _lastBlobPos = pos;
                // 液滴宽 = tab 宽比例（与玻璃水滴款同口径）。
                final blobW = tabW * 0.75;
                final left = (pos + 0.5) * tabW - blobW / 2;
                return glassOn
                    ? LiquidBlobLens(
                        key: const ValueKey('fluidNavBlob'),
                        left: left,
                        width: blobW,
                        activity: 1,
                        velocity: _blobVelocity * FluidGlassNavBar.stretchGain,
                        settings: _glassSettings(tuning, pos),
                        pillColor: Colors.white.withValues(alpha: 0.10),
                        backgroundKey: _navCaptureKey,
                        edgeZone:
                            tuning.edgeZone ?? glassDefault('glassEdgeZone'),
                      )
                    : _FrostedBlob(left: left, width: blobW);
              },
            ),
          ],
        ),
      );
    });
  }

  /// 液镜参数（与玻璃水滴款同源：[lg.AnimatedGlassIndicator] 基准 +
  /// `glassTuning` 实时覆盖；光源相位随液滴位置扫动）。
  lg.LiquidGlassSettings _glassSettings(GlassTuning tuning, double pos) {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    return lg.AnimatedGlassIndicator.baseIndicatorSettings.copyWith(
      glassColor: Colors.white.withValues(alpha: isIOS ? 0.05 : 0.14),
      thickness: tuning.thickness ?? glassDefault('glassThickness'),
      saturation: tuning.saturation ?? glassDefault('glassSaturation'),
      chromaticAberration: 0.5,
      refractiveIndex:
          tuning.refractiveIndex ?? glassDefault('glassRefractiveIndex'),
      lightIntensity:
          tuning.lightIntensity ?? glassDefault('glassLightIntensity'),
      blur: 0.01,
      ambientRim: isIOS ? 0.08 : 0.18,
      glowIntensity: isIOS ? 0.6 : 1.2,
      ambientStrength: isIOS ? 0.0 : 0.4,
      edgeAbsorption: 0.10,
      lightAngle: math.pi / 2 +
          (pos / (ShellNavBar.tabCount - 1) - 0.5) * math.pi,
    );
  }
}

/// 单 tab（图标弹跳 + 文字加粗切换）。
class _FluidTab extends StatelessWidget {
  const _FluidTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: FluidGlassNavBar.navHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 698 N15-F：选中图标弹跳放大（easeOutBack 过冲）。
              TweenAnimationBuilder<double>(
                tween: Tween(end: selected ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                builder: (context, t, child) => Transform.scale(
                  scale: 1 + (FluidGlassNavBar.iconBounce - 1) * t,
                  child: child,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 轻量磨砂胶囊（698 N5-G 玻璃乙）：毛玻璃（模糊 + 半透明 + 描边 + 微光圈），
/// 零折射计算——「液态玻璃」开关关闭时的流体款皮肤。
class _FrostedCapsule extends StatelessWidget {
  const _FrostedCapsule();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(25)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
              width: 1,
            ),
            borderRadius: const BorderRadius.all(Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.12),
                blurRadius: 10,
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// 轻量磨砂液滴（698 N5-G）：正椭圆 + 半透明 + 描边 + 微光圈。
class _FrostedBlob extends StatelessWidget {
  const _FrostedBlob({required this.left, required this.width});

  final double left;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: (FluidGlassNavBar.navHeight - FluidGlassNavBar.blobHeight) / 2,
      width: width,
      height: FluidGlassNavBar.blobHeight,
      child: DecoratedBox(
        key: const ValueKey('fluidNavBlob'),
        // 698 N15-C：正椭圆液滴（OvalBorder = 真椭圆，随宽高自适应）。
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: OvalBorder(
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.42),
              width: 1,
            ),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x29FFFFFF),
              blurRadius: 14,
            ),
          ],
        ),
      ),
    );
  }
}
