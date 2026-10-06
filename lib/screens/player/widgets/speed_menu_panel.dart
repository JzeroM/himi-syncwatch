import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';

/// 播放倍速选择面板（纯参数 widget，不依赖 provider/状态，
/// 便于脱离 `mdk.Player` 单测档位渲染与选择回调）。
/// 放进 [SelectorSidePanel] 右侧浮层，滚动由外层提供。
class SpeedMenuPanel extends StatelessWidget {
  const SpeedMenuPanel({
    super.key,
    required this.current,
    required this.onSelected,
    this.focusNode,
  });

  /// 可选倍速档位。
  static const List<double> speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
  ];

  /// 当前生效倍速（与 [speedOptions] 容差比对高亮）。
  final double current;

  final ValueChanged<double> onSelected;

  /// TV 打开面板后精确落焦的行：当前档位，无匹配回退第一档。
  /// （autofocus 在同级按钮已持焦时不抢占，改由播放页显式 requestFocus）
  final FocusNode? focusNode;

  /// 档位 → 按钮角标/回显文本：`1.0x`、`0.75x`。
  static String formatSpeedLabel(double speed) => '${speed}x';

  @override
  Widget build(BuildContext context) {
    int targetIndex =
        speedOptions.indexWhere((s) => (s - current).abs() < 1e-9);
    if (targetIndex < 0) targetIndex = 0;
    // ListView（可上下滚动）：档位多、浮层高度有限时 Column 会把
    // 超出部分直接裁掉（0.5x~1.25x 后不可见）。
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < speedOptions.length; i++)
          SideOptionRow(
            label: formatSpeedLabel(speedOptions[i]),
            selected: (speedOptions[i] - current).abs() < 1e-9,
            focusNode: i == targetIndex ? focusNode : null,
            onTap: () => onSelected(speedOptions[i]),
          ),
      ],
    );
  }
}
