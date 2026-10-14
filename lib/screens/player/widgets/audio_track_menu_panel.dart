import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/widgets/glass/frosted_surface.dart';

/// 音轨选择面板（放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供）。
class AudioTrackMenuPanel extends StatelessWidget {
  final PlayerAdapter player;
  final List<MediaStream> audioStreams;
  final int currentAudioIndex;
  final ValueChanged<int> onAudioSelected;
  final VoidCallback onClose;

  /// TV 打开面板后精确落焦的行：当前选中音轨，无选中回退第一行。
  final FocusNode? focusNode;

  const AudioTrackMenuPanel({
    super.key,
    required this.player,
    required this.audioStreams,
    this.currentAudioIndex = -1,
    required this.onAudioSelected,
    required this.onClose,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    // 落焦行：当前生效音轨（activeAudioTracks 存的是下标），无则回退首行
    int targetRow = -1;
    for (int i = 0; i < audioStreams.length; i++) {
      if (player.activeAudioTracks.contains(i)) {
        targetRow = i;
        break;
      }
    }
    if (targetRow < 0) targetRow = 0;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (int i = 0; i < audioStreams.length; i++)
          SideOptionRow(
            label: audioStreams[i].displayInfo,
            selected: player.activeAudioTracks.contains(i),
            focusNode: i == targetRow ? focusNode : null,
            onTap: () {
              onAudioSelected(i);
              onClose();
            },
          ),
        if (audioStreams.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '当前视频无音轨选项',
              style: TextStyle(
                color: FrostedSurface.darkInkWith(0.54),
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}
