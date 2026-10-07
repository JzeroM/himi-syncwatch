import 'package:flutter/material.dart';

import 'package:himi_syncwatch/screens/player/widgets/danmaku_style_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/style_slider_row.dart';
import 'package:himi_syncwatch/screens/player/widgets/subtitle_style_panel.dart';

/// 「显示调节」组合面板：字幕段（大小/位置/延迟）+ 弹幕段
/// （速度/大小/透明度），共用一个滚动容器（两段均为非滚动段落，
/// 避免嵌套滚动冲突）。
///
/// 纯参数 widget；TV 落焦点为字幕段第一行滑杆（[focusNode]）。
class DisplayAdjustPanel extends StatelessWidget {
  const DisplayAdjustPanel({
    super.key,
    // 字幕段
    required this.subtitleScale,
    required this.subtitleMarginY,
    required this.subtitleDelayMs,
    required this.onSubtitleScaleChanged,
    required this.onSubtitleMarginChanged,
    required this.onSubtitleDelayChanged,
    required this.onSubtitleReset,
    this.subtitleDelayEnabled = true,
    // 弹幕段
    required this.danmakuSpeed,
    required this.danmakuFontSize,
    required this.danmakuOpacity,
    required this.onDanmakuSpeedChanged,
    required this.onDanmakuFontSizeChanged,
    required this.onDanmakuOpacityChanged,
    required this.onDanmakuReset,
    this.glassEnabled = true,
    this.focusNode,
  });

  // 字幕段参数
  final double subtitleScale;
  final int subtitleMarginY;
  final int subtitleDelayMs;
  final bool subtitleDelayEnabled;
  final ValueChanged<double> onSubtitleScaleChanged;
  final ValueChanged<int> onSubtitleMarginChanged;
  final ValueChanged<int> onSubtitleDelayChanged;
  final VoidCallback onSubtitleReset;

  // 弹幕段参数
  final double danmakuSpeed;
  final double danmakuFontSize;
  final double danmakuOpacity;
  final ValueChanged<double> onDanmakuSpeedChanged;
  final ValueChanged<double> onDanmakuFontSizeChanged;
  final ValueChanged<double> onDanmakuOpacityChanged;
  final VoidCallback onDanmakuReset;

  final bool glassEnabled;

  /// TV 打开面板后精确落焦：字幕段第一行（大小）滑杆。
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        panelSectionHeader('字幕'),
        SubtitleStylePanel(
          scale: subtitleScale,
          marginY: subtitleMarginY,
          delayMs: subtitleDelayMs,
          delayEnabled: subtitleDelayEnabled,
          glassEnabled: glassEnabled,
          focusNode: focusNode,
          scrollable: false,
          onScaleChanged: onSubtitleScaleChanged,
          onMarginYChanged: onSubtitleMarginChanged,
          onDelayChanged: onSubtitleDelayChanged,
          onReset: onSubtitleReset,
        ),
        const Divider(color: Colors.white24, height: 1),
        panelSectionHeader('弹幕'),
        DanmakuStylePanel(
          speed: danmakuSpeed,
          fontSizeScale: danmakuFontSize,
          opacity: danmakuOpacity,
          glassEnabled: glassEnabled,
          scrollable: false,
          onSpeedChanged: onDanmakuSpeedChanged,
          onFontSizeChanged: onDanmakuFontSizeChanged,
          onOpacityChanged: onDanmakuOpacityChanged,
          onReset: onDanmakuReset,
        ),
      ],
    );
  }
}
