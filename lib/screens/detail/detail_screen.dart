import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/screens/detail/episode_number_picker.dart';
import 'package:himi_syncwatch/screens/detail/series_sections.dart';
import 'package:himi_syncwatch/screens/detail/track_selectors.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/services/ui/button_styles.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  final bool roomMode;
  final String? roomCode;

  /// 来源服务器本地配置 id（跨服务器详情）；null = 当前激活服务器。
  final String? serverId;

  const DetailScreen({
    super.key,
    required this.itemId,
    this.roomMode = false,
    this.roomCode,
    this.serverId,
  });

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  MediaItem? _item;
  List<MediaItem> _episodes = [];
  List<MediaItem> _similarItems = [];

  /// 剧集的季列表（服务端 Seasons 优先，为空则从集分组合成，见 [_synthSeasons]）。
  List<MediaItem> _seasons = [];

  /// 当前选中季号（与选季下拉/季卡/剧集行联动）。
  int? _selectedSeason;

  /// 选集器选中的集 id（「开始播放」播这一集；切季时重置）。
  String? _selectedEpisodeId;

  /// 剧集正序/倒序（横卡行与选集网格共用）。
  bool _sortDescending = false;

  /// 版本选择器选中的媒体版本 id（null = 未选/默认）。
  /// 选中后字幕/音轨列表切换为该版本的轨，播放入口直接使用该版本。
  String? _selectedMediaSourceId;

  /// 横卡行挂点与水平滚动控制器：选集后定位高亮卡。
  final _episodeRowKey = GlobalKey();
  final _episodeRowController = ScrollController();

  /// 操作行（开始播放/建房）挂点：选集后垂直滚动的锚，保证按钮可见。
  final _actionRowKey = GlobalKey();

  bool _isLoading = true;
  String? _error;
  bool _overviewExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _episodeRowController.dispose();
    super.dispose();
  }

  /// 跨服务器路由透传参数
  String get _serverQuery => widget.serverId != null
      ? '&server=${Uri.encodeComponent(widget.serverId!)}'
      : '';

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final embyService = ref.read(embyServiceForProvider(widget.serverId));
      final item = await embyService.getItemDetails(widget.itemId);

      if (item != null) {
        final futures = <Future>[];

        if (item.isSeries) {
          futures.add(
            embyService
                .getItems(
              parentId: widget.itemId,
              includeItemTypes: 'Episode',
              sortBy: 'ParentIndexNumber,IndexNumber',
              fields:
                  'ImageTags,PrimaryImageAspectRatio,ProductionYear,Overview,Genres,MediaStreams,MediaSources,PremiereDate',
            )
                .then((episodes) {
              _episodes = episodes;
            }),
          );
          futures.add(embyService.getSeasons(widget.itemId).then((seasons) {
            _seasons = seasons;
          }));
        }

        futures.add(
          embyService.getSimilarItems(widget.itemId).then((similar) {
            _similarItems = similar;
          }),
        );

        await Future.wait(futures);
      }

      if (item != null && item.isSeries) {
        // 服务端季列表为空时按集分组兜底，保证分季 UI 永远可用
        if (_seasons.isEmpty) _seasons = _synthSeasons(_episodes);
        _selectedSeason = _seasons.isEmpty
            ? null
            : SeriesSections.seasonNumber(_seasons.first, 0);
      }

      setState(() {
        _item = item;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 服务端季列表为空时的兜底：按集的 `parentIndexNumber` 分组合成季
  /// （无季海报，`childCount` = 组内集数），保证分季 UI 始终可用。
  List<MediaItem> _synthSeasons(List<MediaItem> episodes) {
    final numbers =
        episodes.map((e) => e.parentIndexNumber ?? 0).toSet().toList()..sort();
    return [
      for (final n in numbers)
        MediaItem(
          id: 'season_$n',
          name: '第$n季',
          type: 'Season',
          indexNumber: n,
          childCount:
              episodes.where((e) => (e.parentIndexNumber ?? 0) == n).length,
        ),
    ];
  }

  /// 点击剧集卡：仅设为选中集（图片描边高亮），不进播放器。
  /// 播放统一走「开始播放」→ [_playEpisode]。
  void _selectEpisode(MediaItem ep) {
    if (_selectedEpisodeId != ep.id) {
      setState(() => _selectedEpisodeId = ep.id);
    }
  }

  /// 从指定集开播：整部序列化进 [pendingRoomEpisodesProvider] 后跳播放器。
  void _playEpisode(MediaItem ep) {
    final episodesJson = _episodes
        .map((e) => {
              'id': e.id,
              'name': e.name,
              'season': e.parentIndexNumber ?? 0,
              'number': e.indexNumber ?? 0,
              'poster': e.posterUrl ?? '',
              'seriesName': _item!.name,
              if (widget.serverId != null) 'serverId': widget.serverId,
            })
        .toList();
    ref.read(pendingRoomEpisodesProvider.notifier).state = episodesJson;
    if (mounted) {
      context.push('/player/${ep.id}?isHost=true$_serverQuery');
    }
  }

  /// 当前选中季的集（按集号正序）。
  List<MediaItem> _seasonEpisodesOf(int? season) => _episodes
      .where((e) => (e.parentIndexNumber ?? 0) == (season ?? 0))
      .toList()
    ..sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));

  /// 当前选中版本的 MediaSource（未选或已失效返回 null）。
  MediaSource? _selectedSource(MediaItem item) {
    final id = _selectedMediaSourceId;
    if (id == null) return null;
    for (final s in item.mediaSources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 当前生效的字幕流：选中版本 → 该版本的轨；否则回退顶层流（默认行为）。
  List<MediaStream> _currentSubtitleStreams() {
    final item = _item;
    if (item == null) return const [];
    final source = _selectedSource(item);
    if (source != null) return source.subtitleStreams;
    return item.mediaStreams.where((s) => s.type == 'Subtitle').toList();
  }

  /// 当前生效的音轨流（同上）。
  List<MediaStream> _currentAudioStreams() {
    final item = _item;
    if (item == null) return const [];
    final source = _selectedSource(item);
    if (source != null) return source.audioStreams;
    return item.mediaStreams.where((s) => s.type == 'Audio').toList();
  }

  /// 打开版本选择器（与字幕/音轨同一图标行，选择后联动轨列表与播放入口）。
  void _openVersionSelector() {
    final item = _item;
    if (item == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '选择版本',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            for (final source in item.mediaSources)
              ListTile(
                key: Key('versionOption_${source.id}'),
                leading: Icon(
                  _selectedMediaSourceId == source.id
                      ? Icons.check_circle
                      : Icons.movie_outlined,
                  color: _selectedMediaSourceId == source.id
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(source.name),
                subtitle: Text(source.displayLabel),
                onTap: () {
                  Navigator.pop(ctx);
                  _onVersionSelected(source);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 切换版本（联动核心）：
  /// 1. 记录选中版本，字幕/音轨图标与选择器的流列表随之切换
  /// 2. 已有预选轨按「语言 + 类型」迁移到新版本；匹配不到则清空该轨预选
  ///    （不同版本的 `MediaStream.index` 归属不同流集，直接沿用会错轨）
  void _onVersionSelected(MediaSource source) {
    final item = _item;
    if (item == null) return;
    final selection = ref.read(pendingTrackSelectionProvider);
    // setState 前取切换前的流，供迁移比对
    final oldAudio = _currentAudioStreams();
    final oldSubtitle = _currentSubtitleStreams();

    setState(() => _selectedMediaSourceId = source.id);
    if (selection == null || selection.isEmpty) return;

    int? migrate(
      int? index,
      List<MediaStream> from,
      List<MediaStream> to, {
      bool keepNegative = false,
    }) {
      if (index == null) return null;
      if (index < 0) return keepNegative ? index : null;
      MediaStream? old;
      for (final s in from) {
        if (s.index == index) {
          old = s;
          break;
        }
      }
      if (old == null) return null;
      final lang = old.language ?? old.displayLanguage;
      if (lang == null || lang.isEmpty) return null;
      for (final s in to) {
        final l = s.language ?? s.displayLanguage;
        if (l == lang) return s.index;
      }
      return null;
    }

    final newAudio =
        migrate(selection.audioIndex, oldAudio, source.audioStreams);
    final newSubtitle = migrate(
      selection.subtitleIndex,
      oldSubtitle,
      source.subtitleStreams,
      keepNegative: true,
    );

    final notifier = ref.read(pendingTrackSelectionProvider.notifier);
    if (newAudio == null && newSubtitle == null) {
      notifier.state = null;
    } else {
      notifier.state = TrackSelection(
        audioIndex: newAudio,
        subtitleIndex: newSubtitle,
      );
    }
  }

  /// 当前版本已选中则直接使用，否则（多版本）弹选择器。
  Future<MediaSource?> _resolveSourceForPlayback(MediaItem item) async {
    final picked = _selectedSource(item);
    if (picked != null) return picked;
    if (!item.hasMultipleVersions) return null;
    return _showVersionPicker();
  }

  /// 高亮集：选中集属于当前季则用它，否则回退该季第一集。
  String? _highlightEpisodeId(List<MediaItem> seasonEpisodes) {
    if (seasonEpisodes.isEmpty) return null;
    final selected = _selectedEpisodeId;
    if (selected != null && seasonEpisodes.any((e) => e.id == selected)) {
      return selected;
    }
    return seasonEpisodes.first.id;
  }

  /// 切换选中季：高亮/选中集随季重置。
  void _onSeasonChanged(int n) {
    setState(() {
      _selectedSeason = n;
      _selectedEpisodeId = null;
    });
  }

  /// 打开数字网格选集器（仅选中高亮，不直接播放）。
  void _openEpisodePicker() {
    final season = _selectedSeason ?? 0;
    final seasonEpisodes = _seasonEpisodesOf(_selectedSeason);
    if (seasonEpisodes.isEmpty) return;
    showEpisodeNumberPicker(
      context,
      seasonNumber: season,
      episodes: seasonEpisodes,
      highlightEpisodeId: _highlightEpisodeId(seasonEpisodes),
      sortDescending: _sortDescending,
      onToggleSort: () => setState(() => _sortDescending = !_sortDescending),
      onSelect: (ep) {
        setState(() => _selectedEpisodeId = ep.id);
        // 等 sheet 关闭动画（350ms）结束后再滚动定位横卡
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _scrollToEpisode(ep);
        });
      },
      tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
    );
  }

  /// 选集后定位：水平 jumpTo 该集图片卡；垂直以操作行（开始播放/建房）
  /// 为锚滚动，保证按钮完整可见且页面不过分靠下（无操作行时锚横卡行）。
  void _scrollToEpisode(MediaItem ep) {
    final list = _seasonEpisodesOf(_selectedSeason);
    final ordered = _sortDescending ? list.reversed.toList() : list;
    final index = ordered.indexWhere((e) => e.id == ep.id);
    if (index >= 0 && _episodeRowController.hasClients) {
      final max = _episodeRowController.position.maxScrollExtent;
      final target = (index * SeriesSections.episodeCardStride).clamp(0.0, max);
      if (_episodeRowController.offset != target) {
        _episodeRowController.jumpTo(target);
      }
    }

    final actionCtx = _actionRowKey.currentContext;
    final anchorCtx = actionCtx ?? _episodeRowKey.currentContext;
    if (anchorCtx == null) return;
    final scrollable = Scrollable.maybeOf(anchorCtx);
    if (scrollable == null) return;
    final position = scrollable.position;
    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    final anchorBox = anchorCtx.findRenderObject() as RenderBox?;
    if (viewport == null || anchorBox == null) return;
    final anchorTop =
        anchorBox.localToGlobal(Offset.zero, ancestor: viewport).dy;
    // 操作行顶贴 pinned SliverAppBar 下沿留 8px；锚横卡行时直接顶对齐+8
    final topInset = MediaQuery.of(anchorCtx).padding.top;
    final barHeight = kToolbarHeight;
    final targetOffset =
        (position.pixels + anchorTop - (topInset + barHeight + 8))
            .clamp(0.0, position.maxScrollExtent);
    if (position.pixels != targetOffset) {
      position.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  /// 剧集页「开始播放」：播选集器选中的集（未选则该季第一集）。
  Future<void> _startPlaySeries() async {
    final seasonEpisodes = _seasonEpisodesOf(_selectedSeason);
    if (seasonEpisodes.isEmpty) return;
    final selected = _selectedEpisodeId;
    final target = selected != null
        ? seasonEpisodes.firstWhere(
            (e) => e.id == selected,
            orElse: () => seasonEpisodes.first,
          )
        : seasonEpisodes.first;
    _playEpisode(target);
  }

  /// 开始播放（多版本先弹选择）。胶囊底栏与 TV 内联按钮共用一份逻辑。
  Future<void> _startPlay() async {
    final item = _item;
    if (item == null) return;

    // 版本已选（图标行联动）直接用；未选且多版本才弹选择器
    MediaSource? source = await _resolveSourceForPlayback(item);
    if (item.hasMultipleVersions && source == null) return;

    ref.read(pendingRoomMovieProvider.notifier).state = {
      'id': item.id,
      'name': item.name,
      'poster': item.posterUrl ?? '',
      if (widget.serverId != null) 'serverId': widget.serverId,
    };

    final query = StringBuffer('isHost=true$_serverQuery');
    if (source != null) {
      query.write('&mediaSourceId=${source.id}');
    }
    if (mounted) {
      context.push('/player/${item.id}?${query.toString()}');
    }
  }

  Future<void> _createRoom() async {
    if (_item == null) return;

    final agoraConfig = ref.read(agoraConfigProvider);
    if (agoraConfig == null || !agoraConfig.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('请先在「声网配置」页填写 App ID 和 App Certificate')),
        );
      }
      return;
    }

    // 1. 版本（图标行已选直接用；未选且多版本弹选择器）
    MediaSource? selectedSource = await _resolveSourceForPlayback(_item!);
    if (_item!.hasMultipleVersions && selectedSource == null) return;

    // 2. 电视剧 → 集数多选弹窗
    List<MediaItem>? selectedEpisodes;
    if (_item!.isSeries && _episodes.isNotEmpty) {
      selectedEpisodes = await _showEpisodePicker();
      if (selectedEpisodes == null) return;
    }

    // 3. Token 数量弹窗
    final tokenCount = await _showTokenCountDialog();
    if (tokenCount == null) return;

    // 4. 构建房间码（仅含连接信息，媒体数据通过 RTM 发送）
    final channel = RoomCode.generateChannelId();

    final roomCode = RoomCode.encode(
      appId: agoraConfig.appId,
      appCertificate: agoraConfig.appCertificate,
      channel: channel,
      tokenCount: tokenCount,
    );

    if (mounted) {
      final query = StringBuffer(
        'roomCode=${Uri.encodeComponent(roomCode)}&isHost=true$_serverQuery',
      );
      if (selectedSource != null) {
        query.write('&mediaSourceId=${selectedSource.id}');
      }
      // 电视剧：通过 Riverpod provider 传递完整剧集数据（避免 URL 编码问题）
      if (selectedEpisodes != null && selectedEpisodes.isNotEmpty) {
        final seriesName = _item!.name;
        final episodesJson = selectedEpisodes
            .map((e) => {
                  'id': e.id,
                  'name': e.name,
                  'season': e.parentIndexNumber ?? 0,
                  'number': e.indexNumber ?? 0,
                  'poster': e.posterUrl ?? '',
                  'seriesName': seriesName,
                  if (widget.serverId != null) 'serverId': widget.serverId,
                })
            .toList();
        ref.read(pendingRoomEpisodesProvider.notifier).state = episodesJson;
      }
      // 电影：通过 Riverpod provider 传递电影数据
      if (!_item!.isSeries) {
        final movieData = {
          'id': _item!.id,
          'name': _item!.name,
          'poster': _item!.posterUrl ?? '',
          if (widget.serverId != null) 'serverId': widget.serverId,
        };
        ref.read(pendingRoomMovieProvider.notifier).state = movieData;
      }
      context.push('/player/${_item!.id}?$query');
    }
  }

  Future<void> _addResourceToRoom() async {
    if (_item == null || widget.roomCode == null) return;

    Map<String, dynamic> result;

    if (_item!.isSeries && _episodes.isNotEmpty) {
      // 电视剧：弹出集数选择
      final selectedEpisodes = await _showEpisodePicker();
      if (selectedEpisodes == null || selectedEpisodes.isEmpty) return;

      final episodesJson = selectedEpisodes
          .map((e) => {
                'id': e.id,
                'name': e.name,
                'season': e.parentIndexNumber ?? 0,
                'number': e.indexNumber ?? 0,
                'poster': e.posterUrl ?? '',
                'seriesName': _item!.name,
              })
          .toList();

      result = {
        'itemId': _item!.id,
        'name': _item!.name,
        'poster': _item!.posterUrl ?? '',
        'isSeries': true,
        'seriesName': _item!.name,
        'episodes': episodesJson,
        if (widget.serverId != null) 'serverId': widget.serverId,
      };
    } else {
      // 电影：支持版本选择（图标行已选直接用，未选才弹）
      String? selectedMediaSourceId;
      if (widget.roomMode == true && _item!.hasMultipleVersions) {
        final already = _selectedSource(_item!);
        if (already != null) {
          selectedMediaSourceId = already.id;
        } else {
          final selectedSource = await _showVersionPicker();
          if (selectedSource == null) return;
          selectedMediaSourceId = selectedSource.id;
        }
      }
      result = {
        'itemId': _item!.id,
        'name': _item!.name,
        'poster': _item!.posterUrl ?? '',
        'isSeries': false,
        if (selectedMediaSourceId != null)
          'mediaSourceId': selectedMediaSourceId,
        if (widget.serverId != null) 'serverId': widget.serverId,
      };
    }

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<MediaSource?> _showVersionPicker() async {
    if (_item == null || !_item!.hasMultipleVersions) return null;
    return showModalBottomSheet<MediaSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择版本',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._item!.mediaSources.map((source) => ListTile(
                  leading: const Icon(Icons.movie),
                  title: Text(source.name),
                  subtitle: Text(source.displayLabel),
                  onTap: () => Navigator.pop(ctx, source),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<List<MediaItem>?> _showEpisodePicker() async {
    final selected = Set<String>.from(_episodes.map((e) => e.id));

    return showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (ctx, scrollController) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '选择要一起看的集数',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              if (selected.length == _episodes.length) {
                                selected.clear();
                              } else {
                                selected.addAll(_episodes.map((e) => e.id));
                              }
                            });
                          },
                          child: Text(
                            selected.length == _episodes.length ? '取消全选' : '全选',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: _episodes.length,
                      itemBuilder: (ctx, i) {
                        final ep = _episodes[i];
                        final isSelected = selected.contains(ep.id);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (v) {
                            setSheetState(() {
                              if (v == true) {
                                selected.add(ep.id);
                              } else {
                                selected.remove(ep.id);
                              }
                            });
                          },
                          secondary: SizedBox(
                            width: 48,
                            height: 32,
                            child: EmbyImage(
                              url: ep.posterUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                          title: Text(
                            'S${ep.parentIndexNumber ?? 0}E${ep.indexNumber ?? 0} - ${ep.name}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          '已选 ${selected.length} 集',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () {
                                  final result = _episodes
                                      .where((e) => selected.contains(e.id))
                                      .toList();
                                  Navigator.pop(ctx, result);
                                },
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<int?> _showTokenCountDialog() async {
    final controller = TextEditingController(text: '2');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('建房设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('房间最大人数', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n != null && n > 0 && n <= 100) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentUrl = _item?.backdropUrl ?? _item?.posterUrl ?? '';
    final accent = ref.watch(posterColorProvider(accentUrl)).valueOrNull;
    final base = Theme.of(context).scaffoldBackgroundColor;
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    return Scaffold(
      extendBody: true,
      body: AnimatedContainer(
        key: const Key('detailBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 16),
                        Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadDetails,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : _buildContent(accent, base),
      ),
      // 播放/建房按钮已统一进内容流（_buildActionRow），仅一起看房间
      // （roomMode）手机端保留胶囊底栏的「加入资源」入口。
      bottomNavigationBar: !tvMode && _item != null && widget.roomMode
          ? _buildBottomBar()
          : null,
    );
  }

  /// 操作区（简介上方，全平台统一）：第一行播放/建房主按钮（玻璃质感、
  /// 各占约半行），第二行字幕/音轨选择器图标行（[TrackActionRow] 内部按
  /// 轨道有无自适应显隐）。
  ///
  /// 按钮外层 [GlassContainer] 提供模糊+高光描边（glassUi 关闭时降级深色
  /// 纯色）。TV 模式下 [TvFocusable] 提供焦点环/放大，第一个按钮 autofocus；
  /// ExcludeFocus 防止内外双焦点节点浪费方向键（Enter 走外层 onTap，
  /// 触摸走按钮 onPressed，两处引用同一方法，各只触发一次）。
  Widget _buildActionRow() {
    final item = _item!;
    final scheme = Theme.of(context).colorScheme;
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    var isFirst = true;

    // 玻璃按钮统一外观：透明底、白字、主色图标、48 高
    ButtonStyle glassStyle() => FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shadowColor: Colors.transparent,
        );

    Widget action({
      required Future<void> Function() run,
      required double radius,
      required Widget button,
    }) {
      final glass = GlassContainer(
        borderRadius: BorderRadius.circular(radius),
        padding: EdgeInsets.zero,
        child: button,
      );
      if (!tvMode) return glass;
      final autofocus = isFirst;
      isFirst = false;
      return TvFocusable(
        autofocus: autofocus,
        radius: radius,
        onTap: run,
        child: ExcludeFocus(child: glass),
      );
    }

    final children = <Widget>[];
    if (widget.roomMode) {
      // TV 模式取消房间模式：房间相关操作全部隐藏
      if (!tvMode) {
        children.add(action(
          run: _addResourceToRoom,
          radius: 14,
          button: FilledButton.icon(
            onPressed: _addResourceToRoom,
            icon: Icon(Icons.add, color: scheme.primary),
            label: const Text('加入资源'),
            style: glassStyle(),
          ),
        ));
      }
    } else {
      // 剧集无集数据时隐藏播放按钮（点了无事发生会误导）
      if (!item.isSeries || _episodes.isNotEmpty) {
        children.add(action(
          run: item.isSeries ? _startPlaySeries : _startPlay,
          radius: 14,
          button: FilledButton.icon(
            onPressed: item.isSeries ? _startPlaySeries : _startPlay,
            icon: Icon(Icons.play_arrow, color: scheme.primary),
            label: const Text('开始播放'),
            style: glassStyle(),
          ),
        ));
      }
      // TV 模式取消房间模式：不提供建房入口
      if (!tvMode) {
        children.add(action(
          run: _createRoom,
          radius: 14,
          button: FilledButton.icon(
            onPressed: _createRoom,
            icon: Icon(Icons.group_add, color: scheme.primary),
            label: const Text('建房'),
            style: glassStyle(),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ],
        ),
        const SizedBox(height: 4),
        TrackActionRow(
          item: item,
          selectedMediaSourceId: _selectedMediaSourceId,
          onOpenVersion: item.hasMultipleVersions ? _openVersionSelector : null,
          subtitleStreams: _currentSubtitleStreams(),
          audioStreams: _currentAudioStreams(),
        ),
      ],
    );
  }

  /// roomMode 胶囊底栏（仅手机端渲染）：一起看房间下唯一入口「加入资源」。
  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassContainer(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _addResourceToRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('加入资源'),
                  style:
                      readableFilledButtonStyle(Theme.of(context).colorScheme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color? accent, Color base) {
    if (_item == null) return const SizedBox();
    final item = _item!;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          leading: Padding(
            padding: const EdgeInsets.all(4),
            child: GlassContainer(
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              padding: EdgeInsets.zero,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                EmbyImage(
                  url: item.backdropUrl ?? item.posterUrl,
                  fit: BoxFit.cover,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                        if (accent != null)
                          Color.lerp(accent, base, 0.6)!
                        else
                          Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item.communityRating != null) ...[
                            const Icon(Icons.star,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              item.communityRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          if (item.officialRating != null) ...[
                            _MetaBadge(text: item.officialRating!),
                            const SizedBox(width: 16),
                          ],
                          if (item.year != null)
                            Text(
                              item.year!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          if (item.runtimeText != null) ...[
                            const SizedBox(width: 16),
                            Text(
                              item.runtimeText!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                          if (_has4k(item)) ...[
                            const SizedBox(width: 16),
                            const _MetaBadge(text: '4K'),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.genres.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.genres
                        .map((g) => Chip(
                              label:
                                  Text(g, style: const TextStyle(fontSize: 13)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                // 非 TV roomMode 的入口统一走底部胶囊（避免双入口）
                if (!(widget.roomMode &&
                    !ref.watch(settingsProvider.select((s) => s.tvMode)))) ...[
                  KeyedSubtree(
                    key: _actionRowKey,
                    child: _buildActionRow(),
                  ),
                  const SizedBox(height: 16),
                ],
                if (item.overview != null && item.overview!.isNotEmpty) ...[
                  const Text(
                    '简介',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  AnimatedCrossFade(
                    firstChild: Text(
                      item.overview!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    secondChild: Text(
                      item.overview!,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    crossFadeState: _overviewExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                  if (item.overview!.length > 100)
                    TvFocusable(
                      onTap: () => setState(
                          () => _overviewExpanded = !_overviewExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _overviewExpanded ? '收起' : '更多',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
                if (item.mediaStreams.isNotEmpty) ...[
                  _buildMediaInfo(item),
                  const SizedBox(height: 20),
                ],
                if (item.hasMultipleVersions) ...[
                  _buildMediaSources(item),
                  const SizedBox(height: 20),
                ],
                if (item.isSeries && _seasons.isNotEmpty) ...[
                  SeriesSections(
                    seasons: _seasons,
                    episodes: _episodes,
                    selectedSeason: _selectedSeason,
                    onSeasonSelected: _onSeasonChanged,
                    onEpisodeSelect: _selectEpisode,
                    onToggleSort: () =>
                        setState(() => _sortDescending = !_sortDescending),
                    onOpenEpisodePicker: _openEpisodePicker,
                    sortDescending: _sortDescending,
                    highlightEpisodeId: _selectedEpisodeId,
                    episodeRowKey: _episodeRowKey,
                    episodeRowController: _episodeRowController,
                    tvMode: ref.watch(settingsProvider.select((s) => s.tvMode)),
                  ),
                ],
                if (_similarItems.isNotEmpty) ...[
                  const Text(
                    '相似推荐',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: PosterCard.heightFor(88),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _similarItems.length,
                      itemBuilder: (context, index) {
                        final sim = _similarItems[index];
                        return SizedBox(
                          width: 96,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: PosterCard(
                              key: ValueKey('posterCard_${sim.id}'),
                              item: sim,
                              width: 88,
                              onTap: () {
                                final q = widget.serverId != null
                                    ? '?server=${Uri.encodeComponent(widget.serverId!)}'
                                    : '';
                                context.push('/detail/${sim.id}$q');
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaSources(MediaItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '可用版本',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...item.mediaSources.map((source) => Card(
              child: ListTile(
                leading: const Icon(Icons.movie_creation_outlined),
                title: Text(source.name),
                subtitle: Text(source.displayLabel),
                dense: true,
              ),
            )),
      ],
    );
  }

  Widget _buildMediaInfo(MediaItem item) {
    final videoStreams =
        item.mediaStreams.where((s) => s.type == 'Video').toList();
    final audioStreams =
        item.mediaStreams.where((s) => s.type == 'Audio').toList();
    final subtitleStreams =
        item.mediaStreams.where((s) => s.type == 'Subtitle').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (videoStreams.isNotEmpty)
          _MediaInfoRow(
            label: '版本：',
            value: videoStreams.first.displayInfo,
          ),
        if (audioStreams.isNotEmpty)
          _MediaInfoRow(
            label: '音频：',
            value: audioStreams.map((s) => s.displayInfo).join('，'),
          ),
        if (subtitleStreams.isNotEmpty)
          _MediaInfoRow(
            label: '字幕：',
            value: subtitleStreams.map((s) => s.displayInfo).join('，'),
          ),
      ],
    );
  }

  /// 是否含 4K 资源（`MediaSource.displayLabel` 对 width>=3840 输出 '4K'，
  /// 或直接看视频流宽度）。
  bool _has4k(MediaItem item) {
    if (item.mediaSources.any((s) => s.displayLabel == '4K')) return true;
    return item.mediaStreams
        .any((s) => s.type == 'Video' && (s.width ?? 0) >= 3840);
  }
}

/// 顶部徽章（TV-MA / 4K）：半透明白描边小胶囊。
class _MetaBadge extends StatelessWidget {
  final String text;
  const _MetaBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white38),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MediaInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _MediaInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
