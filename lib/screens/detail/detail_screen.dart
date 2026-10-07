import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/screens/detail/episode_number_picker.dart';
import 'package:himi_syncwatch/screens/detail/media_details_section.dart';
import 'package:himi_syncwatch/screens/detail/series_sections.dart';
import 'package:himi_syncwatch/screens/detail/track_selectors.dart';
import 'package:himi_syncwatch/services/ui/button_styles.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';

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

  /// TV 整页背景图 URL：服务端默认把图缩到 400 高（`maxHeight=400`），全屏
  /// 铺开会糊。按实际显示需要请求，目标宽度夹在 [720, 1280]（TV 整页背景叠有
  /// 暗罩，1280 足够；避免拉 1920 大图导致弱设备下载/解码慢），并追加
  /// `quality=85` 压缩。空 URL 返回 null。
  @visibleForTesting
  static String? hdImageUrlFor(String? url, int targetWidth) {
    if (url == null || url.isEmpty) return null;
    final w = targetWidth.clamp(720, 1280);
    var out = url.replaceAll('maxHeight=400', 'maxWidth=$w');
    if (!out.contains('quality=')) out += '&quality=85';
    return out;
  }
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

  /// 每集的预选轨（key = 集 id）。按集隔离，多集分别设置互不覆盖；
  /// 播放该集时才写入全局 [pendingTrackSelectionProvider] 供播放器消费。
  final Map<String, TrackSelection> _episodeSelections = {};

  /// 每集选中的版本 source id（key = 集 id；null = 服务端默认版本）。
  final Map<String, String?> _episodeSourceIds = {};

  /// 主条目收藏态（电影页=电影；电视剧页=整部剧）。
  bool _isFavorite = false;

  /// 已收藏的集 id 集合（剧集页横卡爱心的乐观态）。
  final Set<String> _favoriteEpisodeIds = {};

  /// 主条目已观看态（电影页=电影；电视剧页=整部剧）。
  bool _isWatched = false;

  /// 已观看的集 id 集合（剧集页横卡对勾的乐观态）。
  final Set<String> _watchedEpisodeIds = {};

  /// 播放进度本地覆盖（标记已观看后置 0，隐藏「继续/从头播放」）。
  int? _resumeMsOverride;

  /// 横卡行挂点与水平滚动控制器：选集后定位高亮卡。
  final _episodeRowKey = GlobalKey();
  final _episodeRowController = ScrollController();

  /// 操作行（开始播放/建房）挂点：选集后垂直滚动的锚，保证按钮可见。
  final _actionRowKey = GlobalKey();

  bool _isLoading = true;
  String? _error;

  /// 海报内简介浮层开合（v1.1.83：简介默认隐藏，海报上「简介」控件展开，
  /// 正文区原简介块移除——简介只此一份）。
  bool _overviewVisible = false;

  /// 浮层收起按钮焦点：打开后焦点移入浮层（原控件被浮层遮盖），
  /// 关闭随节点销毁由焦点系统回落。
  final _overviewCloseNode = FocusNode(debugLabel: 'overviewClose');

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _episodeRowController.dispose();
    _overviewCloseNode.dispose();
    super.dispose();
  }

  /// 开关简介浮层；打开后 postFrame 把焦点移入浮层收起按钮（TV 遥控器
  /// 可控；手机端 requestFocus 无副作用）。
  void _toggleOverview() {
    setState(() => _overviewVisible = !_overviewVisible);
    if (!_overviewVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overviewVisible) _overviewCloseNode.requestFocus();
    });
  }

  /// 跨服务器路由透传参数
  String get _serverQuery => widget.serverId != null
      ? '&server=${Uri.encodeComponent(widget.serverId!)}'
      : '';

  /// [silent]：静默刷新（从播放器返回时用）——不显示 loading、失败不报错，
  /// 仅替换条目/集/季与收藏/已观看/续播状态。
  Future<void> _loadDetails({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

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
              // AlternateMediaSources：Emby 4.9.x 起批量端点对非管理员
              // 每条只回 1 个 MediaSource，需显式请求该字段才返回全部版本
              fields:
                  'ImageTags,PrimaryImageAspectRatio,ProductionYear,Overview,Genres,MediaStreams,MediaSources,AlternateMediaSources,PremiereDate,UserData,Path',
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

      final wasOfferResume = _offerResume;
      setState(() {
        _item = item;
        _isFavorite = item?.isFavorite ?? false;
        _favoriteEpisodeIds
          ..clear()
          ..addAll(_episodes.where((e) => e.isFavorite).map((e) => e.id));
        _isWatched = item?.isWatched ?? false;
        _watchedEpisodeIds
          ..clear()
          ..addAll(_episodes.where((e) => e.isWatched).map((e) => e.id));
        _resumeMsOverride = null;
        _isLoading = false;
      });
      // 继续播放按钮状态（默认 ↔ 继续）发生变化 → 立即刷新首页「继续观看」栏
      if (_offerResume != wasOfferResume) {
        ref.read(resumeRevisionProvider.notifier).state++;
      }
    } catch (e) {
      if (silent) return; // 静默刷新失败：保留原内容，不弹错误页
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 收藏 / 取消收藏主条目（电影=电影；电视剧=整部剧）。乐观更新，
  /// 失败回滚并提示；成功 bump 收藏修订号让收藏页重取。
  Future<void> _toggleFavorite() async {
    final item = _item;
    if (item == null) return;
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    final ok = await ref
        .read(embyServiceForProvider(widget.serverId))
        .setFavorite(item.id, next);
    if (!mounted) return;
    if (!ok) {
      setState(() => _isFavorite = !next);
      showAppToast(context, '收藏操作失败，请检查网络');
      return;
    }
    ref.read(favoritesRevisionProvider.notifier).state++;
  }

  /// 收藏 / 取消收藏某一集（剧集页横卡爱心）。乐观更新，失败回滚+提示。
  Future<void> _toggleEpisodeFavorite(String episodeId) async {
    final next = !_favoriteEpisodeIds.contains(episodeId);
    setState(() {
      if (next) {
        _favoriteEpisodeIds.add(episodeId);
      } else {
        _favoriteEpisodeIds.remove(episodeId);
      }
    });
    final ok = await ref
        .read(embyServiceForProvider(widget.serverId))
        .setFavorite(episodeId, next);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        if (next) {
          _favoriteEpisodeIds.remove(episodeId);
        } else {
          _favoriteEpisodeIds.add(episodeId);
        }
      });
      showAppToast(context, '收藏操作失败，请检查网络');
      return;
    }
    ref.read(favoritesRevisionProvider.notifier).state++;
  }

  /// 标记 / 取消已观看主条目（电影=电影；电视剧=整部剧）。电视剧标记时
  /// 乐观地把该剧所有集的对勾一并置为已看/未看（Emby 会级联），失败整体回滚。
  Future<void> _toggleWatched() async {
    final item = _item;
    if (item == null) return;
    final next = !_isWatched;
    final prevEpisodes = Set<String>.from(_watchedEpisodeIds);
    final prevResume = _resumeMsOverride;
    setState(() {
      _isWatched = next;
      // 标记已观看/取消后清除本地续播进度 → 播放控件恢复原形态、隐藏「从头播放」
      _resumeMsOverride = 0;
      if (item.isSeries) {
        if (next) {
          _watchedEpisodeIds.addAll(_episodes.map((e) => e.id));
        } else {
          _watchedEpisodeIds.clear();
        }
      }
    });
    final ok = await ref
        .read(embyServiceForProvider(widget.serverId))
        .setWatched(item.id, next);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _isWatched = !next;
        _resumeMsOverride = prevResume;
        _watchedEpisodeIds
          ..clear()
          ..addAll(prevEpisodes);
      });
      showAppToast(context, '标记已观看失败，请检查网络');
      return;
    }
    // 标记已观看会清除服务器续播位置 → 即时刷新首页「继续观看」栏
    ref.read(resumeRevisionProvider.notifier).state++;
  }

  /// 标记 / 取消某一集已观看（剧集页横卡对勾）。乐观更新，失败回滚+提示。
  Future<void> _toggleEpisodeWatched(String episodeId) async {
    final next = !_watchedEpisodeIds.contains(episodeId);
    setState(() {
      if (next) {
        _watchedEpisodeIds.add(episodeId);
      } else {
        _watchedEpisodeIds.remove(episodeId);
      }
    });
    final ok = await ref
        .read(embyServiceForProvider(widget.serverId))
        .setWatched(episodeId, next);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        if (next) {
          _watchedEpisodeIds.remove(episodeId);
        } else {
          _watchedEpisodeIds.add(episodeId);
        }
      });
      showAppToast(context, '标记已观看失败，请检查网络');
      return;
    }
    // 标记该集已观看清除其续播位置 → 即时刷新首页「继续观看」栏
    ref.read(resumeRevisionProvider.notifier).state++;
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
  /// [resume] 为真且该集有进度时携带 `startMs` 续播；否则从头播放并乐观清
  /// 本地续播态。返回详情页后静默刷新，读取最新进度/已观看。
  Future<void> _playEpisode(MediaItem ep, {bool resume = false}) async {
    // 该集的预选轨写入全局槽（播放器 _autoSelectDefaultTracks 消费一次）；
    // 无选择时显式置 null，防止残留上一次的电影/他集预选
    final selection = _episodeSelections[ep.id];
    ref.read(pendingTrackSelectionProvider.notifier).state =
        (selection != null && !selection.isEmpty) ? selection : null;
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
    if (!mounted) return;
    if (!resume) {
      setState(() => _resumeMsOverride = 0);
      _hideResumeOptimistically(ep.id);
      // 已观看的集重播 → 乐观复位未观看 + 服务器取消，重回续播列表
      _unwatchTargetOptimistically(ep.id, isSeries: true);
    }
    final query = StringBuffer('isHost=true$_serverQuery');
    final sourceId = _episodeSourceIds[ep.id];
    if (sourceId != null) {
      query.write('&mediaSourceId=$sourceId');
    }
    final logo = !widget.roomMode ? _item?.logoUrl : null;
    if (logo != null) {
      query.write('&logo=${Uri.encodeComponent(logo)}');
    }
    if (resume && ep.playbackPositionMs > 0) {
      query.write('&startMs=${ep.playbackPositionMs}');
    }
    // 弹幕错源排除线索：类型 + 剧集年份（同名不同版本/年份区分用）
    query.write('&kind=series');
    final seriesYear = _item?.year;
    if (seriesYear != null && seriesYear.isNotEmpty) {
      query.write('&year=$seriesYear');
    }
    await context.push('/player/${ep.id}?$query');
    if (mounted) {
      _clearResumeHidden(ep.id);
      await _loadDetails(silent: true);
    }
  }

  /// 点「重播」：立即把该条加入首页「继续观看」乐观隐藏集合 + bump 修订号
  /// → 首页即时移除该条（不等服务器上报）。
  void _hideResumeOptimistically(String id) {
    final notifier = ref.read(resumeOptimisticHiddenProvider.notifier);
    if (!notifier.state.contains(id)) {
      notifier.state = {...notifier.state, id};
    }
    ref.read(resumeRevisionProvider.notifier).state++;
  }

  /// 从头播放「已观看」目标：乐观复位为未观看并调用服务器取消 `Played`，
  /// 使该条重新进入 Emby 续播列表（随后进度上报成功即回填首页栏）。
  /// 电影=主条目 [isSeries]=false；电视剧=该集 [isSeries]=true。
  void _unwatchTargetOptimistically(String targetId, {required bool isSeries}) {
    if (isSeries) {
      if (!_watchedEpisodeIds.contains(targetId)) return;
      setState(() => _watchedEpisodeIds.remove(targetId));
    } else {
      if (!_isWatched) return;
      setState(() => _isWatched = false);
    }
    unawaited(
      ref
          .read(embyServiceForProvider(widget.serverId))
          .setWatched(targetId, false),
    );
  }

  /// 从播放器返回/上报成功：解除乐观隐藏，交回服务器真相驱动显示。
  void _clearResumeHidden(String id) {
    final notifier = ref.read(resumeOptimisticHiddenProvider.notifier);
    if (notifier.state.contains(id)) {
      notifier.state = {...notifier.state}..remove(id);
    }
    ref.read(resumeRevisionProvider.notifier).state++;
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

  // ---- 每集（方案 A）：选择器绑到选中集 ----

  /// 目标集（选择器与播放入口绑它）：选中集 → 当前季第一集（与
  /// [_startPlaySeries] 的回退一致）；非剧集或无集时 null。
  MediaItem? _targetEpisode() {
    if (_item?.isSeries != true || _episodes.isEmpty) return null;
    final selected = _selectedEpisodeId;
    if (selected != null) {
      for (final e in _episodes) {
        if (e.id == selected) return e;
      }
    }
    final seasonEpisodes = _seasonEpisodesOf(_selectedSeason);
    if (seasonEpisodes.isNotEmpty) return seasonEpisodes.first;
    return _episodes.first;
  }

  /// 续播目标：电影=主条目；电视剧=当前选中集（播放按钮播的就是它）。
  MediaItem? get _resumeItem =>
      _item == null ? null : (_item!.isSeries ? _targetEpisode() : _item);

  int get _resumeMs =>
      _resumeMsOverride ?? _resumeItem?.playbackPositionMs ?? 0;

  double get _resumePct =>
      (_resumeItem?.playedPercentage ?? 0).clamp(0.0, 100.0);

  /// 播放目标是否已观看：电影=主条目；电视剧=当前选中集（播放按钮播的就是它）。
  bool get _targetWatched {
    final item = _item;
    if (item == null) return false;
    if (!item.isSeries) return _isWatched;
    final target = _targetEpisode();
    return target != null && _watchedEpisodeIds.contains(target.id);
  }

  /// 是否展示「继续」形态（目标有进度且目标未标记已观看）。
  bool get _offerResume => _resumeMs > 0 && !_targetWatched;

  /// `mm:ss` / `h:mm:ss`。
  String _formatPosition(int ms) {
    final total = (ms / 1000).floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// 目标集选中版本的字幕流；未选版本回退该集顶层流。
  List<MediaStream> _episodeSubtitleStreams(MediaItem ep) {
    final sourceId = _episodeSourceIds[ep.id];
    if (sourceId != null) {
      for (final s in ep.mediaSources) {
        if (s.id == sourceId) return s.subtitleStreams;
      }
    }
    return ep.mediaStreams.where((s) => s.type == 'Subtitle').toList();
  }

  /// 目标集选中版本的音轨流（同上）。
  List<MediaStream> _episodeAudioStreams(MediaItem ep) {
    final sourceId = _episodeSourceIds[ep.id];
    if (sourceId != null) {
      for (final s in ep.mediaSources) {
        if (s.id == sourceId) return s.audioStreams;
      }
    }
    return ep.mediaStreams.where((s) => s.type == 'Audio').toList();
  }

  /// 打开目标集的版本选择器；预选轨按语言迁移到新版本。
  void _openEpisodeVersionSelector(MediaItem ep) {
    showVersionSelector(
      context,
      sources: ep.mediaSources,
      currentId: _episodeSourceIds[ep.id],
      onSelected: (source) {
        // setState 前取切换前的流，供语言迁移比对
        final oldSelection = _episodeSelections[ep.id];
        final oldAudio = _episodeAudioStreams(ep);
        final oldSubtitle = _episodeSubtitleStreams(ep);
        setState(() {
          _episodeSourceIds[ep.id] = source.id;
          if (oldSelection != null && !oldSelection.isEmpty) {
            final migrated = migrateTrackSelection(
              oldSelection,
              oldAudio: oldAudio,
              newAudio: source.audioStreams,
              oldSubtitle: oldSubtitle,
              newSubtitle: source.subtitleStreams,
            );
            if (migrated == null) {
              _episodeSelections.remove(ep.id);
            } else {
              _episodeSelections[ep.id] = migrated;
            }
          }
        });
      },
    );
  }

  /// 写目标集的预选轨（[TrackActionRow] 的 onSelectionChanged）。
  void _setEpisodeSelection(String episodeId, TrackSelection next) {
    setState(() {
      if (next.isEmpty) {
        _episodeSelections.remove(episodeId);
      } else {
        _episodeSelections[episodeId] = next;
      }
    });
  }

  /// 打开版本选择器（与字幕/音轨同一图标行，选择后联动轨列表与播放入口）。
  void _openVersionSelector() {
    final item = _item;
    if (item == null) return;
    showVersionSelector(
      context,
      sources: item.mediaSources,
      currentId: _selectedMediaSourceId,
      onSelected: _onVersionSelected,
    );
  }

  /// 切换版本（联动核心）：
  /// 1. 记录选中版本，字幕/音轨图标与选择器的流列表随之切换
  /// 2. 已有预选轨按「语言 + 类型」迁移到新版本；匹配不到则清空该轨预选
  ///    （迁移逻辑见 [migrateTrackSelection] 纯函数，与每集版本切换共用）
  void _onVersionSelected(MediaSource source) {
    final selection = ref.read(pendingTrackSelectionProvider);
    // setState 前取切换前的流，供迁移比对
    final oldAudio = _currentAudioStreams();
    final oldSubtitle = _currentSubtitleStreams();

    setState(() => _selectedMediaSourceId = source.id);
    if (selection == null || selection.isEmpty) return;

    final migrated = migrateTrackSelection(
      selection,
      oldAudio: oldAudio,
      newAudio: source.audioStreams,
      oldSubtitle: oldSubtitle,
      newSubtitle: source.subtitleStreams,
    );
    ref.read(pendingTrackSelectionProvider.notifier).state = migrated;
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

  /// 当前选中季的显示名（Emby 自带季名；按选中季号匹配季列表）。
  String _seasonTitleOf(int? seasonNumber) {
    for (var i = 0; i < _seasons.length; i++) {
      if (SeriesSections.seasonNumber(_seasons[i], i) == seasonNumber) {
        return SeriesSections.seasonTitle(_seasons[i], i);
      }
    }
    return '第 ${seasonNumber ?? 0} 季';
  }

  /// 打开数字网格选集器（仅选中高亮，不直接播放）。
  void _openEpisodePicker() {
    final seasonEpisodes = _seasonEpisodesOf(_selectedSeason);
    if (seasonEpisodes.isEmpty) return;
    showEpisodeNumberPicker(
      context,
      seasonTitle: _seasonTitleOf(_selectedSeason),
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
  Future<void> _startPlaySeries({bool resume = false}) async {
    final seasonEpisodes = _seasonEpisodesOf(_selectedSeason);
    if (seasonEpisodes.isEmpty) return;
    final selected = _selectedEpisodeId;
    final target = selected != null
        ? seasonEpisodes.firstWhere(
            (e) => e.id == selected,
            orElse: () => seasonEpisodes.first,
          )
        : seasonEpisodes.first;
    await _playEpisode(target, resume: resume);
  }

  /// 开始播放（多版本先弹选择）。胶囊底栏与 TV 内联按钮共用一份逻辑。
  /// [resume] 为真且当前条目有进度时携带 `startMs` 续播。
  Future<void> _startPlay({bool resume = false}) async {
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
    final logo = !widget.roomMode ? item.logoUrl : null;
    if (logo != null) {
      query.write('&logo=${Uri.encodeComponent(logo)}');
    }
    if (resume && item.playbackPositionMs > 0) {
      query.write('&startMs=${item.playbackPositionMs}');
    }
    // 弹幕错源排除线索：类型 + 年份（同名不同版本/年份区分用）
    query.write('&kind=movie');
    final movieYear = item.year;
    if (movieYear != null && movieYear.isNotEmpty) {
      query.write('&year=$movieYear');
    }
    if (!mounted) return;
    // 从头播放：乐观清本地续播态（主控件立刻恢复默认）+ 首页立即移除该条
    if (!resume) {
      setState(() => _resumeMsOverride = 0);
      _hideResumeOptimistically(item.id);
      // 已观看的电影重播 → 乐观复位未观看 + 服务器取消，重回续播列表
      _unwatchTargetOptimistically(item.id, isSeries: false);
    }
    await context.push('/player/${item.id}?${query.toString()}');
    if (mounted) {
      _clearResumeHidden(item.id);
      await _loadDetails(silent: true);
    }
  }

  Future<void> _createRoom() async {
    if (_item == null) return;

    final agoraConfig = ref.read(agoraConfigProvider);
    if (agoraConfig == null || !agoraConfig.isConfigured) {
      if (mounted) {
        showAppToast(context, '请先在「声网配置」页填写 App ID 和 App Certificate');
      }
      return;
    }

    // 1. 版本（图标行已选直接用；未选且多版本弹选择器）
    MediaSource? selectedSource = await _resolveSourceForPlayback(_item!);
    if (_item!.hasMultipleVersions && selectedSource == null) return;

    // 2. 电视剧 → 集数多选弹窗（含每集版本单选）
    _EpisodePickResult? episodePick;
    if (_item!.isSeries && _episodes.isNotEmpty) {
      episodePick = await _showEpisodePicker();
      if (episodePick == null) return;
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
      if (episodePick != null && episodePick.episodes.isNotEmpty) {
        final pick = episodePick; // 闭包内使用，避免可空类型丢失提升
        final seriesName = _item!.name;
        final episodesJson = pick.episodes
            .map((e) => {
                  'id': e.id,
                  'name': e.name,
                  'season': e.parentIndexNumber ?? 0,
                  'number': e.indexNumber ?? 0,
                  'poster': e.posterUrl ?? '',
                  'seriesName': seriesName,
                  // 该集单选的版本（null = 默认，不下发）
                  if (pick.sourceIds[e.id] != null)
                    'mediaSourceId': pick.sourceIds[e.id],
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
      // 电视剧：弹出集数选择（含每集版本单选）
      final episodePick = await _showEpisodePicker();
      if (episodePick == null || episodePick.episodes.isEmpty) return;

      final episodesJson = episodePick.episodes
          .map((e) => {
                'id': e.id,
                'name': e.name,
                'season': e.parentIndexNumber ?? 0,
                'number': e.indexNumber ?? 0,
                'poster': e.posterUrl ?? '',
                'seriesName': _item!.name,
                // 该集单选的版本（null = 默认，不下发）
                if (episodePick.sourceIds[e.id] != null)
                  'mediaSourceId': episodePick.sourceIds[e.id],
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

  /// 选集面板行尾的版本标签：未选显示「默认」，选中显示版本名。
  String _pickedVersionLabel(MediaItem ep, String? sourceId) {
    if (sourceId == null) return '默认';
    for (final s in ep.mediaSources) {
      if (s.id == sourceId) return s.name;
    }
    return '默认';
  }

  /// 选集面板的每集版本单选弹窗：Radio 组，每集只能勾一个版本。
  void _openPickerVersionSelector(
    MediaItem ep,
    Map<String, String?> versionByEp,
    void Function(void Function()) setSheetState,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '选择版本 - S${ep.parentIndexNumber ?? 0}E${ep.indexNumber ?? 0}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            RadioGroup<String?>(
              groupValue: versionByEp[ep.id],
              onChanged: (v) {
                versionByEp[ep.id] = v;
                setSheetState(() {});
                Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String?>(
                    key: Key('epVersionDefault_${ep.id}'),
                    title: const Text('默认（服务器选择）'),
                    value: null,
                  ),
                  for (final source in ep.mediaSources)
                    RadioListTile<String?>(
                      key: Key('epVersion_${ep.id}_${source.id}'),
                      title: Text(source.name),
                      subtitle: Text(source.displayLabel),
                      value: source.id,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 选集面板结果：所选集 + 每集选中的版本 source id（null = 默认版本）。
  /// 每集只能单选一个版本（面板内 Radio 单选组）。
  Future<_EpisodePickResult?> _showEpisodePicker() async {
    final selected = Set<String>.from(_episodes.map((e) => e.id));
    // 面板内每集版本选择（初始继承方案 A 的 per-episode 版本，确认后回写）
    final versionByEp = <String, String?>{
      for (final e in _episodes) e.id: _episodeSourceIds[e.id],
    };

    return showModalBottomSheet<_EpisodePickResult>(
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
                              cacheWidth:
                                  (48 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                            ),
                          ),
                          title: Text(
                            'S${ep.parentIndexNumber ?? 0}E${ep.indexNumber ?? 0} - ${ep.name}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: ep.hasMultipleVersions
                              ? InkWell(
                                  key: Key('episodeVersionPick_${ep.id}'),
                                  onTap: () => _openPickerVersionSelector(
                                    ep,
                                    versionByEp,
                                    setSheetState,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.layers, size: 14),
                                        const SizedBox(width: 4),
                                        Text(
                                          '版本: ${_pickedVersionLabel(ep, versionByEp[ep.id])}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : null,
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
                                  // 版本选择回写 per-episode map（与方案 A 互通）
                                  setState(() {
                                    _episodeSourceIds.addAll(versionByEp);
                                  });
                                  final result = _episodes
                                      .where((e) => selected.contains(e.id))
                                      .toList();
                                  Navigator.pop(
                                    ctx,
                                    _EpisodePickResult(
                                      result,
                                      Map<String, String?>.of(versionByEp),
                                    ),
                                  );
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
    final base = Theme.of(context).scaffoldBackgroundColor;
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    // TV 整页背景目标宽度：按显示宽×dpr，夹在 [720,1280]（详见 hdImageUrlFor）
    final bgTargetW = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(720, 1280)
        .toInt();

    final content = _isLoading
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
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadDetails,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              )
            : _buildContent();

    return Scaffold(
      extendBody: true,
      body: AnimatedContainer(
        key: const Key('detailBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        // 非 TV：底色打底，正文叠虚化氛围底图（方案 A）；
        // TV：透明底，海报由下方 Stack 做整页固定背景。
        decoration: BoxDecoration(color: tvMode ? null : base),
        child: tvMode
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // 图片加载失败兜底底色
                  ColoredBox(color: base),
                  if (_item != null) ...[
                    // 整页海报（backdrop 优先），滚动内容叠其上；按目标宽
                    // 请求并同尺寸解码（避免拉大图再解大图的浪费）
                    Positioned.fill(
                      child: EmbyImage(
                        key: const Key('detailBackdrop'),
                        url: DetailScreen.hdImageUrlFor(
                            _item!.backdropUrl ?? _item!.posterUrl, bgTargetW),
                        fit: BoxFit.cover,
                        cacheWidth: bgTargetW,
                        errorWidget: const SizedBox.shrink(),
                      ),
                    ),
                    // 压暗罩：上浅下深，保证标题与列表可读
                    DecoratedBox(
                      key: const Key('detailBackdropScrim'),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.35),
                            Colors.black.withValues(alpha: 0.45),
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.4, 0.85],
                        ),
                      ),
                    ),
                  ],
                  content,
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // 虚化氛围底图：颜色取自同一张海报，天然与顶部清晰海报
                  // 无缝衔接（不再另算纯色渐变，消除色相跳变与硬接缝）。
                  if (_item != null) _buildAmbientBackdrop(base),
                  content,
                ],
              ),
      ),
      // 播放/建房按钮已统一进内容流（_buildActionRow），仅一起看房间
      // （roomMode）手机端保留胶囊底栏的「加入资源」入口。
      bottomNavigationBar: !tvMode && _item != null && widget.roomMode
          ? _buildBottomBar()
          : null,
    );
  }

  /// 非 TV 正文氛围背景（方案 A）：同一张 backdrop 低分辨率解码 → 高斯模糊
  /// 铺满正文 → 竖向压暗罩。因为颜色直接来自海报本身，正文与顶部清晰海报
  /// 天然同色同调、无色相跳变；模糊尺度大也避免了硬接缝。顶部海报仍用清晰
  /// 原图（在 SliverAppBar 内），只有正文区虚化。
  Widget _buildAmbientBackdrop(Color base) {
    final url = _item?.backdropUrl ?? _item?.posterUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        // 低分解码 + 放大裁切 + 高斯模糊：开销极低且无边缘透底
        // （放大 1.35 使模糊采样区完全落在图内，屏幕边缘不会出现透底暗边）
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
          child: Transform.scale(
            scale: 1.35,
            child: EmbyImage(
              key: const Key('detailAmbientImage'),
              url: url,
              fit: BoxFit.cover,
              cacheWidth: 200,
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
            ),
          ),
        ),
        // 压暗罩：顶部略暗衔接 AppBar 底部蒙层；底部渐入应用底色，保证
        // 版本/剧集列表等正文可读。
        DecoratedBox(
          key: const Key('detailAmbientScrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.42),
                base.withValues(alpha: 0.90),
                base,
              ],
              stops: const [0.0, 0.5, 0.85, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  /// 操作区（简介上方）：
  /// - 非 TV：第一行播放/建房主按钮（玻璃质感、各占约半行），第二行
  ///   字幕/音轨选择器图标行（[TrackActionRow] 内部按轨道有无自适应显隐）
  /// - TV：单行合排——播放按钮缩小居行首，版本/字幕/音轨图标行紧随其后
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

    // 玻璃按钮统一外观：透明底、白字、主色图标；TV 合行时紧凑
    // （shrinkWrap 去掉 48 最小点击区 → 约 40 高、宽度随内容），
    // 非 TV 占半行高 48。
    ButtonStyle glassStyle({bool compact = false}) => FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          minimumSize: Size(0, compact ? 40 : 48),
          // TV 紧凑态补水平内边距：否则图标+文字贴到玻璃胶囊边缘，
          // 文字看起来"溢出"胶囊；非 TV 靠 Expanded 撑宽居中，无需内边距
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 0,
            vertical: compact ? 10 : 14,
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          shadowColor: Colors.transparent,
          tapTargetSize: compact
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
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

    // 「继续观看」按钮：玻璃底 + 进度填充（按已观看百分比）+ 图标文字。
    Widget resumeButton({required Future<void> Function() onPressed}) {
      final label = tvMode ? '继续' : '继续 ${_formatPosition(_resumeMs)}';
      return Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (_resumePct / 100).clamp(0.0, 1.0),
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
            ),
          ),
          FilledButton(
            onPressed: onPressed,
            style: glassStyle(compact: tvMode),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow,
                    color: scheme.primary, size: tvMode ? 20 : 24),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        final offerResume = _offerResume;
        Future<void> play() => item.isSeries
            ? _startPlaySeries(resume: offerResume)
            : _startPlay(resume: offerResume);
        children.add(action(
          run: play,
          radius: 14,
          button: offerResume
              ? resumeButton(onPressed: play)
              : FilledButton.icon(
                  onPressed: play,
                  icon: Icon(Icons.play_arrow,
                      color: scheme.primary, size: tvMode ? 20 : 24),
                  label: Text(tvMode ? '播放' : '开始播放'),
                  style: glassStyle(compact: tvMode),
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

    final trackRow = _buildTrackActionRow(item);

    // TV：单行合排——播放（缩小）居行首，版本/字幕/音轨图标行紧随；
    // 无可播放项（剧集无集数据 / TV 房间模式无入口）时仅图标行。
    // TV 下 children 至多一个（建房/加入资源均为非 TV 才加入）。
    if (tvMode) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
          if (children.isNotEmpty) const SizedBox(width: 8),
          trackRow,
        ],
      );
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
        // 图标行整行居中（版本/字幕/音轨/收藏/已观看）
        Align(alignment: Alignment.center, child: trackRow),
      ],
    );
  }

  /// 选择器图标行：电影绑主条目（全局预选 provider）；剧集绑选中集
  /// （方案 A：每集独立的版本/预选，见 [_episodeSelections]/
  /// [_episodeSourceIds]，互不覆盖）。
  Widget _buildTrackActionRow(MediaItem item) {
    final target = item.isSeries ? _targetEpisode() : null;
    if (target == null) {
      return TrackActionRow(
        item: item,
        selectedMediaSourceId: _selectedMediaSourceId,
        onOpenVersion: item.hasMultipleVersions ? _openVersionSelector : null,
        subtitleStreams: _currentSubtitleStreams(),
        audioStreams: _currentAudioStreams(),
        // 主爱心：电影收藏电影、电视剧收藏整部剧（与选中集无关）
        isFavorite: _isFavorite,
        onToggleFavorite: _toggleFavorite,
        isWatched: _isWatched,
        onToggleWatched: _toggleWatched,
        onPlayFromBeginning: _offerResume ? () => _startPlay() : null,
      );
    }
    return TrackActionRow(
      item: target,
      selectedMediaSourceId: _episodeSourceIds[target.id],
      onOpenVersion: target.hasMultipleVersions
          ? () => _openEpisodeVersionSelector(target)
          : null,
      subtitleStreams: _episodeSubtitleStreams(target),
      audioStreams: _episodeAudioStreams(target),
      // 非 null（可能是空选择）以区别于电影模式的「读全局 provider」
      selection: _episodeSelections[target.id] ?? const TrackSelection(),
      onSelectionChanged: (next) => _setEpisodeSelection(target.id, next),
      // 主爱心/已观看仍是整部剧（每集收藏/已看在横卡上）
      isFavorite: _isFavorite,
      onToggleFavorite: _toggleFavorite,
      isWatched: _isWatched,
      onToggleWatched: _toggleWatched,
      onPlayFromBeginning: _offerResume ? () => _startPlaySeries() : null,
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

  /// 正文内容流：SliverAppBar（清晰海报）+ 各 Sliver 区块。
  Widget _buildContent() {
    if (_item == null) return const SizedBox();
    final item = _item!;
    // TV 适配：横幅降高、标题降档、间距收紧（540 逻辑高屏）
    final tv = ref.watch(settingsProvider.select((s) => s.tvMode));

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: tv ? 220 : 320,
          pinned: true,
          // 透明 AppBar：非 TV 时清晰海报底部渐隐后，露出正文虚化氛围层，
          // 两层同源图片在接缝处柔化过渡，无硬边。
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          forceMaterialTransparency: true,
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
                // TV：海报已做整页背景，此处不再重复铺图/渐变，
                // 标题区直接坐在整页背景上。
                if (!tv) ...[
                  // 清晰海报：底部渐隐到透明，无缝融入正文虚化氛围层
                  // （两层底图同源，接缝处自然溶解，无硬边也无色相跳变）
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.dstIn,
                    child: EmbyImage(
                      url: item.backdropUrl ?? item.posterUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                  // 可读性压暗：底部收到 0.30，与正文氛围罩顶部同值，
                  // 跨接缝连成一条连续压暗。
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.10),
                          Colors.black.withValues(alpha: 0.30),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ],
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题艺术字（Logo 图）：有则替换文字片名（房间模式
                      // 不加 logo；图 404/加载失败回退文字片名）
                      if (!widget.roomMode && item.logoUrl != null)
                        EmbyImage(
                          url: item.logoUrl,
                          height: tv ? 44 : 60,
                          fit: BoxFit.contain,
                          // logo 多为大尺寸透明 PNG，按显示需要限解码宽
                          cacheWidth: (MediaQuery.sizeOf(context).width *
                                  MediaQuery.devicePixelRatioOf(context))
                              .clamp(300, 640)
                              .toInt(),
                          placeholder: const SizedBox.shrink(),
                          errorWidget: Text(
                            item.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: tv ? 20 : 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Text(
                          item.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: tv ? 20 : 24,
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
                      if (item.overview != null &&
                          item.overview!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        // 简介入口（v1.1.83：默认隐藏，浮层展开在海报内）
                        Row(
                          children: [
                            TvFocusable(
                              onTap: _toggleOverview,
                              child: GlassContainer(
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(14)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.subject,
                                        size: 14, color: Colors.white70),
                                    const SizedBox(width: 5),
                                    Text(
                                      _overviewVisible ? '收起' : '简介',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Icon(
                                      _overviewVisible
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 14,
                                      color: Colors.white70,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // 简介浮层：盖满海报，半透明黑底白字，限高滚动；点遮罩
                // 或收起按钮关闭（TV 焦点打开时已移入收起按钮）
                if (_overviewVisible &&
                    item.overview != null &&
                    item.overview!.isNotEmpty)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _toggleOverview,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.72),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '简介',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: tv ? 16 : 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                TvFocusable(
                                  onTap: _toggleOverview,
                                  focusNode: _overviewCloseNode,
                                  child: GlassContainer(
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(14)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.expand_less,
                                            size: 14, color: Colors.white70),
                                        const SizedBox(width: 5),
                                        const Text(
                                          '收起',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  item.overview!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        .map((g) => GlassContainer(
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(20)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              child: Text(g,
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.white)),
                            ))
                        .toList(),
                  ),
                  SizedBox(height: tv ? 12 : 16),
                ],
                // 非 TV roomMode 的入口统一走底部胶囊（避免双入口）
                if (!(widget.roomMode &&
                    !ref.watch(settingsProvider.select((s) => s.tvMode)))) ...[
                  KeyedSubtree(
                    key: _actionRowKey,
                    child: _buildActionRow(),
                  ),
                  SizedBox(height: tv ? 12 : 16),
                ],
                // 简介已移至海报内浮层（v1.1.83：海报上「简介」控件展开，
                // 正文区不再重复渲染）
                if (item.mediaStreams.isNotEmpty) ...[
                  _buildMediaInfo(item),
                  SizedBox(height: tv ? 14 : 20),
                ],
                if (item.hasMultipleVersions) ...[
                  _buildMediaSources(item),
                  SizedBox(height: tv ? 14 : 20),
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
                    favoriteIds: _favoriteEpisodeIds,
                    onToggleFavorite: _toggleEpisodeFavorite,
                    watchedIds: _watchedEpisodeIds,
                    onToggleWatched: _toggleEpisodeWatched,
                    tvMode: ref.watch(settingsProvider.select((s) => s.tvMode)),
                  ),
                ],
                // 相似推荐：仅 TV 保留在正文（非 TV 移入底部媒体信息区块顶部）
                if (tv && _similarItems.isNotEmpty) ...[
                  Text(
                    '相似推荐',
                    style: TextStyle(
                      fontSize: tv ? 16 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: PosterCard.heightFor(88),
                    child: ListView.builder(
                      // TV 焦点框放大溢出内容盒，默认 clip 会裁边
                      clipBehavior: Clip.none,
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
                // 底部媒体信息（相似推荐/外部链接/工作室/媒体信息/视频/音频；TV 不渲染）
                // 剧集：媒体信息与视频/音频取「当前选中集」；外部链接/工作室取剧集本身
                if (!tv &&
                    MediaDetailsSection.hasContent(item,
                        similarItems: _similarItems,
                        streamsItem:
                            item.isSeries ? _targetEpisode() : null)) ...[
                  const SizedBox(height: 20),
                  MediaDetailsSection(
                    item: item,
                    streamsItem: item.isSeries ? _targetEpisode() : null,
                    similarItems: _similarItems,
                    onOpenSimilar: (sim) {
                      final q = widget.serverId != null
                          ? '?server=${Uri.encodeComponent(widget.serverId!)}'
                          : '';
                      context.push('/detail/${sim.id}$q');
                    },
                  ),
                ],
                SizedBox(height: tv ? 48 : 120),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaSources(MediaItem item) {
    final tv = ref.watch(settingsProvider.select((s) => s.tvMode));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '可用版本',
          style: TextStyle(
            fontSize: tv ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...item.mediaSources.map((source) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassContainer(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.movie_creation_outlined),
                  title: Text(source.name),
                  subtitle: Text(source.displayLabel),
                  dense: true,
                ),
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

/// 选集面板（建房/加入资源）的结果：所选集 + 每集单选的版本。
class _EpisodePickResult {
  final List<MediaItem> episodes;
  final Map<String, String?> sourceIds;
  const _EpisodePickResult(this.episodes, this.sourceIds);
}
