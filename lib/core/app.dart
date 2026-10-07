import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class HimiSyncApp extends ConsumerWidget {
  const HimiSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    // 玻璃参数实时调节：设置页滑杆改值 → theme 重建 → 全部玻璃面更新
    final glassTuning = ref.watch(glassTuningProvider);

    return LiquidGlassWidgets.wrap(
      // MaterialApp 必须桥接 ThemeMode 亮度，否则 OS 深浅色与
      // 应用主题不一致时玻璃描边/投影会消失（包文档要求）。
      brightnessResolver: Theme.maybeBrightnessOf,
      theme: glassTuning.toThemeData(),
      // Skia/Web 兜底：给包内 GlassEffect 提供背景采样键（Impeller 不需要）。
      child: LiquidGlassScope(
        child: MaterialApp.router(
          title: 'HIMI',
          debugShowCheckedModeBanner: false,
          // TV 模式：焦点事件链上挂遥控器按键层（方向键滚动贯通 + OK 作用域落焦）
          // + directional 导航模式（Slider 只消费左右键，上下放行给焦点导航）
          builder: (context, child) {
            final subtree = child ?? const SizedBox.shrink();
            // iOS premium（Impeller）的 grouped 玻璃（GlassContainer /
            // GlassBackdrop 默认 useOwnLayer=false）依赖祖先 LiquidGlassLayer
            // 提供背景采样；缺失时降级为不透明纯色灰（顶栏/卡片/导航全部变灰）。
            // AdaptiveLiquidGlassLayer 同时建立 LiquidGlassLayer + 背景
            // BackdropGroup 并向下继承 quality，是包内推荐的 premium 根层。
            // 置于 MaterialApp.builder 内以拿到应用 Theme（亮度解析）。
            final content = tvMode ? TvRemoteShell(child: subtree) : subtree;
            return defaultTargetPlatform == TargetPlatform.iOS
                ? AdaptiveLiquidGlassLayer(child: content)
                : content;
          },
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            // 聚焦可见反馈（TV 遥控器导航：ListTile/Switch/IconButton 等）
            focusColor: const Color(0x886366F1),
            hoverColor: const Color(0x336366F1),
            // 顶栏玻璃条需透明，由各页 GlassBackdrop 提供模糊背景
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: Color(0x33FFFFFF),
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
            // 弹层半透明近似（主题级，不加模糊以控制开销）
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xF01A1D23),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
                side: BorderSide(color: Color(0x33FFFFFF)),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Color(0xF21A1D23),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                side: BorderSide(color: Color(0x33FFFFFF)),
              ),
            ),
          ),
          routerConfig: router,
        ),
      ),
    );
  }
}
