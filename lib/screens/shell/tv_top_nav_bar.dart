import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_side_drawer.dart';
import 'package:himi_syncwatch/widgets/media_search_button.dart';
import 'package:himi_syncwatch/widgets/room_menu_button.dart';
import 'package:himi_syncwatch/widgets/server_title_dropdown.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// TV 模式专属顶部横排导航栏（固定常驻，不随滚动隐藏）。
///
/// 形态：通栏玻璃条，左侧服务器标题胶囊（合并首页入口：
/// 名称 OK 回首页，▾ OK 打开服务器下拉），右侧依次
/// 搜索 / 房间 / 三个横排导航项（首页已并入标题，故从 index 1 起）；
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
            // 标题占满剩余空间的左对齐区：空间不足时内部省略号收缩，
            // 右侧按钮与导航项始终贴右
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: ServerTitleDropdown(
                    onTitleTap: () => onSelect(0),
                  ),
                ),
              ),
            ),
            const MediaSearchButton(),
            const RoomMenuButton(),
            for (var i = 1; i < kShellNavLabels.length; i++)
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
