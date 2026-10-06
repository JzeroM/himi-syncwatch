import 'package:flutter/material.dart';

/// TV 模式返回键双击确认层。
///
/// - [enabled]=true（TV 模式）：首按返回仅弹「再按一次…」提示，
///   [window] 窗口内第二按才执行 [onConfirm]；窗口过期重新计时；
/// - [enabled]=false（非 TV）：直接执行 [onConfirm]（保持平台默认流程，
///   如页面自身的确认对话）。
///
/// `canPop` 恒为 false：退出动作由 [onConfirm] 内部自行完成
/// （如 `Navigator.pop` / `SystemNavigator.pop`），与壳层
/// `MainShell._handleTvBack` 同一交互模式。
class TvBackConfirm extends StatefulWidget {
  const TvBackConfirm({
    super.key,
    required this.enabled,
    required this.onConfirm,
    this.onBack,
    this.confirmText = '再按一次退出播放器',
    this.window = const Duration(seconds: 2),
    this.now = DateTime.now,
    required this.child,
  });

  /// 是否启用双击确认（false = 直接 onConfirm）。
  final bool enabled;

  /// 返回键优先拦截：返回 true 表示本次返回已被消费（如收起选择器面板），
  /// 不再进入双击确认/退出流程。
  final bool Function()? onBack;

  /// 确认后的退出动作（double-confirm 后异步执行，如房间解散确认）。
  final Future<void> Function() onConfirm;

  /// 首按提示文案。
  final String confirmText;

  /// 双击判定窗口。
  final Duration window;

  /// 时间源（测试注入推进假时间验证窗口过期）。
  final DateTime Function() now;

  final Widget child;

  @override
  State<TvBackConfirm> createState() => _TvBackConfirmState();
}

class _TvBackConfirmState extends State<TvBackConfirm> {
  /// 上次按返回的时刻（null = 当前没有待确认的返回）。
  DateTime? _backAt;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        // 优先拦截：选择器面板等已消费本次返回 → 不进入退出确认
        if (widget.onBack?.call() ?? false) return;
        if (!widget.enabled) {
          await widget.onConfirm();
          return;
        }
        final t = widget.now();
        final within =
            _backAt != null && t.difference(_backAt!) < widget.window;
        _backAt = t;
        if (within) {
          await widget.onConfirm();
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.confirmText),
            duration: widget.window,
          ),
        );
      },
      child: widget.child,
    );
  }
}
