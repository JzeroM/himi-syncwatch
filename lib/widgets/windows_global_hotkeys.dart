import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/router.dart';
import '../services/player/player_hotkey_bridge.dart';
import '../services/room/room_exit_request.dart';

/// 695：Windows 全局键动作（纯函数决策，便于单测）。
enum WindowsHotkeyAction {
  /// 不消费（放行给焦点链/系统）。
  ignored,

  /// 暂停/播放。
  togglePlay,

  /// 退出全屏（阶梯第一段）。
  exitFullscreen,

  /// 房间：解散/离开房间确认（= Flutter 窗右上角关闭窗口同款）。
  roomExit,

  /// 单人：所有 Flutter 页面返回。
  pageBack,
}

/// 695：Windows 全局键决策（Space/ESC）。
///
/// 规则（产品拍板）：
/// - 文本输入焦点一律放行（打字不受影响）；
/// - Space = 暂停/播放（有会话且有权时；房间观众被回调内部门禁拦截）；
/// - ESC 阶梯 = 全屏 → 退全屏；房间播放 → 解散/离开确认；
///   其余 → 页面返回。
WindowsHotkeyAction resolveWindowsHotkey({
  required bool isSpace,
  required bool isEscape,
  required bool textInputFocused,
  required bool canTogglePlay,
  required bool isFullscreen,
  required bool roomActive,
}) {
  if (textInputFocused) return WindowsHotkeyAction.ignored;
  if (isSpace) {
    return canTogglePlay
        ? WindowsHotkeyAction.togglePlay
        : WindowsHotkeyAction.ignored;
  }
  if (isEscape) {
    if (isFullscreen) return WindowsHotkeyAction.exitFullscreen;
    if (roomActive) return WindowsHotkeyAction.roomExit;
    return WindowsHotkeyAction.pageBack;
  }
  return WindowsHotkeyAction.ignored;
}

/// Windows 全局键盘层：挂在 app 根部（`MaterialApp.router.builder`），
/// 让 Space/ESC 在任意 Flutter 页面生效。
///
/// 【焦点关系】本层是焦点树根部节点——播放页 `PlayerHotkey` 更深，
/// 先拿到按键：它消费（如全屏时 ESC=退全屏）则本层不重复处理；它
/// 放行（如非全屏 ESC）则冒泡到本层补位，天然形成「全屏先退全屏、
/// 再按才返回」的阶梯。
class WindowsGlobalHotkeys extends StatefulWidget {
  const WindowsGlobalHotkeys({super.key, required this.child});

  final Widget child;

  @override
  State<WindowsGlobalHotkeys> createState() => _WindowsGlobalHotkeysState();
}

class _WindowsGlobalHotkeysState extends State<WindowsGlobalHotkeys> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'WindowsGlobalHotkeys');

  static bool get _onWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 文本输入焦点（TextField/EditableText 及子类）→ 放行。
  static bool get _textInputFocused {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_onWindows) return KeyEventResult.ignored;
    // 仅 KeyDownEvent：长按 KeyRepeat 不重复触发。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isSpace = event.logicalKey == LogicalKeyboardKey.space;
    final isEscape = event.logicalKey == LogicalKeyboardKey.escape;
    if (!isSpace && !isEscape) return KeyEventResult.ignored;

    final action = resolveWindowsHotkey(
      isSpace: isSpace,
      isEscape: isEscape,
      textInputFocused: _textInputFocused,
      canTogglePlay: PlayerHotkeyBridge.togglePlayPause != null,
      isFullscreen: PlayerHotkeyBridge.isWindowFullscreen?.call() ?? false,
      roomActive: RoomExitRequest.hasRoomListener,
    );
    switch (action) {
      case WindowsHotkeyAction.ignored:
        return KeyEventResult.ignored;
      case WindowsHotkeyAction.togglePlay:
        PlayerHotkeyBridge.togglePlayPause?.call();
        return KeyEventResult.handled;
      case WindowsHotkeyAction.exitFullscreen:
        PlayerHotkeyBridge.exitWindowFullscreen?.call();
        return KeyEventResult.handled;
      case WindowsHotkeyAction.roomExit:
        // = Flutter 窗右上角关闭窗口同款：弹「解散/离开房间」确认面板。
        RoomExitRequest.request();
        return KeyEventResult.handled;
      case WindowsHotkeyAction.pageBack:
        // 全局层挂在 Navigator 之上，经 routerKey 弹栈（所有 Flutter 页面）。
        routerKey.currentState?.maybePop();
        return KeyEventResult.handled;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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
