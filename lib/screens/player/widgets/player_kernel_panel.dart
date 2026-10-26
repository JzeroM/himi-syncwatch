import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 播放内核选择面板（放进 [SelectorSidePanel] 右侧浮层）。
class PlayerKernelPanel extends StatelessWidget {
  const PlayerKernelPanel({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onClose,
    this.focusNode,
  });

  final PlayerEngine current;
  final ValueChanged<PlayerEngine> onSelect;
  final VoidCallback onClose;
  final FocusNode? focusNode;

  static String descriptionOf(PlayerEngine engine) => switch (engine) {
        PlayerEngine.mdk => 'MDK / FVP，兼容性与 HDR 直通',
        PlayerEngine.mediaKit => 'libmpv，格式覆盖广，适合桌面',
        PlayerEngine.erika => 'Erika，Rust 内核，原生位图字幕',
        PlayerEngine.mpv => 'MPV / libmpv，鸿蒙专用，格式与字幕覆盖广',
      };

  @override
  Widget build(BuildContext context) {
    final engines = PlayerEngineFactory.supportedEngines();
    final selectedIndex = engines.indexOf(current);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (var i = 0; i < engines.length; i++)
          SideOptionRow(
            label: '${engines[i].shortLabel} · ${descriptionOf(engines[i])}',
            selected: i == selectedIndex,
            focusNode: i == (selectedIndex >= 0 ? selectedIndex : 0)
                ? focusNode
                : null,
            onTap: () {
              onSelect(engines[i]);
              onClose();
            },
          ),
        const Divider(color: Colors.white24, height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            '切换仅影响当前播放，不改变默认引擎；下一集沿用当前内核',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
