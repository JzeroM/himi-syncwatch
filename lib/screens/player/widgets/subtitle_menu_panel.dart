import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/media_item.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';

/// 字幕选择面板（放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供）。
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        SideOptionRow(
          label: '关闭字幕',
          selected: activeSubtitleIndex == null,
          onTap: () {
            player.activeSubtitleTracks = [];
            onSubtitleSelected(null);
            onClose();
          },
        ),
        for (int i = 0; i < subtitleStreams.length; i++)
          SideOptionRow(
            label: subtitleStreams[i].displayInfo,
            selected: activeSubtitleIndex == subtitleStreams[i].index,
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
        SideOptionRow(
          label: '加载本地字幕文件...',
          selected: false,
          onTap: () {
            onLoadLocal();
            onClose();
          },
        ),
      ],
    );
  }
}
