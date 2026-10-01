import 'package:flutter/material.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

/// 桌面宽度断点：≥ 此宽度走左侧分栏抽屉导航，否则回退底部胶囊导航。
const double kShellDesktopBreakpoint = 1000.0;

/// 桌面宽度下左侧导航项（与底部胶囊一致的四标签）。
const List<String> kShellNavLabels = ['首页', 'Emby服务器', '声网配置', '设置'];
const List<IconData> kShellNavIcons = [
  Icons.home_outlined,
  Icons.dns_outlined,
  Icons.key_outlined,
  Icons.settings_outlined,
];
const List<IconData> kShellNavSelectedIcons = [
  Icons.home,
  Icons.dns,
  Icons.key,
  Icons.settings,
];

/// 桌面左右分栏布局：左抽屉（宽度动画 0↔240）+ 右主内容（实时 reflow）。
///
/// - 汉堡按钮固定在左上角，点击开合；展开时图标切换为关闭
/// - 抽屉展开时主内容区整体右移，**无遮挡、无遮罩**
/// - 点导航项只切换分支，抽屉保持展开（手动收回：仅点汉堡收起）
class ShellDesktopLayout extends StatefulWidget {
  const ShellDesktopLayout({
    super.key,
    required this.content,
    required this.currentIndex,
    required this.onSelect,
  });

  final Widget content;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  State<ShellDesktopLayout> createState() => _ShellDesktopLayoutState();
}

class _ShellDesktopLayoutState extends State<ShellDesktopLayout>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 240;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _expanded =>
      _controller.status == AnimationStatus.forward ||
      _controller.status == AnimationStatus.completed;

  void _toggle() {
    if (_expanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  /// 第 i 个导航项的淡入进度（0..1），交错出现。
  double _itemProgress(int index) {
    final start = 0.18 + index * 0.09;
    final interval =
        Interval(start, (start + 0.45).clamp(0.0, 1.0), curve: Curves.easeOut);
    return interval.transform(_controller.value);
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(56, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HIMI',
            style: TextStyle(
              color: kNavBlobColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 2),
          Text(
            '同步观影',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(int index) {
    final selected = index == widget.currentIndex;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _itemProgress(index);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset((1 - t) * -16, 0),
            child: _Pressable(
              onTap: () => widget.onSelect(index),
              child: Container(
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: selected ? const Color(0x33FFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? kShellNavSelectedIcons[index]
                          : kShellNavIcons[index],
                      size: 21,
                      color: selected ? kNavBlobColor : Colors.white70,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        kShellNavLabels[index],
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF01A1D23),
        border: Border(right: BorderSide(color: Color(0x33FFFFFF))),
        boxShadow: [
          BoxShadow(color: Colors.black38, blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Colors.white10),
          for (var i = 0; i < kShellNavLabels.length; i++) ...[
            _buildItem(i),
            if (i < kShellNavLabels.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(height: 1, color: Colors.white10),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return Positioned(
      left: 8,
      top: MediaQuery.viewPaddingOf(context).top + 6,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const ValueKey('drawerToggle'),
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final open = _expanded;
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x66000000),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Icon(
                  open ? Icons.close : Icons.menu,
                  size: 22,
                  color: open ? kNavBlobColor : Colors.white70,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final curve =
                Curves.easeOutCubic.transform(_controller.value);
            final width = _panelWidth * curve;
            return Row(
              children: [
                SizedBox(
                  width: width,
                  child: width <= 0.5
                      ? const SizedBox.shrink()
                      : ClipRect(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: _panelWidth,
                              height: double.infinity,
                              child: _buildDrawer(),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('shellContentArea'),
                    child: widget.content,
                  ),
                ),
              ],
            );
          },
        ),
        _buildToggleButton(),
      ],
    );
  }
}

/// 简单按压水波（不依赖 Scaffold Material）。
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed ? const Color(0x14FFFFFF) : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}
