import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';

/// 液态玻璃面板。
///
/// 开启时：背景模糊 + 饱和增强 + 半透明着色 + 高光描边；
/// 设置中关闭 `glassUi` 后降级为不透明纯色，不产生 BackdropFilter 开销。
class GlassContainer extends ConsumerWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius =
        const BorderRadius.all(Radius.circular(20)),
    this.tint = GlassConfig.panelTint,
    this.blurSigma = GlassConfig.blurSigma,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final Color tint;
  final double blurSigma;

  /// 是否绘制悬浮投影（顶栏等贴边胶囊传 false，避免黑影）。
  final bool showShadow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassEnabled =
        ref.watch(settingsProvider.select((s) => s.glassUi));

    Widget content = DecoratedBox(
      decoration: BoxDecoration(
        color: glassEnabled ? null : GlassConfig.fallbackColor,
        gradient: glassEnabled
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(tint, Colors.white, 0.06)!,
                  tint,
                  tint.withValues(alpha: tint.a * 0.72),
                ],
              )
            : null,
        borderRadius: borderRadius,
        border: Border.all(color: GlassConfig.rimColor, width: 1),
      ),
      child: CustomPaint(
        foregroundPainter:
            glassEnabled ? GlassRimPainter(borderRadius) : null,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );

    if (glassEnabled) {
      content = BackdropFilter(
        filter: GlassConfig.filter(sigma: blurSigma),
        child: content,
      );
    }

    content = ClipRRect(borderRadius: borderRadius, child: content);

    // 悬浮投影画在裁剪层之外，避免被 ClipRRect 吃掉
    if (glassEnabled && showShadow) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: GlassConfig.panelShadow,
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
class GlassBackdrop extends ConsumerWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassEnabled =
        ref.watch(settingsProvider.select((s) => s.glassUi));

    if (!glassEnabled) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: GlassConfig.fallbackColor),
        child: SizedBox.expand(),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: GlassConfig.filter(),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [GlassConfig.barTint, GlassConfig.barTintSoft],
            ),
            border: Border(
              bottom: BorderSide(color: GlassConfig.rimColor, width: 1),
            ),
          ),
          child: SizedBox.expand(),
        ),
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
