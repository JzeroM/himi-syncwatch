import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/core/page_transitions.dart';
import 'package:himi_syncwatch/core/router.dart';
import 'package:himi_syncwatch/core/scroll_behavior.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
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
    // 698 N41：明暗三档 + 主题色（点缀 seed，未设回退蓝）。
    final appearanceMode =
        ref.watch(settingsProvider.select((s) => s.appearanceMode));
    final themeColor = ref.watch(settingsProvider.select((s) => s.themeColor));
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
            return TraktDeepLinkListener(
              child: WindowsGlobalHotkeys(child: modeSubtree),
            );
          },
          themeMode: switch (appearanceMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system, // 698 N41：三档——经典(明)/深色(暗)/跟随系统
          },
          theme: _buildHimiTheme(Brightness.light, themeColor),
          darkTheme: _buildHimiTheme(Brightness.dark, themeColor),
          routerConfig: router,
        ),
      ),
    );
  }

  /// 698 N41：明暗双套主题——seed = 主题色（未设回退标准蓝 #4A90D9，
  /// 点缀主层由此贯穿 Material 组件：开关/进度条/选中态/链接自动跟
  /// 点缀）。scaffold 平色底：深 #0F1116 / 浅 #F4F5F7（主题色退出背景）。
  static ThemeData _buildHimiTheme(Brightness brightness, int? themeColor) {
    final seed =
        themeColor != null ? Color(themeColor) : const Color(0xFF4A90D9);
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
              seedColor: seed,
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
            focusColor: seed.withValues(alpha: 0.53),
            hoverColor: seed.withValues(alpha: 0.2),
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
          );
  }
}
