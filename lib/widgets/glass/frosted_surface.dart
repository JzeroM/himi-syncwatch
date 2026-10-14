import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';

/// 白色毛玻璃面（模糊背景 + 白 60% 膜 + 深色字，v1.1.239）。
///
/// `ClipRect → BackdropFilter(blur) → 白色半透膜 → 深色细边 → 投影 → child`。
/// 背景模糊透出彩色色块；child 自动包深色文字 Theme——默认样式的
/// Text/Icon/Dropdown 等自动深色可读，调用方无需逐处改色。
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

  /// 白玻璃面内的深色文字/图标 Theme（纯派生，供测试）。
  /// 白 60% 膜上深色字才可读；调用方显式写死的浅色需自行改为主题色。
  static ThemeData darkContentTheme(ThemeData base) => base.copyWith(
        textTheme: base.textTheme.apply(
          bodyColor: darkInk,
          displayColor: darkInk,
        ),
        iconTheme: base.iconTheme.copyWith(color: darkInk),
        colorScheme: base.colorScheme.copyWith(
          onSurface: darkInk,
        ),
      );

  /// 白玻璃内容深墨色（与 [darkContentTheme] 的 onSurface 同源）。
  /// GlassContainer/FrostedSurface 的**构建方** context 位于包装 Theme
  /// 之上（真实 App 暗色主题下 onSurface 仍是白）——这些调用点必须用
  /// 本常量，不能用 `Theme.of(context)`。
  static const Color darkInk = Color(0xE6000000);

  /// [darkInk] 指定不透明度（如 0.54 ≈ secondary、0.70 ≈ 中强）。
  static Color darkInkWith(double opacity) => darkInk.withValues(alpha: opacity);

  @override
  Widget build(BuildContext context) {
    // 背景色用 ColoredBox 而非带色 DecoratedBox：面板内常见 ListTile，
    // Flutter 断言「带 bg 的 ColoredBox/DecoratedBox 包 ListTile 会遮住
    // 背景/墨水」——透明 Material 在着色层内兜底解决。
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
            // 深字 Theme + 透明 Material 兜底：前者让默认样式文字/图标
            // 在白膜上可读；后者满足 ListTile 对最近 Material 祖先的断言。
            child: Theme(
              data: darkContentTheme(Theme.of(context)),
              child: Material(
                type: MaterialType.transparency,
                child: child,
              ),
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
