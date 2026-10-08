import 'package:flutter/material.dart';

import 'package:himi_syncwatch/models/episode_info.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 选集面板（放进 [SelectorSidePanel] 右侧浮层，滚动由本组件提供）。
///
/// 竖排剧集卡片：16:9 缩略图在上、标题在下（`1.集名` 样式），当前集
/// 主色描边 + 对勾高亮。TV 每卡可聚焦（D-pad 上下移动，OK 切集）。
class EpisodeSelectPanel extends StatefulWidget {
  const EpisodeSelectPanel({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeSelected,
    this.focusNode,
  });

  /// 完整剧集列表（与播放器 `_episodes` 对齐）。
  final List<EpisodeInfo> episodes;

  /// 当前播放集下标；-1 = 未选定（不高亮）。
  final int currentIndex;

  /// 点击卡片回调（父层负责切集并关闭面板）。
  final ValueChanged<int> onEpisodeSelected;

  /// TV 打开面板后精确落焦的卡：当前集，未选定回退第一集。
  final FocusNode? focusNode;

  /// 卡片标题：剧集 `number.name`（截图样式 `1.沈家灭门，嘉兰入林府`），
  /// number 缺失（0）直接用名字；电影用名字。
  @visibleForTesting
  static String cardTitle(EpisodeInfo ep) {
    if (ep.isMovie || ep.number <= 0) return ep.name;
    return '${ep.number}.${ep.name}';
  }

  @override
  State<EpisodeSelectPanel> createState() => _EpisodeSelectPanelState();
}

class _EpisodeSelectPanelState extends State<EpisodeSelectPanel> {
  /// 卡片行高估算（缩略图 16:9 + 标题 + 间距），用于打开时定位当前集。
  static const double _cardStride = 196;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 打开时把当前集滚进视口（集数多时不用手翻）
    if (widget.currentIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final target = (widget.currentIndex * _cardStride) -
            _viewportPadding;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(target.clamp(0.0, max));
      });
    }
  }

  /// 列表顶部内边距补偿（jump 目标对齐卡片顶边）。
  static const double _viewportPadding = 8;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (280 * dpr).round();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.episodes.length,
      itemBuilder: (context, index) {
        final ep = widget.episodes[index];
        final selected = index == widget.currentIndex;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TvFocusable(
            key: Key('playerEpisodeCard_$index'),
            focusNode: index == widget.currentIndex ||
                    (widget.currentIndex < 0 && index == 0)
                ? widget.focusNode
                : null,
            radius: 10,
            scale: 1.03,
            onTap: () => widget.onEpisodeSelected(index),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 缩略图：选中集主色描边（与详情页选中集高亮语言一致）
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          EmbyImage(
                            url: ep.poster,
                            fit: BoxFit.cover,
                            cacheWidth: cacheWidth,
                          ),
                          if (selected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check,
                                    size: 14, color: primary),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  EpisodeSelectPanel.cardTitle(ep),
                  key: Key('playerEpisodeTitle_$index'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
