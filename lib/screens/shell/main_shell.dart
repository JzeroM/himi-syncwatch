import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 四标签底部导航壳：首页 / Emby服务器 / 声网配置 / 设置。
///
/// 浮动玻璃胶囊导航，`extendBody` 让页面内容延伸到导航之下。
/// 壳层绘制主题色三段渐变背景（各标签页透明以透出）。
/// 仅首页：滑到底部时胶囊淡出隐藏，回滚立即恢复。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _navVisible = true;

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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    // 三键虚拟按键（≥40）：紧贴其上沿 +2，避免被遮挡又不留空隙；
    // 手势条（≤34，透明）或无安全区：贴近屏底保留少量空间
    final bottomGap = bottomInset >= 40
        ? bottomInset + 2
        : (bottomInset > 0 ? 6.0 : 4.0);

    // 主题色三段渐变（null 时保持应用底色）
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      extendBody: true,
      body: AnimatedContainer(
        key: const ValueKey('shellBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: widget.shell,
        ),
      ),
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
              child: GlassContainer(
                borderRadius: const BorderRadius.all(Radius.circular(28)),
                padding: EdgeInsets.zero,
                child: ShellNavBar(
                  currentIndex: widget.shell.currentIndex,
                  onSelect: (index) {
                    widget.shell.goBranch(
                      index,
                      initialLocation: index == widget.shell.currentIndex,
                    );
                    if (!_navVisible) setState(() => _navVisible = true);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
