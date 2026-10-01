import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// TV 模式专属顶部横排导航栏（固定常驻，不随滚动隐藏）。
///
/// 形态：通栏玻璃条，左侧 HIMI 标题，右侧四个横排导航项；
/// 每项 [TvFocusable] 获得 D-pad 焦点，左右键切换、OK 进入。
/// 复用壳层导航数据（kShellNavLabels/Icons/SelectedIcons）与薄荷青选中色。
class TvTopNavBar extends StatelessWidget {
  const TvTopNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.viewPaddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: const BoxDecoration(
        color: Color(0x0AFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0x26FFFFFF))),
      ),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 24, right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HIMI',
                    style: TextStyle(
                      color: kNavBlobColor,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    '同步观影',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Spacer(),
            for (var i = 0; i < kShellNavLabels.length; i++)
              _TvTopNavItem(
                index: i,
                selected: i == currentIndex,
                onTap: () => onSelect(i),
              ),
            const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

class _TvTopNavItem extends StatelessWidget {
  const _TvTopNavItem({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? kNavBlobColor : Colors.white70;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: TvFocusable(
        radius: 12,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0x33FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? kShellNavSelectedIcons[index]
                    : kShellNavIcons[index],
                size: 20,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                kShellNavLabels[index],
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
