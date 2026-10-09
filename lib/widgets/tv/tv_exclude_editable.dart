import 'package:flutter/widgets.dart';

/// TV 模式下屏蔽可编辑文本控件的焦点。
///
/// TV directional 导航下 `TextField` 可聚焦，但 `DefaultTextEditingShortcuts`
/// 会吞掉全部方向键（焦点永远出不去），且 TV 无输入法本就打不了字——
/// TV 下一律跳过输入框，配置走扫码（服务器管理/弹幕配置均有扫码管道）。
/// 非 TV 原样返回。
Widget tvExcludeEditable({required bool tvMode, required Widget child}) {
  if (!tvMode) return child;
  return ExcludeFocus(child: child);
}
