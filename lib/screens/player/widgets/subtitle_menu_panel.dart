import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/media_item.dart';

class SubtitleMenuPanel extends StatelessWidget {
  final mdk.Player player;
  final List<MediaStream> subtitleStreams;
  final int? activeSubtitleIndex;
  final bool useServerBurnIn;
  final String? itemId;
  final String? mediaSourceId;
  final String token;
  final ValueChanged<int?> onSubtitleSelected;
  final VoidCallback onLoadLocal;
  final VoidCallback onClose;

  const SubtitleMenuPanel({
    super.key,
    required this.player,
    required this.subtitleStreams,
    this.activeSubtitleIndex,
    this.useServerBurnIn = false,
    this.itemId,
    this.mediaSourceId,
    this.token = '',
    required this.onSubtitleSelected,
    required this.onLoadLocal,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _buildMenuItem(
          label: '关闭字幕',
          isSelected: activeSubtitleIndex == null,
          onTap: () {
            player.activeSubtitleTracks = [];
            onSubtitleSelected(null);
            onClose();
          },
        ),
        for (int i = 0; i < subtitleStreams.length; i++)
          _buildMenuItem(
            label: subtitleStreams[i].displayInfo,
            isSelected: activeSubtitleIndex == subtitleStreams[i].index,
            onTap: () {
              onSubtitleSelected(i);
              onClose();
            },
          ),
        if (subtitleStreams.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '当前视频无内嵌字幕轨道',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
        Divider(color: Colors.white24, height: 1),
        _buildMenuItem(
          label: '加载本地字幕文件...',
          isSelected: false,
          onTap: () {
            onLoadLocal();
            onClose();
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF6366F1) : Colors.white54,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF6366F1) : Colors.white,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
