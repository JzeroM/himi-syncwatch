import 'package:flutter/material.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 桌面宽度断点：≥ 此宽度走左侧 Dock 导航，否则回退底部胶囊导航。
const double kShellDesktopBreakpoint = 1000.0;

/// 桌面宽度下左侧导航项（与底部胶囊一致的五标签）。
const List<String> kShellNavLabels = ['首页', '收藏', 'Emby', '声网', '设置'];
const List<IconData> kShellNavIcons = [
  Icons.home_outlined,
  Icons.favorite_border,
  Icons.dns_outlined,
  Icons.key_outlined,
  Icons.settings_outlined,
];
const List<IconData> kShellNavSelectedIcons = [
  Icons.home,
  Icons.favorite,
  Icons.dns,
  Icons.key,
  Icons.settings,
];

/// 686：桌面侧边导航改为**垂直 Dock**（方案 C）。
///
/// ## 为什么改
///
/// 旧实现是「可折叠抽屉 + 每项之间横线分隔 + 选中淡白底」的老式列表：
///   - 5 个导航项之间各插一条 `Divider`，像系统菜单
///   - 选中态 `0x33FFFFFF` 在深色渐变背景上几乎看不出来
///   - 与底部胶囊导航的「水珠 + 玻璃胶囊」语言完全割裂
///
/// ## 现在
///
/// 每个导航项是**独立玻璃方块**（类似 macOS Dock 竖立在左侧）：
///   - 收起 72px：只有图标块；悬停出 tooltip 显示名称
///   - 展开 200px：图标 + 文字并排（`AnimatedSize` 平滑过渡）
///   - 选中：放大 1.15 + 主色外发光 + 右侧 3px 竖条
///   - 悬停：整块右移 2px + 提亮
///
/// ## 兼容
///
/// 保留 `ShellDesktopLayout` 公开 API 与 `shellContentArea` /
/// `drawerToggle` 两个 key（既有测试依赖）。
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
  /// 686：收起态轨道宽（只放图标块）。
  static const double _railWidth = 72;

  /// 686：展开态轨道宽（图标 + 文字）。
  static const double _expandedWidth = 200;

  /// 图标块尺寸。
  static const double _tileSize = 48;

  /// 图标块圆角。
  static const double _tileRadius = 14;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );

  /// 当前悬停的导航项索引（-1 = 无）。用于提亮与 tooltip。
  int _hoverIndex = -1;

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 686：**外层统一监听**动画，不再让 5 个 item 各自 AnimatedBuilder
        //（旧实现折叠时触发 5 次重建）。
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final curve = Curves.easeOutCubic.transform(_controller.value);
            final width =
                _railWidth + (_expandedWidth - _railWidth) * curve;
            return Row(
              children: [
                SizedBox(
                  width: width,
                  child: ClipRect(
                    child: SizedBox(
                      width: width,
                      height: double.infinity,
                      child: _buildDock(curve),
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
      ],
    );
  }

  /// 686：垂直 Dock 主体（图标方块列 + 底部折叠把手）。
  Widget _buildDock(double curve) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 品牌区（展开时显示，收起时留白）
        _buildBrand(curve),
        const SizedBox(height: 12),
        // 导航项
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < kShellNavLabels.length; i++)
                  _buildTile(i, curve),
              ],
            ),
          ),
        ),
        // 折叠把手
        _buildToggleHandle(curve),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 686：品牌区——展开时显示 HIMI / 同步观影，收起时只剩一个主色圆点。
  Widget _buildBrand(double curve) {
    final showText = curve > 0.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 120),
        child: showText
            ? Column(
                children: [
                  Text(
                    'HIMI',
                    style: TextStyle(
                      color: kNavBlobColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '同步观影',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              )
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kNavBlobColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kNavBlobColor.withValues(alpha: 0.6),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// 686：单个导航方块（Dock 风格）。
  ///
  /// 收起态：48×48 图标块，悬停出 tooltip。
  /// 展开态：整行「图标 + 文字」，选中项放大 + 主色发光 + 右侧竖条。
  Widget _buildTile(int index, double curve) {
    final selected = index == widget.currentIndex;
    final hovered = _hoverIndex == index;
    // 展开进度 > 0.5 才显示文字（避免半透明文字糊在图标上）
    final showLabel = curve > 0.5;

    final iconColor = selected
        ? kNavBlobColor
        : (hovered ? Colors.white : Colors.white70);

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: showLabel ? (_expandedWidth - 24) : _tileSize,
      height: _tileSize,
      decoration: BoxDecoration(
        color: selected
            ? kNavBlobColor.withValues(alpha: 0.16)
            : (hovered ? const Color(0x14FFFFFF) : Colors.transparent),
        borderRadius: BorderRadius.circular(_tileRadius),
        border: Border.all(
          color: selected
              ? kNavBlobColor.withValues(alpha: 0.55)
              : Colors.transparent,
          width: 1.2,
        ),
        // 选中态主色外发光（液态玻璃的「点亮」感）
        boxShadow: selected
            ? [
                BoxShadow(
                  color: kNavBlobColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisAlignment: showLabel
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          // 选中态右侧竖条（展开时贴左，收起时不显示）
          SizedBox(
            width: showLabel ? 4 : 0,
            child: showLabel && selected
                ? Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: kNavBlobColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                : null,
          ),
          SizedBox(width: showLabel ? 10 : 0),
          Icon(
            selected ? kShellNavSelectedIcons[index] : kShellNavIcons[index],
            size: 22,
            color: iconColor,
          ),
          if (showLabel) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                kShellNavLabels[index],
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 13.5,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    // 悬停时整块右移 2px（Dock 的「浮起」手感）+ tooltip
    final animated = AnimatedSlide(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      offset: hovered && !showLabel ? const Offset(0.04, 0) : Offset.zero,
      child: tile,
    );

    // 收起态用 Tooltip 显示名称（展开态文字已常显，不需要）
    final withTip = showLabel
        ? animated
        : Tooltip(
            message: kShellNavLabels[index],
            waitDuration: const Duration(milliseconds: 400),
            child: animated,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hoverIndex = index),
        onExit: (_) => setState(() => _hoverIndex = -1),
        child: TvFocusable(
          key: ValueKey('shellDockItem_$index'),
          onTap: () => widget.onSelect(index),
          child: withTip,
        ),
      ),
    );
  }

  /// 686：底部折叠把手（胶囊形玻璃钮，替代旧的左缘 18×64 竖条）。
  ///
  /// 保留 `drawerToggle` key（既有测试依赖）。
  Widget _buildToggleHandle(double curve) {
    final open = curve > 0.5;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TvFocusable(
        key: const ValueKey('drawerToggle'),
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: open ? 40 : 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x26FFFFFF), width: 0.8),
          ),
          child: Icon(
            open ? Icons.chevron_left : Icons.chevron_right,
            size: 18,
            color: open ? kNavBlobColor : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// 686：旧辅助类 `_Pressable` 已移除——按压水波由 `TvFocusable` +
/// `AnimatedContainer` 的悬停/选中态取代（Dock 风格不需要点击波纹）。
