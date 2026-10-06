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

  /// TV 打开面板后精确落焦的行：当前选中行，无选中回退第一行。
  final FocusNode? focusNode;

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
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    // 落焦行：选中的字幕轨（行序 = 关闭字幕 + 各流），无选中回退首行
    int targetRow = 0;
    if (activeSubtitleIndex != null) {
      final streamRow =
          subtitleStreams.indexWhere((s) => s.index == activeSubtitleIndex);
      if (streamRow >= 0) targetRow = streamRow + 1;
    }
    int rowIndex = 0;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        SideOptionRow(
          label: '关闭字幕',
          selected: activeSubtitleIndex == null,
          focusNode: rowIndex++ == targetRow ? focusNode : null,
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
            focusNode: rowIndex++ == targetRow ? focusNode : null,
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
          focusNode: rowIndex++ == targetRow ? focusNode : null,
          onTap: () {
            onLoadLocal();
            onClose();
          },
        ),
      ],
    );
  }
}
