import 'package:flutter/material.dart';

/// 播放器时间格式化：有小时 `HH:MM:SS`（补零），否则 `MM:SS`。
String formatPlayerDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// 进度条两侧时间数显：左当前进度、右总时长，与滑杆同一水平中线。
///
/// 两格同宽（按总时长格式分档），逐秒更新不产生布局位移；
/// 中段为滑杆本体（焦点/描边环仍只框进度条）。
class SeekTimeLabels extends StatelessWidget {
  const SeekTimeLabels({
    super.key,
    required this.position,
    required this.duration,
    required this.child,
  });

  /// 当前进度。
  final Duration position;

  /// 总时长（决定数显格式档位与两格宽度）。
  final Duration duration;

  /// 中段进度条（滑杆本体）。
  final Widget child;

  /// 单侧时间格宽度：时长 ≥1h 用 `HH:MM:SS` 8 字符档（78），否则
  /// `MM:SS` 5 字符档（56）。左右同宽，逐秒更新不抖动；供外部（如
  /// 播放/暂停控件对齐左数显）复用同一宽度。
  static double cellWidth(Duration duration) =>
      duration.inHours > 0 ? 78.0 : 56.0;

  @override
  Widget build(BuildContext context) {
    final cell = cellWidth(duration);
    const style = TextStyle(color: Colors.white70, fontSize: 12);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: cell,
          child: Text(
            formatPlayerDuration(position),
            textAlign: TextAlign.right,
            maxLines: 1,
            style: style,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
        const SizedBox(width: 8),
        SizedBox(
          width: cell,
          child: Text(
            formatPlayerDuration(duration),
            textAlign: TextAlign.left,
            maxLines: 1,
            style: style,
          ),
        ),
      ],
    );
  }
}
