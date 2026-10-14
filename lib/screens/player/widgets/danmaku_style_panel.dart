import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/glass_slider_theme.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/style_slider_row.dart';

/// 弹幕样式调节面板：速度 / 大小 / 透明度三行滑杆 + 「恢复默认」。
///
/// 纯参数 widget（不依赖 provider/状态），独立使用时自带滚动容器，
/// 组合进 `DisplayAdjustPanel` 时以 [scrollable]=false 提供段落。
/// 滑杆行为与字幕样式面板同款（TV 直接 D-pad 聚焦，左右键调值）。
class DanmakuStylePanel extends StatelessWidget {
  const DanmakuStylePanel({
    super.key,
    required this.speed,
    required this.fontSizeScale,
    required this.opacity,
    required this.onSpeedChanged,
    required this.onFontSizeChanged,
    required this.onOpacityChanged,
    required this.onReset,
    this.glassEnabled = true,
    this.scrollable = true,
  });

  // ---- 范围与步进 ----
  static const double minSpeed = 0.5;
  static const double maxSpeed = 2.0;
  static const double speedStep = 0.05;
  static const double minFontSize = 0.5;
  static const double maxFontSize = 2.0;
  static const double fontSizeStep = 0.05;
  static const double minOpacity = 0.1;
  static const double maxOpacity = 1.0;
  static const double opacityStep = 0.05;

  // ---- 默认值 ----
  static const double defaultSpeed = 1.0;
  static const double defaultFontSize = 0.5;
  static const double defaultOpacity = 0.6;

  /// 弹幕速度倍率（穿屏时长 = 8s ÷ speed）。
  final double speed;

  /// 字号倍率（基准 25px）。
  final double fontSizeScale;

  /// 整体透明度 0.1~1.0。
  final double opacity;

  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<double> onOpacityChanged;
  final VoidCallback onReset;

  /// 液态玻璃开关（设置页）；false 时滑杆回退纯色观。
  final bool glassEnabled;

  /// true = 自带滚动容器；false = 返回 Column 段落（组合面板用）。
  final bool scrollable;

  static String formatSpeed(double v) => '${v.toStringAsFixed(2)}×';

  static String formatFontSize(double v) => '${v.toStringAsFixed(2)}×';

  static String formatOpacity(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final theme = glassSliderTheme(
      thumbRadius: 9,
      overlayRadius: 16,
      glassEnabled: glassEnabled,
    );
    final children = <Widget>[
      styleSliderRow(
        label: '速度',
        valueText: formatSpeed(speed),
        valueKey: 'danmakuSpeedValue',
        slider: SliderTheme(
          data: theme,
          child: Slider(
            key: const ValueKey('danmakuSpeedSlider'),
            min: minSpeed,
            max: maxSpeed,
            divisions: ((maxSpeed - minSpeed) / speedStep).round(),
            value: speed.clamp(minSpeed, maxSpeed),
            onChanged: (v) =>
                onSpeedChanged(double.parse(v.toStringAsFixed(2))),
          ),
        ),
      ),
      styleSliderRow(
        label: '大小',
        valueText: formatFontSize(fontSizeScale),
        valueKey: 'danmakuFontSizeValue',
        slider: SliderTheme(
          data: theme,
          child: Slider(
            key: const ValueKey('danmakuFontSizeSlider'),
            min: minFontSize,
            max: maxFontSize,
            divisions: ((maxFontSize - minFontSize) / fontSizeStep).round(),
            value: fontSizeScale.clamp(minFontSize, maxFontSize),
            onChanged: (v) =>
                onFontSizeChanged(double.parse(v.toStringAsFixed(2))),
          ),
        ),
      ),
      styleSliderRow(
        label: '透明度',
        valueText: formatOpacity(opacity),
        valueKey: 'danmakuOpacityValue',
        slider: SliderTheme(
          data: theme,
          child: Slider(
            key: const ValueKey('danmakuOpacitySlider'),
            min: minOpacity,
            max: maxOpacity,
            divisions: ((maxOpacity - minOpacity) / opacityStep).round(),
            value: opacity.clamp(minOpacity, maxOpacity),
            onChanged: (v) =>
                onOpacityChanged(double.parse(v.toStringAsFixed(2))),
          ),
        ),
      ),
      const Divider(color: Colors.white24, height: 1),
      SideOptionRow(
        label: '恢复默认',
        selected: speed == defaultSpeed &&
            fontSizeScale == defaultFontSize &&
            opacity == defaultOpacity,
        onTap: onReset,
      ),
    ];
    if (scrollable) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
