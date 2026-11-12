import 'package:flutter/material.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
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

/// 687：桌面侧边导航 —— **玻璃 Dock**。
///
/// ## 视觉
///
/// 整条侧边栏包在一整块**大圆角玻璃**里（[GlassContainer]，与底部胶囊
/// 导航同一套液态玻璃管线；设置里关掉玻璃 UI 时自动降级为半透明纯色）。
///
/// 内部每个导航项：
///   - 未选中：极淡玻璃，悬停时提亮 + 图标上浮放大
///   - 选中：主色渐变玻璃 + 外发光 + 顶部内高光（玻璃「厚度」感）
///
/// 选中指示器是一条**竖向光条**，切换时用 [AnimatedPositioned] 平滑
/// 滑到新位置（不是瞬间消失出现）。
///
/// 收起态（72px）当前页图标下方有一枚**主色呼吸圆点**。
///
/// ## 为什么用信号而非换 key 重置
///
/// 见 [AgoraGuideBook] 的同款教训：换 key 会销毁重建整棵子树。
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
  /// 收起态轨道宽（只放图标块）。
  static const double _railWidth = 72;

  /// 展开态轨道宽（图标 + 文字）。
  static const double _expandedWidth = 200;

  /// 图标块尺寸。
  static const double _tileSize = 48;

  /// 图标块圆角。
  static const double _tileRadius = 14;

  /// 687：导航项按语义分两组（首页/收藏 | Emby/声网/设置），
  /// 组间留空隙代替横线分隔。
  static const int _groupSplitAfter = 1;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );

  /// 当前悬停的导航项索引（-1 = 无）。
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
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final curve = Curves.easeOutCubic.transform(_controller.value);
            final width = _railWidth + (_expandedWidth - _railWidth) * curve;
            return Row(
              children: [
                SizedBox(
                  width: width,
                  child: Padding(
                    // 687：整块玻璃与屏幕边缘留一点呼吸空间。
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    child: _buildGlassShell(width, curve),
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

  /// 687：整条侧边栏包在**一整块大圆角玻璃**里。
  ///
  /// 复用 [GlassContainer] → 自动跟随设置里的「液态玻璃」开关
  /// （关闭后降级为半透明纯色 + 白描边，不会变成不透明色块）。
  Widget _buildGlassShell(double width, double curve) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(20),
      tint: const Color(0x12FFFFFF),
      showShadow: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _buildDock(curve),
      ),
    );
  }

  /// 垂直 Dock 主体（品牌 + 导航方块列 + 折叠把手）。
  ///
  /// 687：选中指示光条用 [Stack] 叠在导航列左侧，`AnimatedPositioned`
  /// 平滑滑动到当前项——不是瞬间消失出现。
  Widget _buildDock(double curve) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildBrand(curve),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 每个导航项占「方块 48 + 上下 padding 3*2」= 54，
              // 再加分组空隙；据此算指示光条的 y。
              const itemExtent = _tileSize + 6;
              final splitGap = 10.0;
              var y = 0.0;
              for (var i = 0; i < widget.currentIndex; i++) {
                y += itemExtent;
                if (i == _groupSplitAfter) y += splitGap;
              }
              // 光条在方块内垂直居中：方块高 48，光条高 24 → 偏移 12
              final barTop = y + 3 + (_tileSize - 24) / 2;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < kShellNavLabels.length; i++) ...[
                          _buildTile(i, curve),
                          if (i == _groupSplitAfter) SizedBox(height: splitGap),
                        ],
                      ],
                    ),
                  ),
                  // 展开态才显示左侧光条（收起态用图标下方圆点）
                  if (curve > 0.5)
                    DockIndicatorBar(
                      top: barTop,
                      visible: widget.currentIndex >= 0,
                    ),
                ],
              );
            },
          ),
        ),
        _buildToggleHandle(curve),
        const SizedBox(height: 14),
      ],
    );
  }

  /// 687：品牌区——展开显示「HIMI / 同步观影」，收起显示**单字母 H**。
  ///
  /// 【为什么收起用单字母】旧实现是一个 10px 小圆点，辨识度太低；
  /// 单字母 H 在 72px 轨道里既有品牌感又不占空间。
  Widget _buildBrand(double curve) {
    final showText = curve > 0.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 2),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: showText
            ? Column(
                key: const ValueKey('brandFull'),
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
                key: const ValueKey('brandLetter'),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kNavBlobColor.withValues(alpha: 0.30),
                      kNavBlobColor.withValues(alpha: 0.10),
                    ],
                  ),
                  border: Border.all(
                    color: kNavBlobColor.withValues(alpha: 0.45),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kNavBlobColor.withValues(alpha: 0.28),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Text(
                  'H',
                  style: TextStyle(
                    color: kNavBlobColor,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }

  /// 687：单个导航方块（玻璃 + 选中发光 + 悬停浮起）。
  Widget _buildTile(int index, double curve) {
    final selected = index == widget.currentIndex;
    final hovered = _hoverIndex == index;
    final showLabel = curve > 0.5;

    final iconColor = selected
        ? kNavBlobColor
        : (hovered ? Colors.white : Colors.white70);

    // ── 底色：选中主色渐变玻璃 / 悬停淡玻璃 / 常态透明 ──
    final BoxDecoration decoration;
    if (selected) {
      decoration = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kNavBlobColor.withValues(alpha: 0.28),
            kNavBlobColor.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(_tileRadius),
        border: Border.all(
          color: kNavBlobColor.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          // 外发光
          BoxShadow(
            color: kNavBlobColor.withValues(alpha: 0.30),
            blurRadius: 16,
            spreadRadius: 1,
          ),
          // 内高光：顶部一条亮线，制造玻璃「厚度」感
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.10),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      );
    } else if (hovered) {
      decoration = BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(_tileRadius),
        border: Border.all(
          color: const Color(0x22FFFFFF),
          width: 1,
        ),
      );
    } else {
      decoration = BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_tileRadius),
      );
    }

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: showLabel ? (_expandedWidth - 28) : _tileSize,
      height: _tileSize,
      decoration: decoration,
      child: Row(
        mainAxisAlignment: showLabel
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          SizedBox(width: showLabel ? 10 : 0),
          // 687：图标悬停浮起 + 放大（Dock 磁吸感）
          AnimatedSlide(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            offset: hovered ? const Offset(0, -0.04) : Offset.zero,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              scale: hovered ? 1.08 : 1.0,
              child: Icon(
                selected
                    ? kShellNavSelectedIcons[index]
                    : kShellNavIcons[index],
                size: 22,
                color: iconColor,
              ),
            ),
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

    // 收起态：当前页图标下方一枚主色呼吸圆点
    final dot = (!showLabel && selected)
        ? Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: kNavBlobColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kNavBlobColor.withValues(alpha: 0.8),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [tile, dot],
    );

    // 收起态用 Tooltip 显示名称（展开态文字已常显）
    final withTip = showLabel
        ? column
        : Tooltip(
            message: kShellNavLabels[index],
            waitDuration: const Duration(milliseconds: 400),
            child: column,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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

  /// 687：底部折叠把手（圆角短横线，悬停展开成圆形按钮）。
  ///
  /// 保留 `drawerToggle` key（既有测试依赖）。
  Widget _buildToggleHandle(double curve) {
    final open = curve > 0.5;
    final hovered = _hoverIndex == -2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoverIndex = -2),
      onExit: (_) => setState(() => _hoverIndex = -1),
      child: TvFocusable(
        key: const ValueKey('drawerToggle'),
        onTap: _toggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          // 常态是一条 32×4 短横线；悬停/展开时变成 36×36 圆形按钮
          width: (hovered || open) ? 36 : 32,
          height: (hovered || open) ? 36 : 4,
          decoration: BoxDecoration(
            color: (hovered || open)
                ? const Color(0x1AFFFFFF)
                : const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(18),
            border: (hovered || open)
                ? Border.all(color: const Color(0x26FFFFFF), width: 0.8)
                : null,
          ),
          child: (hovered || open)
              ? Icon(
                  open ? Icons.chevron_left : Icons.chevron_right,
                  size: 18,
                  color: open ? kNavBlobColor : Colors.white70,
                )
              : null,
        ),
      ),
    );
  }
}

/// 687：选中指示器光条（展开态贴左侧的竖向渐变条）。
///
/// 用 [AnimatedPositioned] 在切换时平滑滑动到新位置——不是瞬间消失出现。
/// 由 [_ShellDesktopLayoutState] 计算目标 y 坐标后传入。
class DockIndicatorBar extends StatelessWidget {
  const DockIndicatorBar({
    super.key,
    required this.top,
    required this.visible,
  });

  final double top;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      left: 0,
      top: top,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: Container(
          width: 3,
          height: 24,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                kNavBlobColor.withValues(alpha: 0.95),
                kNavBlobColor.withValues(alpha: 0.45),
              ],
            ),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(2),
            ),
            boxShadow: [
              BoxShadow(
                color: kNavBlobColor.withValues(alpha: 0.55),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 687：旧辅助类 `_Pressable` 已移除——按压水波由 `TvFocusable` +
/// `AnimatedContainer` 的悬停/选中态取代（Dock 风格不需要点击波纹）。
