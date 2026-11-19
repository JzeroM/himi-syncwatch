import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/player/media_info_summary.dart';
import '../screens/player/widgets/selector_side_panel.dart';

/// 695：「视频详细信息」面板——点按底栏信息按钮弹出。
///
/// 样式（产品拍板）：与播放页其他弹出面板**同风格**——右侧玻璃浮层
/// （复用 [SelectorSidePanel]，`GlassContainer(popup:true)` 深色磨砂+白
/// 描边+投影），**靠右显示**；整体可滚动；每个分组一张矩形玻璃卡片；
/// 组内每条信息纵向独占一行（左：中文标签；右：英文值）。仅非房间由
/// 调用方门控。
Future<void> showVideoInfoSheet(
  BuildContext context,
  MediaInfoSummary summary,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => Dialog(
      alignment: Alignment.centerRight,
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          const EdgeInsets.only(left: 16, right: 12, top: 16, bottom: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 680),
        child: VideoInfoSheet(summary: summary),
      ),
    ),
  );
}

class VideoInfoSheet extends StatelessWidget {
  const VideoInfoSheet({super.key, required this.summary});

  final MediaInfoSummary summary;

  @override
  Widget build(BuildContext context) {
    return SelectorSidePanel(
      title: '视频详细信息',
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final g in summary.groups) ...[
              _GroupCard(group: g),
              const SizedBox(height: 10),
            ],
          ],
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
