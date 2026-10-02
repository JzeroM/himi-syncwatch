import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

class HimiSyncApp extends ConsumerWidget {
  const HimiSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    return MaterialApp.router(
      title: 'HIMI',
      debugShowCheckedModeBanner: false,
      // TV 模式：焦点事件链上挂遥控器按键层（方向键滚动贯通 + OK 作用域落焦）
      // + directional 导航模式（Slider 只消费左右键，上下放行给焦点导航）
      builder: (context, child) {
        final subtree = child ?? const SizedBox.shrink();
        return tvMode ? TvRemoteShell(child: subtree) : subtree;
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
    );
  }
}
