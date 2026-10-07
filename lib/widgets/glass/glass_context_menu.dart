import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 玻璃浮层菜单里的一个选项。
class GlassMenuAction {
  const GlassMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// 选中回调（菜单先关闭再执行）。
  final VoidCallback onTap;

  /// 危险项（移除/取消收藏等，红字提示）。
  final bool destructive;
}

/// 锚定卡片的液态玻璃上下文菜单（长按触发）。
///
/// - 锚点 [anchor] 为卡片全局矩形；优先弹在卡片下方，空间不足则上方；
/// - [GlassContainer] 玻璃底 + 选项行 `TvFocusable`（TV 首行落焦、返回归还）；
/// - `barrierDismissible` 点外部关闭。
Future<void> showGlassContextMenu(
  BuildContext context, {
  required Rect anchor,
  required List<GlassMenuAction> actions,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    barrierColor: Colors.black.withValues(alpha: 0.30),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, _, __) {
      final screen = MediaQuery.sizeOf(dialogContext);
      const width = 208.0;
      var left = anchor.left;
      if (left + width > screen.width - 12) left = screen.width - 12 - width;
      if (left < 12) left = 12;

      final height = actions.length * 48.0 + 12;
      final showBelow = anchor.bottom + 8 + height <= screen.height - 12;
      final top = showBelow ? anchor.bottom + 8 : null;
      final bottom = showBelow ? null : (screen.height - anchor.top + 8);

      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            bottom: bottom,
            width: width,
            child: Material(
              type: MaterialType.transparency,
              child: GlassContainer(
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++)
                      _GlassMenuRow(
                        action: actions[i],
                        autofocus: i == 0,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _GlassMenuRow extends StatelessWidget {
  const _GlassMenuRow({required this.action, required this.autofocus});

  final GlassMenuAction action;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? const Color(0xFFFF7A7A) : Colors.white;
    return TvFocusable(
      autofocus: autofocus,
      radius: 12,
      scale: 1.0,
      onTap: () {
        Navigator.of(context).pop();
        action.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(action.icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(color: color, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
