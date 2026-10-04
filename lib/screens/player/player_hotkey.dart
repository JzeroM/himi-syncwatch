import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'player_platform.dart';

/// 播放页键盘/遥控器热键：
/// - 空格 = 暂停/播放（仅 Windows；KeyRepeatEvent 非 KeyDownEvent，长按自动忽略）
/// - ESC = 退出全屏（onEscape 提供时响应）
/// - TV 模式（Android 遥控器）：
///   * 中键 Enter/Select、媒体键 mediaPlayPause = 暂停/播放 + 唤出控制条
///     （onShowControls 提供时；控制条 5 秒后自动隐藏，隐藏期间再次唤出）
///   * 左右 = ±10 秒快进退（控制条隐藏时；可见时让位给焦点导航）
///   * 上下 = 唤出控制条（控制条隐藏时；可见时让位给焦点导航并顺延自动隐藏）
///   * 音量键 audioVolumeUp/audioVolumeDown（Android 遥控器音量键与 PC 多媒体键同映射）
///     = ±5% 应用内音量，任意时刻生效，长按（KeyRepeatEvent）连续调节；
///     onVolumeDelta 未提供时放行给系统音量
class PlayerHotkey extends StatefulWidget {
  const PlayerHotkey({
    super.key,
    required this.onTogglePlayPause,
    this.onEscape,
    this.tvMode = false,
    this.controlsVisible = true,
    this.onSeekRelative,
    this.onVolumeDelta,
    this.onShowControls,
    this.focusNode,
    required this.child,
  });

  final VoidCallback onTogglePlayPause;
  final VoidCallback? onEscape;
  final bool tvMode;

  /// 控制条是否可见：可见时方向键交给焦点导航（seek/唤出控制条让位）
  final bool controlsVisible;

  /// ±毫秒快进退回调（如 -10000）
  final ValueChanged<int>? onSeekRelative;

  /// ±百分比音量回调（如 +5 / -5）
  final ValueChanged<double>? onVolumeDelta;

  /// TV 中键/媒体键暂停播放时同步唤出控制条
  final VoidCallback? onShowControls;

  /// 外部持有的焦点节点：控制条隐藏后焦点回落到热键层，
  /// 方向键恢复 seek/唤出控制条语义（不传则内部创建）
  final FocusNode? focusNode;

  final Widget child;

  @override
  State<PlayerHotkey> createState() => _PlayerHotkeyState();
}

class _PlayerHotkeyState extends State<PlayerHotkey> {
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode(debugLabel: 'PlayerHotkey');

  @override
  void dispose() {
    // 仅释放内部创建的节点，外部传入的由持有者管理
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  static const _seekStepMs = 10000;
  static const _volumeStep = 5.0;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    // KeyUpEvent 放行；KeyRepeatEvent 仅音量键消费（见下），其余放行
    if (!isDown && !isRepeat) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // 音量键（TV 模式）：任意时刻生效，长按 KeyRepeatEvent 连续调节；
    // 未提供 onVolumeDelta 时放行给系统音量。
    // Android KEYCODE_VOLUME_UP/DOWN 与 PC 多媒体键均映射到 audioVolume*
    if (widget.tvMode) {
      final double? direction = key == LogicalKeyboardKey.audioVolumeUp
          ? 1.0
          : key == LogicalKeyboardKey.audioVolumeDown
              ? -1.0
              : null;
      if (direction != null) {
        final onVolume = widget.onVolumeDelta;
        if (onVolume == null) return KeyEventResult.ignored;
        onVolume(direction * _volumeStep);
        return KeyEventResult.handled;
      }
    }

    // 其余热键仅 KeyDownEvent：KeyRepeatEvent 放行，长按不重复触发
    if (!isDown) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.space) {
      if (!PlayerPlatform.spaceKeyPlayPause) return KeyEventResult.ignored;
      widget.onTogglePlayPause();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      final onEscape = widget.onEscape;
      if (onEscape == null) return KeyEventResult.ignored;
      onEscape();
      return KeyEventResult.handled;
    }

    if (widget.tvMode) {
      // 中键（OK 键）与媒体键 = 暂停/播放 + 唤出控制条
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.mediaPlayPause ||
          key == LogicalKeyboardKey.mediaPlay ||
          key == LogicalKeyboardKey.mediaPause) {
        widget.onTogglePlayPause();
        widget.onShowControls?.call();
        return KeyEventResult.handled;
      }

      // 方向键：控制条可见时让位给焦点导航（并顺延自动隐藏计时）；
      // 隐藏时左右 seek、上下唤出控制条
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        if (!widget.controlsVisible) {
          final onSeek = widget.onSeekRelative;
          if (key == LogicalKeyboardKey.arrowLeft && onSeek != null) {
            onSeek(-_seekStepMs);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight && onSeek != null) {
            onSeek(_seekStepMs);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown) {
            final onShow = widget.onShowControls;
            if (onShow != null) {
              onShow();
              return KeyEventResult.handled;
            }
          }
        } else {
          // 可见：仅顺延自动隐藏，不拦按键（焦点导航照常），故不 handled
          widget.onShowControls?.call();
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: widget.child,
    );
  }
}
