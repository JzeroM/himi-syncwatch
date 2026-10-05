import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 播放倍速选择面板（纯参数 widget，不依赖 provider/状态，
/// 便于脱离 `mdk.Player` 单测档位渲染与选择回调）。
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
    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: speedOptions.map((speed) {
            final isSelected = (speed - current).abs() < 1e-9;
            // TV 遥控：选项行可聚焦（焦点环 + Enter 选择），触摸行为不变
            return TvFocusable(
              autofocus: speedOptions.first == speed,
              onTap: () => onSelected(speed),
              radius: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                      : null,
                  border: const Border(
                      bottom: BorderSide(color: Colors.white12, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color:
                          isSelected ? const Color(0xFF6366F1) : Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatSpeedLabel(speed),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
