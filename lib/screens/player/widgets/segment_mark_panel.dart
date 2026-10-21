import 'package:flutter/material.dart';

import 'package:himi_syncwatch/models/media_segment.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// TV 端长按进度条弹出的片头/片尾标记面板。
///
/// 主面板只有两项（设置片头 / 设置片尾）；已有标记时由播放器再弹二次确认。
class SegmentMarkPanel extends StatelessWidget {
  const SegmentMarkPanel({
    super.key,
    required this.positionMs,
    required this.introEndMs,
    required this.creditsStartMs,
    required this.firstFocusNode,
    required this.onSelect,
  });

  final int positionMs;
  final int? introEndMs;
  final int? creditsStartMs;
  final FocusNode firstFocusNode;
  final ValueChanged<MediaSegmentType> onSelect;

  static String formatMs(int ms) {
    final d = Duration(milliseconds: ms < 0 ? 0 : ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.content_cut, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '片头 / 片尾',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '当前位置 ${formatMs(positionMs)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SegmentMarkRow(
              focusNode: firstFocusNode,
              icon: Icons.skip_next,
              title: '设置片头',
              value: introEndMs,
              hint: '当前位置作为片头结束 / 正片开始',
              onTap: () => onSelect(MediaSegmentType.intro),
            ),
            const SizedBox(height: 8),
            _SegmentMarkRow(
              icon: Icons.skip_previous,
              title: '设置片尾',
              value: creditsStartMs,
              hint: '当前位置作为片尾开始',
              onTap: () => onSelect(MediaSegmentType.outro),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentMarkRow extends StatelessWidget {
  const _SegmentMarkRow({
    this.focusNode,
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final String title;
  final int? value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return TvFocusable(
      focusNode: focusNode,
      radius: 12,
      scale: 1.0,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasValue
                        ? '已设置：${SegmentMarkPanel.formatMs(value!)}'
                        : hint,
                    style: TextStyle(
                      color: hasValue ? Colors.greenAccent : Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}
