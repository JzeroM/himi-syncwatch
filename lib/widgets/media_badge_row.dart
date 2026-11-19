import 'package:flutter/material.dart';

import 'glass/glass_container.dart';

/// 695：媒体信息徽章行（进度条上方）——玻璃**圆角矩形**胶囊、靠右对齐、
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
      // 圆角矩形胶囊（radius 6 + 纵向内距 3 → 矩形观感，非药丸/椭圆；
      // 695 真机回归：radius 10 + 小高变椭圆，不好看）
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
