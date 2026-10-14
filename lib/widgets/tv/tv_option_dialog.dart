import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 居中单选弹层的一个选项。
class TvOptionEntry<T> {
  const TvOptionEntry({
    required this.value,
    required this.label,
    this.subtitle,
    this.key,
  });

  final T value;
  final String label;
  final String? subtitle;

  /// 行测试键（调用方按旧键名传入，保持既有测试可用）。
  final Key? key;
}

/// 居中单选弹层：标题 + 选项列表（超长滚动），TV 遥控 D-pad 上下切换 +
/// OK 选择，触屏点选，点外部关闭。
///
/// 实现要点：
/// - **不用 `RadioGroup`/`RadioListTile`**：其自带方向键内层 Shortcut 会
///   在 `TvRemoteShortcuts`（MaterialApp.builder）之前劫持方向键并直接
///   触发 `onChanged`（调用方通常立即 pop）——TV 下第一次方向键导航就
///   关闭弹层/跳选，即「选择面板焦点不能上下切换」的根因。
/// - 行控件 `TvFocusable`（非 TV 降级 GestureDetector，与播放器
///   `SideOptionRow` 同交互）；当前值行 `autofocus` 打开即落焦。
/// - `showDialog` 天然居中，复用主题 `dialogTheme`。
Future<T?> showTvOptionDialog<T>({
  required BuildContext context,
  required String title,
  required List<TvOptionEntry<T>> options,
  required T currentValue,
  required ValueChanged<T> onSelected,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => _TvOptionDialog<T>(
      title: title,
      options: options,
      currentValue: currentValue,
      onSelected: onSelected,
    ),
  );
}

class _TvOptionDialog<T> extends StatelessWidget {
  const _TvOptionDialog({
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelected,
  });

  final String title;
  final List<TvOptionEntry<T>> options;
  final T currentValue;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    // 当前值行落焦；值不在列表中（异常数据）时回退第一行。
    final autofocusIndex = options.indexWhere((e) => e.value == currentValue);
    return AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < options.length; i++)
                  _TvOptionRow<T>(
                    entry: options[i],
                    selected: options[i].value == currentValue,
                    autofocus: i == (autofocusIndex < 0 ? 0 : autofocusIndex),
                    onTap: () {
                      Navigator.of(context).pop(options[i].value);
                      onSelected(options[i].value);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvOptionRow<T> extends StatelessWidget {
  const _TvOptionRow({
    required this.entry,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final TvOptionEntry<T> entry;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      key: entry.key,
      autofocus: autofocus,
      radius: 8,
      scale: 1.0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: 18,
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
