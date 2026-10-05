import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 播放页顶栏：返回 + 左上角影视信息 + 网速 + 解码胶囊 + 分享 + 锁。
///
/// 纯参数 widget（不依赖 provider/状态），便于脱离 `mdk.Player` 单测
/// 标题格式化回显、网速显隐与锁定回调。渐变底与内边距沿用原
/// `_buildTopBar` 样式。
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.networkSpeedText,
    required this.showDecodeButton,
    required this.decodeModeLabel,
    required this.decodeMenuOpen,
    required this.showShare,
    required this.locked,
    required this.onBack,
    required this.onToggleDecode,
    required this.onShare,
    required this.onToggleLock,
  });

  /// 左上角影视信息（电影名 / `剧名 – S01E02`）；空串不渲染。
  final String title;

  /// 网速回显（如 `12.34 Mbps`）；null = 设置关闭不渲染。
  final String? networkSpeedText;

  final bool showDecodeButton;
  final String decodeModeLabel;
  final bool decodeMenuOpen;
  final bool showShare;
  final bool locked;

  final VoidCallback onBack;
  final VoidCallback onToggleDecode;
  final VoidCallback onShare;
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 12,
        right: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('playerBackButton'),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onBack,
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                key: const ValueKey('playerTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (networkSpeedText != null) ...[
            Text(
              networkSpeedText!,
              key: const ValueKey('playerNetworkSpeed'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 8),
          ],
          // 解码模式按钮（TV 隐藏：解码模式仅走设置页切换）
          if (showDecodeButton) ...[
            TvFocusable(
              radius: 12,
              onTap: onToggleDecode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: decodeMenuOpen
                      ? const Color(0xFF6366F1)
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.memory, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      decodeModeLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (showShare) ...[
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('playerShareButton'),
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: '分享房间',
              onPressed: onShare,
            ),
          ],
          TvFocusable(
            radius: 12,
            onTap: onToggleLock,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                key: const ValueKey('playerLockButton'),
                locked ? Icons.lock : Icons.lock_open,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
