import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

Future<bool> showTvConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _TvConfirmDialog(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _TvConfirmDialog extends StatelessWidget {
  const _TvConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      ),
      actions: [
        _TvDialogAction(
          key: const ValueKey('tvConfirmCancel'),
          label: cancelLabel,
          autofocus: true,
          onTap: () => Navigator.of(context).pop(false),
        ),
        _TvDialogAction(
          key: const ValueKey('tvConfirmOk'),
          label: confirmLabel,
          destructive: destructive,
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

class _TvDialogAction extends StatelessWidget {
  const _TvDialogAction({
    super.key,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        destructive ? colorScheme.error : colorScheme.onSurfaceVariant;
    final background = destructive
        ? colorScheme.error.withValues(alpha: 0.14)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final border = destructive
        ? colorScheme.error.withValues(alpha: 0.45)
        : colorScheme.outlineVariant.withValues(alpha: 0.4);

    return TvFocusable(
      autofocus: autofocus,
      scale: 1.0,
      radius: 10,
      onTap: onTap,
      child: Semantics(
        button: true,
        label: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
