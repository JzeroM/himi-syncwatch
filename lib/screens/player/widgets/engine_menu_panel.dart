import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

/// 播放引擎选择面板（纯参数 widget）。
/// 放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供。
///
/// [engines] 为当前平台可用引擎列表（由 player_screen 按平台/ TV 模式传入，
/// 例如仅 Windows 含 media_kit；TV 仅 MDK）。
class EngineMenuPanel extends StatelessWidget {
  const EngineMenuPanel({
    super.key,
    required this.current,
    required this.engines,
    required this.onSelected,
    this.focusNode,
  });

  /// 当前生效引擎。
  final PlayerEngine current;

  /// 当前平台可用引擎（有序）。
  final List<PlayerEngine> engines;

  final ValueChanged<PlayerEngine> onSelected;

  /// TV 打开面板后精确落焦的行。
  final FocusNode? focusNode;

  String _hint(PlayerEngine e) {
    switch (e) {
      case PlayerEngine.mdk:
        return 'MDK: 原生 Dolby Vision 支持';
      case PlayerEngine.mediaKit:
        return 'media_kit: DV P5 不支持硬解';
      case PlayerEngine.erika:
        return 'Erika: 原生位图字幕(PGS) + HDR';
    }
  }

  @override
  Widget build(BuildContext context) {
    int targetIndex = engines.indexOf(current);
    if (targetIndex < 0) targetIndex = 0;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < engines.length; i++)
          SideOptionRow(
            label: engines[i].label,
            selected: engines[i] == current,
            focusNode: i == targetIndex ? focusNode : null,
            onTap: () => onSelected(engines[i]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Text(
            _hint(current),
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    );
  }
}
