import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/media_item.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';

/// 音轨选择面板（放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供）。
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (int i = 0; i < audioStreams.length; i++)
          SideOptionRow(
            label: audioStreams[i].displayInfo,
            selected: player.activeAudioTracks.contains(i),
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
}
