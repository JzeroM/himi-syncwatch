import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:liquid_glass_widgets/utils/draggable_indicator_physics.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

/// 移动态真折射水珠镜片。
///
/// 直连包内 [GlassEffect]，绕过 `AnimatedGlassIndicator`（其内部强制
/// `blur: 0` 导致 Skia 上背景捕获永不启动，折射与彩虹色散全部失效）：
/// - `settings.blur = 0.01` 满足 GlassEffect 捕获门槛
///   （`interactionIntensity > 0.01 && key != null && blur > 0`），
///   移动中每帧对 [backgroundKey] 边界（胶囊+导航图标）toImageSync，
///   shader 拿到真背景后折射形变与 RGB 色散才真正生效；
/// - [backgroundKey] 指向导航 RepaintBoundary（非默认 body 边界）：
///   图标在采样纹理内 → 水珠划过时图标被物理折射弯折；水珠自身在
///   边界之外，不会自采样产生反馈环；越界像素由纹理钳边兜底；
/// - [activity] 由外部弹簧驱动 0..1：0 静止（仅扁平实心 pill、镜片不挂载、
///   零 shader 开销），1 活动（pill 淡出、镜片挂载、矩形上下外扩
///   [expansionV]、jelly 果冻形变吃 [velocity]）；
/// - **彩虹 = 纯物理色散**（vendored 包 [PATCH himi] 补丁，色散 0.12→4.0）：
///   沿边折射带（edgeZone 滑杆 20~24，默认 20，平方衰减压中带 → 贴边
///   一圈干净彩边）把捕获内容的
///   RGB 通道分开 —— 只在背后有对比处（图标边、胶囊边线）出彩边，
///   随果冻形变流动；无任何自发光色环；
/// - quality 按引擎分流：Impeller（iOS）→ premium（原生折射层），
///   Skia（安卓）→ standard（interactive_indicator.frag 捕获折射）。
///
/// 作为导航 Stack 的直接子级渲染：胶囊与图标是它的兄弟层而非祖先，
/// 适配层与包内 `LightweightLiquidGlass` 对各自子级的无条件裁剪
/// 都碰不到这里，水珠才能溢出胶囊。
class LiquidBlobLens extends StatelessWidget {
  const LiquidBlobLens({
    super.key,
    required this.left,
    required this.width,
    required this.activity,
    required this.velocity,
    required this.settings,
    required this.pillColor,
    this.backgroundKey,
    this.edgeZone = 20,
    this.pillShadows = const [
      BoxShadow(color: Color(0x29FFFFFF), blurRadius: 14),
    ],
    this.paddingV = 5,
    this.expansionV = 11,
    this.borderRadius = 25,
  });

  /// 水珠左沿（导航局部坐标）。
  final double left;

  /// 水珠宽度（整体放大倍数由调用方按弹簧值算好传入，宽高同比）。
  final double width;

  /// 弹簧活动量 0..1（0 静止实心，1 完全镜片 + 外扩）。
  final double activity;

  /// 横向速度（包内 jelly 坐标系，对齐值 -1..1 的每秒变化量）。
  final double velocity;

  /// 镜片玻璃参数（调用方从 baseIndicatorSettings 组装，
  /// 含 Skia 捕获钥匙 `blur: 0.01` 与固定 0.5 色散）。
  final lg.LiquidGlassSettings settings;

  /// 采样边界钥匙：导航 [RepaintBoundary]（胶囊+图标，不含水珠自身）。
  ///
  /// 覆盖 `LiquidGlassScope` 默认的 body 边界 —— 只有图标在采样纹理内，
  /// 水珠移动时导航图标才会被真实折射形变；水珠本身在边界之外，
  /// 不会自采样成反馈环。
  final GlobalKey? backgroundKey;

  /// 折射范围（shader edgeZone，逻辑 px）：折射/色散影响带从边缘向内的
  /// 宽度。App「折射范围」滑杆 20~24，默认 20；随调随生效。
  final double edgeZone;

  /// 静止实心胶囊底色（白 0.10）。
  final Color pillColor;

  /// 静止实心胶囊外光晕（无边框）。
  final List<BoxShadow> pillShadows;

  /// 水珠在 60 高导航内的上下留白（60 - 2×5 = 50 高）。
  final double paddingV;

  /// 活动态矩形外扩量（相对静止矩形上下各扩，11 → 超出胶囊各 6px）。
  final double expansionV;

  /// 水珠圆角（25 = 50 高半圆直边）。
  final double borderRadius;

  /// 画质分流：按引擎能力。
  ///
  /// iOS 恒为 Impeller（`ImageFilter.isShaderFilterSupported =>
  /// _impellerEnabled` 为 true）→ `premium`（Impeller 原生 3D 折射）；
  /// 安卓关闭 Impeller → Skia → 该 getter 为 false → `standard`
  /// （`interactive_indicator.frag`，含 [PATCH himi] 调校）。
  /// iOS 的 premium 取向参数与着色器补丁见 settings / premium shader。
  static lg.GlassQuality get quality =>
      !kIsWeb && ui.ImageFilter.isShaderFilterSupported
          ? lg.GlassQuality.premium
          : lg.GlassQuality.standard;

  @override
  Widget build(BuildContext context) {
    final q = quality;
    final isStd = q == lg.GlassQuality.standard || q == lg.GlassQuality.minimal;
    // pill 活动量前 15% 淡出，交棒给镜片
    final bgOpacity = (1.0 - activity / 0.15).clamp(0.0, 1.0);
    final rect = RelativeRect.lerp(
      RelativeRect.fill,
      RelativeRect.fromLTRB(0, -expansionV, 0, -expansionV),
      activity,
    )!;

    return Positioned.fill(
      // 纯视觉层：水珠盖在图标之上（参考效果），放行所有点击给下层图标
      child: IgnorePointer(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: paddingV),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: width,
                child: lg.InheritedLiquidGlass(
                  settings: settings,
                  quality: q,
                  avoidsRefraction: false,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (bgOpacity > 0)
                        Positioned.fromRelativeRect(
                          rect: rect,
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: bgOpacity,
                              child: DecoratedBox(
                                decoration: ShapeDecoration(
                                  color: pillColor,
                                  shape: lg.LiquidRoundedRectangle(
                                    borderRadius: borderRadius,
                                  ),
                                  shadows: pillShadows,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      if (activity > 0.05)
                        Positioned.fromRelativeRect(
                          rect: rect,
                          child: Transform(
                            alignment: Alignment.center,
                            transform:
                                DraggableIndicatorPhysics.buildJellyTransform(
                              velocity: Offset(velocity, 0),
                              maxDistortion: isStd ? 0.35 : 0.8,
                              velocityScale: 10,
                            ),
                            child: GlassEffect(
                              shape: lg.LiquidRoundedRectangle(
                                borderRadius: borderRadius,
                              ),
                              settings: settings.copyWith(visibility: activity),
                              quality: q,
                              interactionIntensity: activity,
                              // 采样导航边界（胶囊+图标）→ 图标被真实折射形变
                              backgroundKey: backgroundKey,
                              // 折射范围（滑杆 20~24，默认 20）
                              edgeZone: edgeZone,
                              clipExpansion: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              // std 输入 2.0：×0.35 归一化后 ~0.7px 中性软边
                              rimThickness: isStd
                                  ? 2.0
                                  : settings.effectiveThickness.clamp(0.8, 8.0),
                              ambientRim: settings.ambientRim > 0
                                  ? settings.ambientRim
                                  : (isStd ? 0.08 : 0.1),
                              baseAlphaMultiplier: isStd ? 0.08 : 0.2,
                              edgeAlphaMultiplier: isStd ? 0.15 : 0.4,
                              child: const lg.GlassGlow(
                                glowColor: Color(0x00000000),
                                child: SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
