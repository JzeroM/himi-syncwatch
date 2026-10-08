import 'package:flutter/material.dart';

/// 播放页底部控制条的主按钮行。
///
/// 两种排布：
/// - `centered = false`（TV / 桌面）：传输组（上一集/播放暂停/下一集）置左，
///   `leading`（Windows 音量/亮度滑杆）紧随其后，`trailing` 贴右，中间留白。
/// - `centered = true`（手机）：传输组**精确水平居中**，`trailing` 贴右，
///   `leading` 贴左（锁钮等）；极窄屏时 `trailing` 会被 `FittedBox`
///   轻微等比缩放以防溢出。
///
/// 纯参数布局件，便于脱离 `mdk.Player` 单测居中与贴右行为。
class PlayerBottomRow extends StatelessWidget {
  const PlayerBottomRow({
    super.key,
    required this.transport,
    required this.trailing,
    this.leading = const [],
    this.centered = false,
  });

  /// 传输组：上一集 / 播放暂停 / 下一集（可为空列表：房间非房主）。
  final List<Widget> transport;

  /// 左组附加（Windows 音量/亮度滑杆）；仅 `centered = false` 时参与排布。
  final List<Widget> leading;

  /// 右侧按钮组：弹幕 / 字幕 / 音轨 / 面板 / 全屏等。
  final List<Widget> trailing;

  /// 传输组是否精确居中（手机）。
  final bool centered;

  @override
  Widget build(BuildContext context) {
    if (!centered) {
      return Row(
        children: [
          ...transport,
          ...leading,
          const Spacer(),
          ...trailing,
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: leading),
          ),
        ),
        ...transport,
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: trailing),
            ),
          ),
        ),
      ],
    );
  }
}
