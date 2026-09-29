import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 四标签底部导航壳：首页 / Emby服务器 / 声网配置 / 设置。
///
/// 浮动玻璃胶囊导航，`extendBody` 让页面内容延伸到导航之下。
/// 仅首页：滑到底部时胶囊淡出隐藏，回滚立即恢复。
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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

    return Scaffold(
      extendBody: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: widget.shell,
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
