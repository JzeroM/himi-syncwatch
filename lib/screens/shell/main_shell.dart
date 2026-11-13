import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/core/himi_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_back_intercept_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_visibility.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/shell/tv_top_nav_bar.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'package:himi_syncwatch/widgets/app_toast.dart';

/// 697：是否**真桌面平台**（Windows / macOS / Linux）。
///
/// 用于「侧边栏 vs 底部胶囊」的布局判定。
///
/// 【为什么不能只看宽度】旧实现是 `width >= 1000` 就上桌面侧边栏——
/// 鸿蒙平板横屏逻辑宽度普遍 1200+，装完直接是 Win 版布局（用户反馈）。
/// 移动平台（Android / iOS / 鸿蒙，含平板）应始终用手机布局。
bool get _isDesktopPlatform {
  if (HimiPlatform.isOhos) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

/// 四标签壳：首页 / Emby服务器 / 声网配置 / 设置。
///
/// - TV 模式（任意宽度）：顶部横排导航栏（遥控器左右键切换，常驻不隐藏）
/// - **桌面平台**且宽窗口（≥1000px）：左缘吊绳 + 百叶窗抽屉导航
/// - 移动平台（含平板）/ 窄窗口：浮动玻璃胶囊底部导航，滑到底部时胶囊淡出
///
/// 壳层绘制主题色三段渐变背景（各标签页透明以透出）。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();

  /// 手机端底部胶囊的底距（v1.1.84 再上移）：
  /// - 三键虚拟按键（inset≥40）：紧贴其上沿 +12
  /// - 手势条 / 无安全区：统一 20（v1.1.83 为 12，原 6 / 4）
  @visibleForTesting
  static double navBottomGap(double bottomInset) =>
      bottomInset >= 40 ? bottomInset + 12 : 20.0;
}

class _MainShellState extends ConsumerState<MainShell> {
  /// TV 模式双击返回退出的判定窗口。
  static const _exitBackWindow = Duration(seconds: 2);

  /// 上次在首页拦截返回的时刻（null = 当前没有待确认的返回）。
  DateTime? _backAt;

  bool _handleScroll(ScrollNotification notification) {
    // 仅竖向滚动响应显隐（横向海报栏滚到末端不应误隐藏导航）
    if (notification.metrics.axis != Axis.vertical) return false;
    // 仅窄窗口底部胶囊方案使用显隐（TV/桌面无底部导航）
    if (ref.read(settingsProvider).tvMode) return false;
    // 697：与 build 里的 isDesktop 判定保持一致（含平台判断），
    // 否则鸿蒙平板会出现「导航是底部胶囊、但不随滚动显隐」的错位。
    if (_isDesktopPlatform &&
        MediaQuery.sizeOf(context).width >= kShellDesktopBreakpoint) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;

    final nav = ref.read(shellNavVisibilityProvider.notifier);
    if (metrics.pixels >= metrics.maxScrollExtent - 8) {
      nav.hideFor(kShellNavHideScroll);
    } else if ((notification is ScrollUpdateNotification &&
            (notification.scrollDelta ?? 0) < 0) ||
        metrics.pixels < metrics.maxScrollExtent - 32) {
      nav.showFor(kShellNavHideScroll);
    }
    return false;
  }

  void _goBranch(int index) {
    // 切到其他 tab 时：源分支退回其首页（分支根路由），
    // 丢弃子页/弹层/未保存表单，保证下次切回落在该 tab 首页。
    if (index != widget.shell.currentIndex) {
      final source = widget.shell.route.branches[widget.shell.currentIndex];
      final nav = source.navigatorKey.currentState;
      // 643：仅在**真的能退栈**时才 popUntil。
      //
      // 真机根因（事件查看器 + himi_runtime.log 双证）：原实现无条件
      // `popUntil((r) => r.isFirst)`，紧接着 `widget.shell.goBranch(...)`
      // ——后者内部同样会退栈到分支根，于是**同一条路由被 complete 两次**
      // → `Bad state: Future already completed`（go_router
      // ImperativeRouteMatch.complete / Route.didComplete）。
      //
      // 若此时正处于播放页（PlayerScreen.dispose 中，视频纹理 / mpv ctx
      // 正在释放），该异常会**打断清理流程** → `flutter_windows.dll`
      // 访问违例（0xc0000005 @ 0x1551f）。三个引擎（MPV / MDK / media_kit）
      // 崩溃偏移完全一致，正是因为崩溃点在 Flutter 引擎的路由/纹理清理
      // 路径，与具体播放器无关——这也是 641「换引擎」无效的原因。
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      }
      ref.read(shellBranchEpochProvider.notifier).bump(widget.shell.currentIndex);
    }
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
    _backAt = null;
    ref.read(shellNavVisibilityProvider.notifier).reset();
  }

  /// TV 模式返回键策略：非首页标签 → 回首页；首页 → 2 秒内连按两次
  /// 退出到桌面（首按仅提示）。
  void _handleTvBack() {
    if (widget.shell.currentIndex != 0) {
      _goBranch(0);
      return;
    }
    final now = DateTime.now();
    final withinWindow =
        _backAt != null && now.difference(_backAt!) < _exitBackWindow;
    _backAt = now;
    if (withinWindow) {
      SystemNavigator.pop();
      return;
    }
    showAppToast(context, '再按一次返回退出应用', duration: Duration(seconds: 2));
  }

  /// 统一系统返回策略（TV / 非 TV 共用）：
  /// 0. 页面级拦截（如 Emby 页内联表单 / TV 布局模式）→ 优先消费
  /// 1. 当前分支 Navigator 还能弹（在子页）→ 弹子页，回父页
  /// 2. 在 tab 根页：非首页 → 回首页
  /// 3. 首页根页：TV 双击退出；非 TV 直接退桌面
  void _handleBack({required bool tvMode}) {
    // 0. 页面级拦截（Emby 内联表单、TV 布局模式等）→ 页面自行处理
    final intercept = ref.read(shellBackInterceptProvider);
    if (intercept != null && intercept()) return;
    // 1. 分支子页（设置子页、Emby 扫码、首页搜索等）→ 弹回父页
    final branch = widget.shell.route.branches[widget.shell.currentIndex];
    final navigator = branch.navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return;
    }
    // 2. tab 根页：非首页 → 回首页
    if (widget.shell.currentIndex != 0) {
      _goBranch(0);
      return;
    }
    // 3. 首页根页：TV 双击确认；非 TV 直接退出
    if (tvMode) {
      _handleTvBack();
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final shellBody = _buildShellBody(context);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        _handleBack(tvMode: tvMode);
      },
      child: shellBody,
    );
  }

  Widget _buildShellBody(BuildContext context) {
    final navVisible = ref.watch(shellNavVisibilityProvider);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // 胶囊底距上移（v1.1.84，见 MainShell.navBottomGap）：
    // 三键贴其上沿 +12；手势条/无安全区统一 20（原 6/4，太贴屏底）
    final bottomGap = MainShell.navBottomGap(bottomInset);

    // 主题色三段渐变（null 时保持应用底色）
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

    final gradientBg = AnimatedContainer(
      key: const ValueKey('shellBackground'),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: PosterPalette.pageGradient(accent, base),
      ),
    );

    final scrollable = NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: widget.shell,
    );

    // 697：桌面布局只给**真桌面平台**。
    //
    // 旧实现只看逻辑宽度（>= 1000）——鸿蒙平板横屏逻辑宽度普遍 1200+，
    // 直接落进桌面侧边栏布局（用户反馈「鸿蒙平板装完是 win 版布局」）。
    //
    // 现在按平台判定：只有 Windows / macOS / Linux 才可能用侧边栏；
    // Android / iOS / 鸿蒙（含平板）一律手机布局（底部胶囊），与手机一致。
    final isDesktop = _isDesktopPlatform &&
        MediaQuery.sizeOf(context).width >= kShellDesktopBreakpoint;

    // TV 模式优先于宽度断点：任意宽度都用顶部横排导航（遥控器友好），
    // 彻底避开高 DPI 电视盒子逻辑宽度不足 1000 而落入底部胶囊的问题
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    if (tvMode) {
      // TV 模式隐藏声网配置分支：若当前正停在该页（切换 TV 模式时
      // 恰好在声网页），顶栏已无对应入口 → 兜底回首页，避免"无选中项
      // 且无路可回"的死页。build 中不可直接导航，延迟到帧后执行。
      if (widget.shell.currentIndex == TvTopNavBar.hiddenAgoraIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              widget.shell.currentIndex == TvTopNavBar.hiddenAgoraIndex) {
            _goBranch(0);
          }
        });
      }
      return Scaffold(
        extendBody: true,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: gradientBg),
            Column(
              children: [
                TvTopNavBar(
                  currentIndex: widget.shell.currentIndex,
                  onSelect: _goBranch,
                ),
                Expanded(child: scrollable),
              ],
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      // 桌面：左右分栏抽屉导航（展开时内容右移不遮挡），无底部胶囊。
      // 渐变铺在最底层全宽，抽屉区与内容区共用同一张连续背景
      return Scaffold(
        extendBody: true,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: gradientBg),
            ShellDesktopLayout(
              content: scrollable,
              currentIndex: widget.shell.currentIndex,
              onSelect: _goBranch,
            ),
          ],
        ),
      );
    }

    final content = AnimatedContainer(
      key: const ValueKey('shellBackground'),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: PosterPalette.pageGradient(accent, base),
      ),
      child: scrollable,
    );

    return Scaffold(
      extendBody: true,
      // 标记页面内容为玻璃采样面（LiquidGlassScope 兜底，包内 GlassEffect
      // 在 Skia/Web 上采样此 RepaintBoundary；Impeller 不需要）。
      body: lg.GlassBackgroundSource(child: content),
      bottomNavigationBar: AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInCubic,
        offset: navVisible ? Offset.zero : const Offset(0, 1.5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: navVisible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !navVisible,
            child: Padding(
              key: const ValueKey('shellNavBarPadding'),
              padding: EdgeInsets.fromLTRB(12, 0, 12, bottomGap),
              child: ShellNavBar(
                currentIndex: widget.shell.currentIndex,
                onSelect: _goBranch,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
