import 'package:flutter/material.dart';

import 'glass/glass_container.dart';

/// 695：媒体信息徽章行（进度条上方）——玻璃矩形圆角胶囊、右对齐、
/// 胶囊间等距；无徽章时不占位。仅非房间模式由调用方门控。
class MediaBadgeRow extends StatelessWidget {
  const MediaBadgeRow({super.key, required this.badges});

  final List<String> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final badge in badges)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _BadgeCapsule(text: badge),
            ),
        ],
      ),
    );
  }
}

class _BadgeCapsule extends StatelessWidget {
  const _BadgeCapsule({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      // 矩形圆角胶囊（胶囊 10，与焦点环胶囊圆角规范一致）
      borderRadius: BorderRadius.circular(10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          height: 1.3,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
