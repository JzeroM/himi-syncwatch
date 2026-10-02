import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 打开数字网格选集器（底部玻璃 sheet）。
///
/// - 标题「第 N 季」+ 排序切换（正序/倒序，key: [kSortToggleInSheet]）
/// - 4 列数字格显示该季各集的 `indexNumber`，滚动支持 40+ 集
/// - 高亮格 = [highlightEpisodeId]（无命中时由调用方给该季第一集）
/// - 点击格子：仅选中（[onSelect] 通知调用方更新状态，不直接播放）并关闭
/// - TV：每格 [TvFocusable] 包裹，方向键网格导航
Future<void> showEpisodeNumberPicker(
  BuildContext context, {
  required int seasonNumber,
  required List<MediaItem> episodes,
  required String? highlightEpisodeId,
  required bool sortDescending,
  required VoidCallback onToggleSort,
  required ValueChanged<MediaItem> onSelect,
  bool tvMode = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      // sheet 内排序视图状态：初值取外部，切换时同步刷新本地网格并
      // 通知外部（驱动剧集横卡行同一排序）。
      var descending = sortDescending;

      void applySort() {
        descending = !descending;
        onToggleSort();
      }

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final size = MediaQuery.sizeOf(ctx);
          final primary = Theme.of(ctx).colorScheme.primary;

          final sorted = [
            ...episodes
          ]..sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
          final display = descending ? sorted.reversed.toList() : sorted;

          return Container(
            height: size.height * 0.78,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: GlassContainer(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 拖拽把手（图中顶部短横条）
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '第 $seasonNumber 季',
                        key: const Key('episodePickerTitle'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        descending ? '倒序' : '正序',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('episodeSortToggleInSheet'),
                        icon: Icon(
                          descending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: primary,
                        ),
                        tooltip: descending ? '改为正序' : '改为倒序',
                        onPressed: () {
                          applySort();
                          setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.1,
                      ),
                      itemCount: display.length,
                      itemBuilder: (gridCtx, i) {
                        final ep = display[i];
                        final highlighted = ep.id == highlightEpisodeId;
                        final tile = Container(
                          key: Key('episodeNumber_${ep.id}'),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: highlighted ? primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            ep.indexNumber?.toString() ?? '${i + 1}',
                            style: TextStyle(
                              fontSize: 16,
                              color: highlighted ? primary : Colors.white,
                              fontWeight: highlighted
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );

                        void pick() {
                          onSelect(ep);
                          Navigator.of(ctx).pop();
                        }

                        if (!tvMode) {
                          return GestureDetector(
                            onTap: pick,
                            child: tile,
                          );
                        }
                        return TvFocusable(
                          radius: 12,
                          onTap: pick,
                          child: ExcludeFocus(child: tile),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
