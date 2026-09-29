import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 四标签底部导航壳：首页 / Emby服务器 / 声网配置 / 设置。
///
/// 浮动玻璃胶囊导航，`extendBody` 让页面内容延伸到导航之下。
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: shell,
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 12),
        child: GlassContainer(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          padding: EdgeInsets.zero,
          child: NavigationBar(
            height: 68,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            indicatorColor: Colors.white24,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (index) {
              shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              );
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.dns_outlined),
                selectedIcon: Icon(Icons.dns),
                label: 'Emby服务器',
              ),
              NavigationDestination(
                icon: Icon(Icons.key_outlined),
                selectedIcon: Icon(Icons.key),
                label: '声网配置',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
