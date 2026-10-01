import 'package:flutter/material.dart';

/// 高对比可读的填充按钮样式。
///
/// 主题 `ColorScheme.fromSeed(brightness: dark)` 的 `primary` 可能是亮色，
/// 固定白字会看不清；用规范配对的 `onPrimary` 作前景（亮底自动配深字），
/// 文字在任何主题色下都可读。
ButtonStyle readableFilledButtonStyle(ColorScheme scheme) {
  return FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 14),
    backgroundColor: scheme.primary,
    foregroundColor: scheme.onPrimary,
  );
}
