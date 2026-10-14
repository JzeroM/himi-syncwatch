import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';

/// 中等磨砂毛玻璃面（无色调深色磨砂）。
///
/// `ClipRect → BackdropFilter(blur) → 深色半透明底 → 白描边 → 投影 → child`。
/// 模糊背景只见色块、文字绝对可读；用于弹出面板与 glassUi 关闭后的降级面。
/// BackdropFilter 必须被 ClipRect 限定，否则模糊整屏、开销失控。
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.sigma = GlassConfig.frostedSigma,
    this.tint = GlassConfig.frostedTint,
    this.padding,
    this.showBorder = true,
    this.showShadow = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double sigma;
  final Color tint;
  final EdgeInsetsGeometry? padding;
  final bool showBorder;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    // 背景色用 ColoredBox 而非带色 DecoratedBox：面板内常见 ListTile，
    // Flutter 断言「带 bg 的 DecoratedBox 包 ListTile 会遮住背景/墨水」。
    Widget content = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: ColoredBox(
        color: tint,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: showBorder
                ? Border.all(color: GlassConfig.frostedBorder)
                : null,
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            // 透明 Material 兜底：面板内常见 ListTile，其断言要求最近
            // Material 祖先在着色层内，否则 ink/背景被上层色块遮住报错。
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ),
      ),
    );

    content = ClipRRect(borderRadius: borderRadius, child: content);

    if (showShadow) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: GlassConfig.panelShadow,
        ),
        child: content,
      );
    }
    return content;
  }
}

/// 毛玻璃居中弹窗（替代裸 `showDialog` + 深色 `AlertDialog`）。
///
/// 外层 Dialog 透明，内容套 [FrostedSurface]；`builder` 返回弹窗主体
/// （通常是一列文字/按钮，不要自带不透明底色）。
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: FrostedSurface(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: builder(ctx),
      ),
    ),
  );
}

/// 毛玻璃底部弹层（替代裸 `showModalBottomSheet` + 深色底）。
///
/// 外层 sheet 透明，内容套顶部圆角 [FrostedSurface]。
Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool useSafeArea = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    builder: (ctx) => FrostedSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      showShadow: false,
      padding: const EdgeInsets.only(top: 8),
      child: builder(ctx),
    ),
  );
}
