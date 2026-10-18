import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';

/// 多版本切换面板（放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供）。
class VersionMenuPanel extends StatelessWidget {
  final List<MediaSource> sources;
  final String? activeSourceId;
  final ValueChanged<MediaSource> onSourceSelected;
  final VoidCallback onClose;

  /// TV 打开面板后精确落焦的行：当前生效版本，无选中回退第一行。
  final FocusNode? focusNode;

  const VersionMenuPanel({
    super.key,
    required this.sources,
    required this.activeSourceId,
    required this.onSourceSelected,
    required this.onClose,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    int targetRow = sources.indexWhere((s) => s.id == activeSourceId);
    if (targetRow < 0) targetRow = 0;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (int i = 0; i < sources.length; i++)
          SideOptionRow(
            label: sources[i].displayLabel,
            selected: sources[i].id == activeSourceId,
            focusNode: i == targetRow ? focusNode : null,
            onTap: () {
              onSourceSelected(sources[i]);
              onClose();
            },
          ),
        if (sources.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '当前视频无其他版本',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
      ],
    );
  }
}
