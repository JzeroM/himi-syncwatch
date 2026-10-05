import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 播放页左缘锁/解锁钮（同位置两形态）。
///
/// 位于画面左缘垂直居中，未锁显 `Icons.lock_open`（点击上锁），
/// 已锁显 `Icons.lock`（点击解锁）；显隐跟随控制栏（`_showControls`），
/// TV 模式由调用方通过 `PlayerScreen.showLockButton` 整体隐藏。
///
/// 纯参数 widget（不依赖 provider/状态），便于脱离 `mdk.Player` 单测
/// 两形态图标与回调。
class PlayerLockButton extends StatelessWidget {
  const PlayerLockButton({
    super.key,
    required this.locked,
    required this.onToggle,
  });

  final bool locked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: 14,
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(
          locked ? Icons.lock : Icons.lock_open,
          key: const ValueKey('playerLockButton'),
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
