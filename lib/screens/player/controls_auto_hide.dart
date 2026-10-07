import 'dart:async';

import 'package:flutter/widgets.dart';

/// 控件自动隐藏控制器：长时间无真实输入后回调 [onHide]。
///
/// 仅**真实操作**顺延计时（[reset]）：
/// - 焦点**位置变更**且落在 [focusRoots] 内（[onFocusChanged]）；
/// - 控件根内按键事件（[onKeyEvent]，TV OK 等焦点不移动的交互）；
/// - 指针按下/松开（[notePointerDown] 按住期间暂停 / [notePointerUp] 重开）。
///
/// 焦点只是**静置**在控件上不算操作：计时照走到点触发 [onHide]
///（由调用方收起全部控件并回落焦点）。[enabled] 为 false 时不启动、
/// 到点也不触发（控件已隐藏/锁定场景）。
class ControlsAutoHideController {
  ControlsAutoHideController({
    required this.after,
    required this.onHide,
    required this.focusRoots,
    this.enabled,
  });

  /// 无操作时长（5 秒）。
  final Duration after;

  /// 到点回调（调用方负责收起控件）。
  final VoidCallback onHide;

  /// "焦点在控件内"的判定根（底部控制条 / 选择器面板 / 顶栏）。
  final List<FocusNode> Function() focusRoots;

  /// 计时是否有效（如 `() => _showControls`）；null 视为恒有效。
  final bool Function()? enabled;

  Timer? _timer;

  bool get _active => enabled?.call() ?? true;

  /// 顺延计时（控件隐藏时为空操作）。
  void reset() {
    _timer?.cancel();
    if (!_active) return;
    _timer = Timer(after, _fire);
  }

  /// 停止计时（隐藏控件/锁定/页面销毁）。
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// 指针按下：暂停计时（手指按住不动不隐藏）。
  void notePointerDown() => _timer?.cancel();

  /// 指针松开/取消：重新起算一轮。
  void notePointerUp() => reset();

  /// 焦点变更：新焦点落在任一控件根内视为操作。
  /// 焦点停留原地不会产生回调，因此"静置焦点"不顺延计时。
  void onFocusChanged(FocusNode? primaryFocus) {
    if (!_active) return;
    for (final root in focusRoots()) {
      if (containsFocus(root, primaryFocus)) {
        reset();
        return;
      }
    }
  }

  /// 控件根内按键事件：不消费事件（返回 ignored），仅顺延计时。
  KeyEventResult onKeyEvent(FocusNode node, KeyEvent event) {
    reset();
    return KeyEventResult.ignored;
  }

  void dispose() => cancel();

  void _fire() {
    _timer = null;
    if (!_active) return;
    onHide();
  }

  /// [candidate] 是否为 [root] 自身或其后代焦点。
  static bool containsFocus(FocusNode root, FocusNode? candidate) =>
      candidate != null &&
      (candidate == root || candidate.ancestors.contains(root));
}
