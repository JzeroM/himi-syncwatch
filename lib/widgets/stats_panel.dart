import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 首页底部统计面板：横排三张玻璃卡片，白色数字 + 三色点缀条。
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.counts});

  final MediaCounts counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _StatCard(
            label: '电影',
            value: counts.movies,
            barColor: const Color(0xFF2DD4BF), // 青绿
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: '电视剧',
            value: counts.series,
            barColor: const Color(0xFFFBBF24), // 琥珀
          ),
          const SizedBox(width: 10),
          _StatCard(
            label: '集',
            value: counts.episodes,
            barColor: const Color(0xFFA78BFA), // 紫罗兰
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.barColor,
  });

  final String label;
  final int value;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              key: ValueKey('stat_$label'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              key: ValueKey('statBar_$label'),
              height: 3,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: const BorderRadius.all(Radius.circular(1.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
