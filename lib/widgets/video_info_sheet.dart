import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/player/media_info_summary.dart';

/// 695：「视频详细信息」面板——点击底栏信息按钮弹出。
///
/// 排版（产品拍板）：整体**可滚动**；每个分组一张**矩形玻璃卡片**；
/// 组内**每条信息纵向独占一行**（左：中文标签；右：英文值）；值缺失
/// 的行/组已在 [buildMediaInfoGroups] 省略。仅非房间模式由调用方门控。
Future<void> showVideoInfoSheet(
  BuildContext context,
  MediaInfoSummary summary,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => VideoInfoSheet(summary: summary),
  );
}

class VideoInfoSheet extends StatelessWidget {
  const VideoInfoSheet({super.key, required this.summary});

  final MediaInfoSummary summary;

  @override
  Widget build(BuildContext context) {
    final groups = summary.groups;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xE6121417),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  '视频详细信息',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final g in groups) ...[
                  _GroupCard(group: g),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 每个分组 = 一张矩形玻璃卡片；组内每条信息一行。
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final MediaInfoGroup group;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 6),
              for (final row in group.rows)
                Padding(
                  // 每条信息纵向独占一行
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          row.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value,
                          textAlign: TextAlign.right,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
