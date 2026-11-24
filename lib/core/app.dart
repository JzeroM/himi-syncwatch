import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/core/page_transitions.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/core/scroll_behavior.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/providers/tv_sync_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
import 'package:himi_syncwatch/widgets/trakt_deep_link_listener.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';
import 'package:himi_syncwatch/widgets/windows_global_hotkeys.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class HimiSyncApp extends ConsumerWidget {
  const HimiSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    // 698 N43：明暗三档（经典/深色/跟随系统）。
    final appearanceMode =
        ref.watch(settingsProvider.select((s) => s.appearanceMode));

    // 玻璃参数实时调节：设置页滑杆改值 → theme 重建 → 全部玻璃面更新
    final glassTuning = ref.watch(glassTuningProvider);
    // TV 端局域网同步常驻服务（tvMode 时启动 HTTP 配对/同步 + UDP 广播）
    ref.watch(tvSyncProvider);

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
          // 687：统一滚动手感——手机 iOS 式回弹、桌面 Clamping +
          // 鼠标可拖动 + 细滚动条（详见 HimiScrollBehavior）。
          scrollBehavior: const HimiScrollBehavior(),
          // TV 模式：焦点事件链上挂遥控器按键层（方向键滚动贯通 + OK 作用域落焦）
          // + directional 导航模式（Slider 只消费左右键，上下放行给焦点导航）
          builder: (context, child) {
            final subtree = child ?? const SizedBox.shrink();
            // 全平台统一 standard 玻璃路径（自带 RepaintBoundary 捕获）；
            // iOS 不再挂 premium 专用根层 AdaptiveLiquidGlassLayer。
            final modeSubtree =
                tvMode ? TvRemoteShell(child: subtree) : subtree;
            // 695：Windows 全局键（Space=暂停/播放、ESC=退全屏/返回/房间
            // 解散确认）——挂根部让任意 Flutter 页面都生效。
            // 698 N43：织物微粒噪点蒙层（全局细粒，明暗通用，玻璃折射
            // 穿出织纹质感）。
            return TraktDeepLinkListener(
              child: WindowsGlobalHotkeys(
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    modeSubtree,
                    const IgnorePointer(
                      child: CustomPaint(
                        painter: FabricWeavePainter(),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          themeMode: switch (appearanceMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system, // 698 N43：三档
          },
          theme: _buildHimiTheme(Brightness.light),
          darkTheme: _buildHimiTheme(Brightness.dark),
          routerConfig: router,
        ),
      ),
    );
  }

  /// 698 N43：明暗双套主题（seed 恒 #6366F1）——明主题前景语义色反转
  ///（onSurface 近黑、灰阶平移、AppBar/导航文字随明度），海报叠字恒白
  /// 由各图片层自管（不受此影响）。
  static ThemeData _buildHimiTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
            // 698 N10-A：全应用默认字体 MiSans（子集四字重，四端观感一致；
            // 生僻字回落系统字）。评分行/元数据行开 tnum 等宽数字见
            // [RatingsBadgeRow]/[_MetaRow]。
            fontFamily: 'MiSans',
            fontFamilyFallback: const [
              'PingFang SC',
              'HarmonyOS Sans SC',
              'Microsoft YaHei',
              'Noto Sans SC',
              'sans-serif',
            ],
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: brightness,
            ),
            scaffoldBackgroundColor:
                isDark ? const Color(0xFF0F1116) : const Color(0xFFF4F5F7),
            useMaterial3: true,
            // 687：页面转场——手机（含鸿蒙）iOS 横滑（比 Android 默认 Zoom
            // 自然），桌面淡入上移（不抢眼）。
            //
            // 697：改为运行时构建（见 [buildHimiPageTransitions]）——常量 map
            // 里写不了 `TargetPlatform.ohos`（stock SDK 无该枚举值），鸿蒙
            // 曾因此落到框架兜底的 Zoom 缩放。
            pageTransitionsTheme: buildHimiPageTransitions(),
            // 聚焦可见反馈（TV 遥控器导航：ListTile/Switch/IconButton 等）
            focusColor: const Color(0x886366F1),
            hoverColor: const Color(0x336366F1),
            // 顶栏玻璃条需透明，由各页 GlassBackdrop 提供模糊背景
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.transparent,
              // 698 N43：明主题前景反转（白 → 近黑）。
              foregroundColor: isDark ? Colors.white : const Color(0xFF1A1C1E),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: const Color(0x33FFFFFF),
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                ),
              ),
            ),
            // 弹层半透明近似（主题级，不加模糊以控制开销）
            dialogTheme: DialogThemeData(
              backgroundColor: isDark
                  ? const Color(0xF01A1D23)
                  : const Color(0xF7F4F5F7),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
                side: BorderSide(color: Color(0x33FFFFFF)),
              ),
            ),
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: isDark
                  ? const Color(0xF21A1D23)
                  : const Color(0xF9F4F5F7),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                side: BorderSide(color: Color(0x33FFFFFF)),
              ),
            ),
          );
  }
}
