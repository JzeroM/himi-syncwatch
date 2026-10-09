import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 面板滚动行为：默认拖动设备只含 touch/stylus/trackpad（**不含 mouse**，
/// 桌面端鼠标按下拖动列表不滚动），内容超视口时表现为「滚不动、显示
/// 不全」。显式加 mouse；面板无文本选择需求，不受该默认限制影响。
class _PanelScrollBehavior extends ScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices =>
      {...super.dragDevices, PointerDeviceKind.mouse};
}

/// 右侧浮层选择面板：玻璃卡片（GlassContainer 透明玻璃，关闭时降级
/// 深色纯色）+ 顶部标题 + 可上下滚动的选项列表。
///
/// 字幕/音轨/倍速三个选择器共用容器；选项行由 [SideOptionRow] 提供
/// （文字左对齐、选中右侧对勾）。面板区域拦截点击，防止冒泡到
/// 视频区触发「点屏收起控制条」。
class SelectorSidePanel extends StatelessWidget {
  const SelectorSidePanel({
    super.key,
    required this.title,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  /// 面板标题（「字幕」/「音轨」/「倍速」）。
  final String title;

  /// 选项列表（通常为 ListView，超长自动滚动）。
  final Widget child;

  /// 玻璃卡片圆角；全高贴边的选集面板把右侧圆角放平。
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: GlassContainer(
        borderRadius: borderRadius,
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ScrollConfiguration(
                behavior: _PanelScrollBehavior(),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板选项行：文字左对齐（选中主色加粗），右侧选中对勾；
/// TV 遥控可聚焦（焦点环 + Enter 选择），触摸行为不变。
class SideOptionRow extends StatelessWidget {
  const SideOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  /// 外部焦点节点（TV 打开面板后精确落焦选中行；由调用方持有）。
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      radius: 6,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? const Color(0xFF6366F1) : Colors.white,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // 未选中占空位，保证各行文字/对勾对齐
            SizedBox(
              width: 18,
              child: selected
                  ? const Icon(Icons.check, color: Color(0xFF6366F1), size: 18)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
