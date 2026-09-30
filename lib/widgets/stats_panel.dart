import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 彩虹条纹渐变：红橙黄绿青蓝紫七色，硬边 stops 形成条纹而非平滑过渡。
///
/// 每个色段占 1/7 宽度，通过「同色重复两个 stop」在段界突变。
LinearGradient buildRainbowStripeGradient() {
  const colors = <Color>[
    Color(0xFFF43F5E), // 红
    Color(0xFFFBBF24), // 橙
    Color(0xFFFDE047), // 黄
    Color(0xFF4ADE80), // 绿
    Color(0xFF22D3EE), // 青
    Color(0xFF60A5FA), // 蓝
    Color(0xFFA78BFA), // 紫
  ];
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [for (final c in colors) ...[c, c]],
    stops: [
      0, 1 / 7, //
      1 / 7, 2 / 7, //
      2 / 7, 3 / 7, //
      3 / 7, 4 / 7, //
      4 / 7, 5 / 7, //
      5 / 7, 6 / 7, //
      6 / 7, 1,
    ],
  );
}

/// 首页底部统计面板：横排三张玻璃卡片，数字为彩虹条纹。
class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key, required this.counts});

  final MediaCounts counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _StatCard(label: '电影', value: counts.movies),
          const SizedBox(width: 10),
          _StatCard(label: '电视剧', value: counts.series),
          const SizedBox(width: 10),
          _StatCard(label: '集', value: counts.episodes),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) =>
                  buildRainbowStripeGradient().createShader(bounds),
              child: Text(
                '$value',
                key: ValueKey('stat_$label'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
          ],
        ),
      ),
    );
  }
}
