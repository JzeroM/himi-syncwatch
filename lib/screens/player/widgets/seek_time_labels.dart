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

  @override
  Widget build(BuildContext context) {
    // 时长 ≥1h → `HH:MM:SS` 8 字符档，否则 `MM:SS` 5 字符档；
    // 左右同宽对称，pos ≤ dur 不会溢出
    final cell = duration.inHours > 0 ? 78.0 : 56.0;
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
