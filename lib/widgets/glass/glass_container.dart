import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

/// 液态玻璃面板（适配层）。
///
/// 开启时：以 liquid_glass_widgets 的真折射玻璃为底（磨砂/厚度/色散等
/// 参数由设置页滑杆经 GlassTheme 全局调节），叠加本层的半透明着色渐变、
/// 高光描边与悬浮投影；设置中关闭 `glassUi` 后降级为约 90% 透明的
/// 着色底（无模糊/折射），调用方 API 与旧版保持一致。
class GlassContainer extends ConsumerWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.tint = GlassConfig.panelTint,
    this.fallbackColor = GlassConfig.fallbackColor,
    this.showShadow = true,
    this.popup = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final Color tint;

  /// 关闭玻璃后的降级底色（弹层传 [GlassConfig.popupFallback]
  /// 保持 94% 不透明压住背景）。
  final Color fallbackColor;

  /// 是否绘制悬浮投影（顶栏等贴边胶囊传 false，避免黑影）。
  final bool showShadow;

  /// **播放器弹层深色磨砂**变体（仅播放器内的弹出面板使用）。
  ///
  /// 587 由 585 纯白 → 586 暖白 → 深色磨砂。与顶/底栏同族的近黑叠色
  /// （65%）+ 白描边 + 重投影，**走与全局玻璃同一条折射管线**（
  /// `glassUi` 开启时是真·实时折射模糊，关闭时降级为实色深底），
  /// 白字由调用方配套。旧实现（浅色分支）在关闭玻璃时也强制浅底、
  /// 且不参与折射管线，反而与全局降级不一致且完全盖死磨砂。
  final bool popup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassEnabled = ref.watch(settingsProvider.select((s) => s.glassUi));
    // iOS 用更淡的默认着色（自定义 tint 不覆盖）→ 背景更透。
    final effectiveTint =
        tint == GlassConfig.panelTint ? GlassConfig.panelTintOf() : tint;

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        // 关闭玻璃时：弹层降级为实色深底，普通容器降级为 `fallbackColor`。
        color: glassEnabled
            ? null
            : (popup ? GlassConfig.playerPanelBase : fallbackColor),
        gradient: glassEnabled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // 弹层（587）：深色磨砂三段渐变；普通玻璃沿用叠色。
                colors: popup
                    ? const [
                        GlassConfig.playerPanelTop,
                        GlassConfig.playerPanelBase,
                        GlassConfig.playerPanelBottom,
                      ]
                    : [
                        Color.lerp(effectiveTint, Colors.white, 0.06)!,
                        effectiveTint,
                        effectiveTint.withValues(alpha: effectiveTint.a * 0.72),
                      ],
              )
            : null,
        borderRadius: borderRadius,
        // 普通玻璃开启时不加本层白描边：包折射管线自带菲涅尔高光边缘，
        // 双描边会压灰、破坏 Kyant 镜片观感；纯色降级态才需要边线定界。
        // 弹层是深底，必须靠亮描边定界，开关玻璃都保留。
        border: popup
            ? Border.all(color: GlassConfig.playerPanelRim)
            : (glassEnabled ? null : Border.all(color: GlassConfig.rimColor)),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );

    if (glassEnabled) {
      // 真折射液态玻璃底（liquid_glass_widgets）：磨砂/厚度/色散等
      // 由设置页滑杆经 GlassTheme 全局调节（见 glass_tuning.dart）；
      // 原「模糊+饱和 BackdropFilter」由包内折射管线取代。
      content = lg.GlassContainer(
        shape: lg.LiquidRoundedSuperellipse(
          borderRadius: borderRadius.topLeft.x,
        ),
        child: content,
      );
    }

    content = ClipRRect(borderRadius: borderRadius, child: content);

    // 悬浮投影画在裁剪层之外，避免被 ClipRRect 吃掉。
    // 弹层无论玻璃开关都要投影：深底浮在视频上靠投影分离层次。
    if ((glassEnabled || popup) && showShadow) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow:
              popup ? GlassConfig.playerPanelShadow : GlassConfig.panelShadow,
        ),
        child: content,
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
  }
}

/// 页面顶栏背景玻璃条，配合 `extendBodyBehindAppBar` 与透明 AppBar 使用。
///
/// 开启液态玻璃时走包内真折射管线；关闭后仍保留普通磨砂模糊
/// （[BackdropFilter] + 饱和度增强），与其他面板关闭后的纯色降级不同。
class GlassBackdrop extends ConsumerWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassEnabled = ref.watch(settingsProvider.select((s) => s.glassUi));

    Widget surface() => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassConfig.barTintOf(), GlassConfig.barTintSoftOf()],
            ),
            border: const Border(
              bottom: BorderSide(color: GlassConfig.rimColor, width: 1),
            ),
          ),
          child: const SizedBox.expand(),
        );

    if (!glassEnabled) {
      return ClipRect(
        child: BackdropFilter(
          filter: GlassConfig.filter(),
          child: surface(),
        ),
      );
    }

    return ClipRect(
      child: lg.GlassContainer(
        shape: const lg.LiquidRoundedSuperellipse(borderRadius: 0),
        child: surface(),
      ),
    );
  }
}

/// 面板高光描边：外圈亮线（顶部更亮、向下渐隐）+ 内圈暗线，模拟玻璃厚度折射。
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter(this.borderRadius);

  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // 外圈亮边
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [GlassConfig.highlightTop, GlassConfig.highlightBottom],
      ).createShader(rect);
    canvas.drawRRect(borderRadius.toRRect(rect).deflate(0.5), highlight);

    // 内圈玻璃厚度暗线
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = GlassConfig.innerRimColor;
    canvas.drawRRect(borderRadius.toRRect(rect).deflate(1.5), inner);
  }

  @override
  bool shouldRepaint(covariant GlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius;
}
