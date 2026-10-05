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

  /// 档位 → 按钮角标/回显文本：`1.0x`、`0.75x`。
  static String formatSpeedLabel(double speed) => '${speed}x';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: speedOptions.map((speed) {
        final isSelected = (speed - current).abs() < 1e-9;
        return SideOptionRow(
          label: formatSpeedLabel(speed),
          selected: isSelected,
          // TV 遥控：初进落焦第一档（焦点环 + Enter 选择）
          autofocus: speedOptions.first == speed,
          onTap: () => onSelected(speed),
        );
      }).toList(),
    );
  }
}
