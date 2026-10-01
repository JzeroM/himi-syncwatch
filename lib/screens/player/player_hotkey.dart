import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'player_platform.dart';

/// 播放页键盘热键：
/// - 空格 = 暂停/播放（仅 Windows；KeyRepeatEvent 非 KeyDownEvent，长按自动忽略）
/// - ESC = 退出全屏（onEscape 提供时响应）
class PlayerHotkey extends StatefulWidget {
  const PlayerHotkey({
    super.key,
    required this.onTogglePlayPause,
    this.onEscape,
    required this.child,
  });

  final VoidCallback onTogglePlayPause;
  final VoidCallback? onEscape;
  final Widget child;

  @override
  State<PlayerHotkey> createState() => _PlayerHotkeyState();
}

class _PlayerHotkeyState extends State<PlayerHotkey> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'PlayerHotkey');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // KeyUpEvent/KeyRepeatEvent 非 KeyDownEvent：放行，长按不重复触发
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (!PlayerPlatform.spaceKeyPlayPause) return KeyEventResult.ignored;
      widget.onTogglePlayPause();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final onEscape = widget.onEscape;
      if (onEscape == null) return KeyEventResult.ignored;
      onEscape();
      return KeyEventResult.handled;
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
