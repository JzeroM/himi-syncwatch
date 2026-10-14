import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/category_filter.dart';

/// 打开筛选面板（触屏底部面板 / TV 居中对话框）。
/// 返回确认后的新筛选；取消返回 null。
/// [options] 为 null 或全空时隐藏类型/年份/分级分组（仅剩播放状态）。
///
/// 面板高度固定为 0.5 屏高且**不可拖拽**（v1.1.234）——原先用
/// DraggableScrollableSheet 占 0.7 屏，选中标签换行堆高后整体过高；
/// 现标签改单行横滑，高度由 0.5 屏高固定承载，内部 ListView 自行滚动。
Future<CategoryFilter?> showMediaFilterPanel(
  BuildContext context, {
  required CategoryFilter current,
  MediaFilterOptions? options,
  bool tvMode = false,
}) {
  if (tvMode) {
    return showDialog<CategoryFilter>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            // 与触屏同源：0.5 屏高，但给 1080p/4K 大屏留上限，避免占半屏过高
            maxHeight: (MediaQuery.sizeOf(ctx).height * 0.5).clamp(360.0, 560.0),
          ),
          child: SizedBox(
            width: 420,
            child: _FilterPanelBody(current: current, options: options),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<CategoryFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // 关闭下滑手势（面板本身已不可拖拽，避免半拖状态）
    enableDrag: false,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.5,
        child: _FilterPanelBody(current: current, options: options),
      ),
    ),
  );
}

/// 面板主体：草稿筛选 + 恢复默认 + 取消/确认。确认时 pop 出草稿结果。
class _FilterPanelBody extends StatefulWidget {
  const _FilterPanelBody({
    required this.current,
    required this.options,
  });

  final CategoryFilter current;
  final MediaFilterOptions? options;

  @override
  State<_FilterPanelBody> createState() => _FilterPanelBodyState();
}

class _FilterPanelBodyState extends State<_FilterPanelBody> {
  late CategoryFilter _draft = widget.current;

  void _confirm() => Navigator.of(context).pop(_draft);

  void _reset() => setState(() => _draft = CategoryFilter.empty);

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final textTheme = Theme.of(context).textTheme;

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '筛选',
                style: textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              key: const Key('filterResetButton'),
              onPressed: _reset,
              child: const Text('恢复默认'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _WatchStatusRow(
          value: _draft.watchStatus,
          onChanged: (v) => setState(() => _draft = _draft.copyWith(watchStatus: v)),
        ),
        if (options != null && options.hasGenres) ...[
          const SizedBox(height: 8),
          _MultiPickRow<String>(
            label: '类型',
            allOptions: options.genres,
            selected: _draft.genres,
            labelOf: (v) => v,
            onDeleted: (v) =>
                setState(() => _draft = _draft.copyWith(genres: {..._draft.genres}..remove(v))),
            onAdd: () => _pick<String>(
              title: '类型',
              options: options.genres,
              selected: _draft.genres,
              labelOf: (v) => v,
            ).then((picked) {
              if (picked != null && mounted) {
                setState(() => _draft = _draft.copyWith(genres: picked));
              }
            }),
          ),
        ],
        if (options != null && options.hasYears) ...[
          const SizedBox(height: 8),
          _MultiPickRow<int>(
            label: '年份',
            allOptions: options.years,
            selected: _draft.years,
            labelOf: (v) => v.toString(),
            onDeleted: (v) =>
                setState(() => _draft = _draft.copyWith(years: {..._draft.years}..remove(v))),
            onAdd: () => _pick<int>(
              title: '年份',
              options: options.years,
              selected: _draft.years,
              labelOf: (v) => v.toString(),
            ).then((picked) {
              if (picked != null && mounted) {
                setState(() => _draft = _draft.copyWith(years: picked));
              }
            }),
          ),
        ],
        if (options != null && options.hasRatings) ...[
          const SizedBox(height: 8),
          _MultiPickRow<String>(
            label: '官方分级',
            allOptions: options.ratings,
            selected: _draft.ratings,
            labelOf: (v) => v,
            onDeleted: (v) => setState(
                () => _draft = _draft.copyWith(ratings: {..._draft.ratings}..remove(v))),
            onAdd: () => _pick<String>(
              title: '官方分级',
              options: options.ratings,
              selected: _draft.ratings,
              labelOf: (v) => v,
            ).then((picked) {
              if (picked != null && mounted) {
                setState(() => _draft = _draft.copyWith(ratings: picked));
              }
            }),
          ),
        ],
      ],
    );

    return Column(
      key: const Key('filterPanelBody'),
      children: [
        Expanded(child: body),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const Key('filterCancelButton'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('filterConfirmButton'),
                onPressed: _confirm,
                child: const Text('确认'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 打开二级复选弹窗；确认返回新集合，取消返回 null。
  Future<Set<T>?> _pick<T>({
    required String title,
    required List<T> options,
    required Set<T> selected,
    required String Function(T) labelOf,
  }) {
    return showDialog<Set<T>>(
      context: context,
      builder: (ctx) => _MultiPickDialog<T>(
        title: title,
        options: options,
        selected: selected,
        labelOf: labelOf,
      ),
    );
  }
}

/// 播放状态下拉行。
class _WatchStatusRow extends StatelessWidget {
  const _WatchStatusRow({required this.value, required this.onChanged});

  final WatchStatusFilter value;
  final ValueChanged<WatchStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('播放状态'),
        const Spacer(),
        DropdownButton<WatchStatusFilter>(
          value: value,
          items: [
            for (final s in WatchStatusFilter.values)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

/// 多选行：标签 + 已选 chips（可逐个删除）+ 「+」添加按钮。
///
/// 已选 chips **不换行**（v1.1.234）：单行横向滚动，避免选中多项时把
/// 面板撑高（原先 Wrap 逐行堆高，面板显得过高）。
class _MultiPickRow<T> extends StatelessWidget {
  const _MultiPickRow({
    required this.label,
    required this.allOptions,
    required this.selected,
    required this.labelOf,
    required this.onDeleted,
    required this.onAdd,
  });

  final String label;
  final List<T> allOptions;
  final Set<T> selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onDeleted;
  final VoidCallback onAdd;

  /// 单行 chips 高度（InputChip + 上下留白）。
  static const double rowHeight = 40;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            IconButton(
              key: Key('filterAdd_${label}_button'),
              icon: const Icon(Icons.add),
              color: primary,
              onPressed: onAdd,
            ),
          ],
        ),
        if (selected.isNotEmpty)
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // 嵌在竖向 ListView 内，关闭 primary 并用 clamping，TV 横滑稳定
              primary: false,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(right: 4),
              itemCount: selected.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final v = selected.elementAt(i);
                return InputChip(
                  key: Key('filterChip_${label}_${labelOf(v)}'),
                  label: Text(labelOf(v)),
                  onDeleted: () => onDeleted(v),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 二级复选弹窗（类型 / 年份 / 官方分级共用）。
class _MultiPickDialog<T> extends StatefulWidget {
  const _MultiPickDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
  });

  final String title;
  final List<T> options;
  final Set<T> selected;
  final String Function(T) labelOf;

  @override
  State<_MultiPickDialog<T>> createState() => _MultiPickDialogState<T>();
}

class _MultiPickDialogState<T> extends State<_MultiPickDialog<T>> {
  late Set<T> _checked = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in widget.options)
              CheckboxListTile(
                key: Key('filterPick_${widget.title}_${widget.labelOf(option)}'),
                value: _checked.contains(option),
                contentPadding: EdgeInsets.zero,
                title: Text(widget.labelOf(option)),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _checked.add(option);
                    } else {
                      _checked.remove(option);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: Key('filterPick_${widget.title}_confirm'),
          onPressed: () => Navigator.of(context).pop(_checked),
          child: const Text('确认'),
        ),
      ],
    );
  }
}
