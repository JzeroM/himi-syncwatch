import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

/// 播放引擎选择面板（纯参数 widget）。
/// 放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供。
class EngineMenuPanel extends StatelessWidget {
  const EngineMenuPanel({
    super.key,
    required this.current,
    required this.onSelected,
    this.focusNode,
  });

  /// 当前生效引擎。
  final PlayerEngine current;

  final ValueChanged<PlayerEngine> onSelected;

  /// TV 打开面板后精确落焦的行。
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    int targetIndex = PlayerEngine.values.indexOf(current);
    if (targetIndex < 0) targetIndex = 0;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < PlayerEngine.values.length; i++)
          SideOptionRow(
            label: PlayerEngine.values[i].label,
            selected: PlayerEngine.values[i] == current,
            focusNode: i == targetIndex ? focusNode : null,
            onTap: () => onSelected(PlayerEngine.values[i]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text(
            current == PlayerEngine.mediaKit
                ? 'media_kit: DV P5 不支持硬解'
                : 'MDK: 原生 Dolby Vision 支持',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    );
  }
}
