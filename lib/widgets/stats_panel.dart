import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 首页底部统计面板：横排三张玻璃卡片，展示电影 / 电视剧 / 集的数量。
class StatsPanel extends ConsumerWidget {
  const StatsPanel({super.key, required this.counts});

  final MediaCounts counts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? Theme.of(context).colorScheme.primary
        : Color(themeColorValue);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          _StatCard(label: '电影', value: counts.movies, accent: accent),
          const SizedBox(width: 10),
          _StatCard(label: '电视剧', value: counts.series, accent: accent),
          const SizedBox(width: 10),
          _StatCard(label: '集', value: counts.episodes, accent: accent),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$value',
              key: ValueKey('stat_$label'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }
}
