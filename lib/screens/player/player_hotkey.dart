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
///   * 上下 = ±5% 音量（控制条隐藏时；可见时让位给焦点导航）
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

  /// 控制条是否可见：可见时方向键交给焦点导航（seek/音量让位）
  final bool controlsVisible;

  /// ±毫秒快进退回调（如 -10000）
  final ValueChanged<int>? onSeekRelative;

  /// ±百分比音量回调（如 +5 / -5）
  final ValueChanged<double>? onVolumeDelta;

  /// TV 中键/媒体键暂停播放时同步唤出控制条
  final VoidCallback? onShowControls;

  /// 外部持有的焦点节点：控制条隐藏后焦点回落到热键层，
  /// 方向键恢复 seek/音量语义（不传则内部创建）
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
    // KeyUpEvent/KeyRepeatEvent 非 KeyDownEvent：放行，长按不重复触发
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

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

      // 方向键：控制条可见时让位给焦点导航；隐藏时 seek/音量
      if (!widget.controlsVisible) {
        final onSeek = widget.onSeekRelative;
        final onVolume = widget.onVolumeDelta;
        switch (key) {
          case LogicalKeyboardKey.arrowLeft:
            if (onSeek != null) {
              onSeek(-_seekStepMs);
              return KeyEventResult.handled;
            }
          case LogicalKeyboardKey.arrowRight:
            if (onSeek != null) {
              onSeek(_seekStepMs);
              return KeyEventResult.handled;
            }
          case LogicalKeyboardKey.arrowUp:
            if (onVolume != null) {
              onVolume(_volumeStep);
              return KeyEventResult.handled;
            }
          case LogicalKeyboardKey.arrowDown:
            if (onVolume != null) {
              onVolume(-_volumeStep);
              return KeyEventResult.handled;
            }
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
