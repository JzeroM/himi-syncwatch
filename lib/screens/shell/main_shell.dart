import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/screens/shell/tv_top_nav_bar.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

/// 四标签壳：首页 / Emby服务器 / 声网配置 / 设置。
///
/// - TV 模式（任意宽度）：顶部横排导航栏（遥控器左右键切换，常驻不隐藏）
/// - 宽窗口（≥1000px，桌面）：左缘吊绳 + 百叶窗抽屉导航
/// - 窄窗口（手机/小窗）：浮动玻璃胶囊底部导航，滑到底部时胶囊淡出
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
  bool _navVisible = true;

  /// TV 模式双击返回退出的判定窗口。
  static const _exitBackWindow = Duration(seconds: 2);

  /// 上次在首页拦截返回的时刻（null = 当前没有待确认的返回）。
  DateTime? _backAt;

  bool _handleScroll(ScrollNotification notification) {
    // 仅首页标签响应滚动显隐
    if (widget.shell.currentIndex != 0) return false;
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) return false;

    if (metrics.pixels >= metrics.maxScrollExtent - 8) {
      if (_navVisible) setState(() => _navVisible = false);
    } else if ((notification is ScrollUpdateNotification &&
            (notification.scrollDelta ?? 0) < 0) ||
        metrics.pixels < metrics.maxScrollExtent - 32) {
      if (!_navVisible) setState(() => _navVisible = true);
    }
    return false;
  }

  void _goBranch(int index) {
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
    _backAt = null;
    if (!_navVisible) setState(() => _navVisible = true);
  }

  /// TV 模式返回键策略：非首页标签 → 回首页；首页 → 2 秒内连按两次
  /// 退出到桌面（首按仅提示）。非 TV 模式不拦截（保持平台默认）。
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('再按一次返回退出应用'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shellBody = _buildShellBody(context);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    if (!tvMode) return shellBody;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        _handleTvBack();
      },
      child: shellBody,
    );
  }

  Widget _buildShellBody(BuildContext context) {
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

    final isDesktop =
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
        offset: _navVisible ? Offset.zero : const Offset(0, 1.5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _navVisible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !_navVisible,
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
