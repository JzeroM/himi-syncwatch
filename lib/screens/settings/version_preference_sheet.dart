import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/version_preference.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/sheet_bottom_safe_area.dart';

/// 打开「视频版本偏好」设置面板（底部弹层，长按拖动 + 上移调整优先级）。
Future<void> showVersionPreferenceSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(settingsProvider).versionPreferenceOrder;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VersionPreferenceSheet(initial: current),
  );
}

class _VersionPreferenceSheet extends ConsumerStatefulWidget {
  const _VersionPreferenceSheet({required this.initial});

  final List<VersionPreference> initial;

  @override
  ConsumerState<_VersionPreferenceSheet> createState() =>
      _VersionPreferenceSheetState();
}

class _VersionPreferenceSheetState
    extends ConsumerState<_VersionPreferenceSheet> {
  late List<VersionPreference> _order = [...widget.initial];

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _order.removeAt(oldIndex);
      _order.insert(newIndex, item);
    });
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(index - 1, item);
    });
  }

  void _confirm() {
    ref
        .read(settingsProvider.notifier)
        .update(versionPreference: VersionPreference.encode(_order));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SheetBottomSafeArea(
      avoidSides: true,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '视频版本偏好',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text('长按拖动调整优先级',
                      style: TextStyle(fontSize: 13, color: Colors.white54)),
                ],
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _order.length,
                onReorder: _reorder,
                itemBuilder: (context, i) {
                  final pref = _order[i];
                  return ListTile(
                    key: ValueKey('versionPrefRow_${pref.name}'),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(pref.label, style: const TextStyle(fontSize: 16)),
                    trailing: i == 0
                        ? const SizedBox(width: 56)
                        : TextButton(
                            key: ValueKey('versionPrefUp_${pref.name}'),
                            onPressed: () => _moveUp(i),
                            child: const Text('上移'),
                          ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('versionPrefConfirm'),
                  onPressed: _confirm,
                  child: const Text('确定'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
