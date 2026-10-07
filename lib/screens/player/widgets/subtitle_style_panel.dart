import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/glass_slider_theme.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';

/// 字幕样式调节面板：大小 / 位置 / 延迟三行滑杆 + 「恢复默认」。
///
/// 纯参数 widget（不依赖 provider/状态），放进 [SelectorSidePanel] 右侧
/// 浮层；滑杆行为与设置页 `_glassSliderRow` 同款（TV 直接 D-pad 聚焦，
/// 左右键调值）。数值范围/步进集中为静态常量，便于测试与默认值断言。
class SubtitleStylePanel extends StatelessWidget {
  const SubtitleStylePanel({
    super.key,
    required this.scale,
    required this.marginY,
    required this.delayMs,
    required this.onScaleChanged,
    required this.onMarginYChanged,
    required this.onDelayChanged,
    required this.onReset,
    this.delayEnabled = true,
    this.glassEnabled = true,
    this.focusNode,
  });

  // ---- 范围与步进 ----
  static const double minScale = 0.5;
  static const double maxScale = 3.0;
  static const double scaleStep = 0.05;
  static const int minMarginY = 0;
  static const int maxMarginY = 200;
  static const int marginStep = 2;
  static const int minDelayMs = -5000;
  static const int maxDelayMs = 5000;
  static const int delayStepMs = 100;

  // ---- 默认值（= mdk 初始化属性）----
  static const double defaultScale = 1.0;
  static const int defaultMarginY = 22;
  static const int defaultDelayMs = 0;

  /// 字幕缩放（mdk `subtitle.scale`）。
  final double scale;

  /// 字幕底部边距 px（mdk `subtitle.margin.y`）。
  final int marginY;

  /// 字幕延迟毫秒（正=晚显示）。
  final int delayMs;

  /// 无任何激活字幕轨时延迟不可调（滑杆禁用）。
  final bool delayEnabled;

  /// 液态玻璃开关（设置页）；false 时滑杆回退纯色观。
  final bool glassEnabled;

  final ValueChanged<double> onScaleChanged;
  final ValueChanged<int> onMarginYChanged;
  final ValueChanged<int> onDelayChanged;
  final VoidCallback onReset;

  /// TV 打开面板后精确落焦的控件：第一行（大小）滑杆。
  final FocusNode? focusNode;

  static String formatScale(double v) => '${v.toStringAsFixed(2)}×';

  static String formatMarginY(int v) => '${v}px';

  /// `+0.8s` / `-1.2s` / `0.0s`
  static String formatDelay(int ms) {
    final sign = ms > 0 ? '+' : '';
    return '$sign${(ms / 1000).toStringAsFixed(1)}s';
  }

  Widget _row({
    required String label,
    required String valueText,
    required String valueKey,
    required Widget slider,
  }) {
    return Padding(
      key: valueKey.isEmpty ? null : ValueKey('${valueKey}Row'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          Expanded(child: slider),
          SizedBox(
            width: 48,
            child: Text(
              valueText,
              key: ValueKey(valueKey),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = glassSliderTheme(
      thumbRadius: 7,
      overlayRadius: 12,
      glassEnabled: glassEnabled,
    );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _row(
          label: '大小',
          valueText: formatScale(scale),
          valueKey: 'subtitleStyleScaleValue',
          slider: SliderTheme(
            data: theme,
            child: Slider(
              key: const ValueKey('subtitleStyleScaleSlider'),
              min: minScale,
              max: maxScale,
              divisions: ((maxScale - minScale) / scaleStep).round(),
              value: scale.clamp(minScale, maxScale),
              focusNode: focusNode,
              onChanged: (v) =>
                  onScaleChanged(double.parse(v.toStringAsFixed(2))),
            ),
          ),
        ),
        _row(
          label: '位置',
          valueText: formatMarginY(marginY),
          valueKey: 'subtitleStyleMarginValue',
          slider: SliderTheme(
            data: theme,
            child: Slider(
              key: const ValueKey('subtitleStyleMarginSlider'),
              min: minMarginY.toDouble(),
              max: maxMarginY.toDouble(),
              divisions: (maxMarginY - minMarginY) ~/ marginStep,
              value: marginY.clamp(minMarginY, maxMarginY).toDouble(),
              onChanged: (v) => onMarginYChanged(v.round()),
            ),
          ),
        ),
        _row(
          label: '延迟',
          valueText: formatDelay(delayMs),
          valueKey: 'subtitleStyleDelayValue',
          slider: SliderTheme(
            data: theme,
            child: Slider(
              key: const ValueKey('subtitleStyleDelaySlider'),
              min: minDelayMs.toDouble(),
              max: maxDelayMs.toDouble(),
              divisions: (maxDelayMs - minDelayMs) ~/ delayStepMs,
              value: delayMs.clamp(minDelayMs, maxDelayMs).toDouble(),
              onChanged: delayEnabled ? (v) => onDelayChanged(v.round()) : null,
            ),
          ),
        ),
        if (!delayEnabled)
          const Padding(
            padding: EdgeInsets.only(left: 60, top: 4),
            child: Text(
              '当前无激活字幕轨，延迟不可调',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ),
        const Divider(color: Colors.white24, height: 1),
        SideOptionRow(
          label: '恢复默认',
          selected: scale == defaultScale &&
              marginY == defaultMarginY &&
              delayMs == defaultDelayMs,
          onTap: onReset,
        ),
      ],
    );
  }
}
