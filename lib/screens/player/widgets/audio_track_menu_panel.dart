import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/media_item.dart';

class AudioTrackMenuPanel extends StatelessWidget {
  final mdk.Player player;
  final List<MediaStream> audioStreams;
  final int currentAudioIndex;
  final ValueChanged<int> onAudioSelected;
  final VoidCallback onClose;

  const AudioTrackMenuPanel({
    super.key,
    required this.player,
    required this.audioStreams,
    this.currentAudioIndex = -1,
    required this.onAudioSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (int i = 0; i < audioStreams.length; i++)
          _buildMenuItem(
            label: audioStreams[i].displayInfo,
            isSelected: player.activeAudioTracks.contains(i),
            onTap: () {
              onAudioSelected(i);
              onClose();
            },
          ),
        if (audioStreams.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '当前视频无音轨选项',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
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
