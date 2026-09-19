import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:himi_syncwatch/core/constants.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/rtm_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:agora_rtm/agora_rtm.dart';
import 'package:himi_syncwatch/services/decode_mode_service.dart';
import 'package:himi_syncwatch/services/rtm_service.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/screens/player/room_search_delegate.dart';
import 'package:himi_syncwatch/screens/player/widgets/decode_mode_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/subtitle_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/audio_track_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/sync_debug_panel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:himi_syncwatch/services/log_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? roomCode;
  final String? mediaSourceId;
  final bool isHost;
  final String audienceName;

  const PlayerScreen({
    super.key,
    required this.itemId,
    this.roomCode,
    this.mediaSourceId,
    this.isHost = false,
    this.audienceName = '',
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

enum _OrientationMode { portraitUp, landscapeLeft, landscapeRight }

class _ResourceItem {
  final String id;
  final String name;
  final int season;
  final int number;
  final String poster;
  final String seriesName;

  const _ResourceItem({
    required this.id,
    required this.name,
    this.season = 0,
    this.number = 0,
    this.poster = '',
    this.seriesName = '',
  });

  bool get isMovie => season == 0 && number == 0 && seriesName.isEmpty;
}

class EpisodeInfo {
  final String id;
  final String name;
  final int season;
  final int number;
  final String poster;
  final String seriesName;
  final String? mediaSourceId;

  const EpisodeInfo({
    required this.id,
    required this.name,
    this.season = 0,
    this.number = 0,
    this.poster = '',
    this.seriesName = '',
    this.mediaSourceId,
  });

  bool get isMovie => season == 0 && number == 0 && seriesName.isEmpty;
}

class _SeasonGroup {
  final int seasonNumber;
  final List<_ResourceItem> episodes;
  bool collapsed = true;

  _SeasonGroup({
    required this.seasonNumber,
    required this.episodes,
  });
}

class _ResourceGroup {
  final String name;
  final bool isMovie;
  final List<_SeasonGroup> seasons;
  bool collapsed = true;

  _ResourceGroup({
    required this.name,
    required this.isMovie,
    required this.seasons,
  });

  int get totalCount => seasons.fold(0, (sum, s) => sum + s.episodes.length);
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  late final mdk.Player _player;
  Timer? _heartbeatTimer;
  Timer? _rateRestoreTimer;
  StreamSubscription? _rtmSubscription;
  bool _isHost = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  String? _myUserId;
  String? _rtmChannel;
  String? _rtmAppId;
  String? _hostUserId;

  double _volume = 80;
  double _brightness = 0.65;
  final ValueNotifier<double> _brightnessNotifier = ValueNotifier(0.65);
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(80);
  bool _syncPaused = false;
  bool _isSyncing = false;
  int _playRequestId = 0;
  DateTime? _lastSeekTime;
  bool _showPanel = true;
  String _currentPlayUrl = '';
  String _currentToken = '';
  Timer? _hideControlsTimer;
  Timer? _positionTimer;
  bool _isDraggingSlider = false;

  bool _showSubtitleMenu = false;
  bool _showAudioMenu = false;
  bool _showDecodeModeMenu = false;

  // 手势控制
  bool _showGestureOverlay = false;
  String _gestureHintText = '';
  Timer? _gestureHintTimer;
  IconData? _gestureOverlayIcon;
  bool _isLeftSide = false;
  final ValueNotifier<bool> _showBrightnessBarNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _showVolumeBarNotifier = ValueNotifier(false);
  Timer? _gestureBarTimer;

  // fvp: 轨道信息通过 Emby API 获取，不需要 media_kit 的 SubtitleTrack/AudioTrack
  StreamSubscription? _tracksSubscription;
  bool _subtitleAutoSelected = false;

  List<MediaStream> _embySubtitleStreams = [];
  List<MediaStream> _embyAudioStreams = [];
  MediaStream? _embyVideoStream; // 视频流信息（用于 DV 检测）
  int? _embyDefaultAudioIndex;
  int? _activeSubtitleIndex;
  bool _useServerSubtitleBurnIn = false;
  _OrientationMode _orientationMode = _OrientationMode.portraitUp;
  BoxFit _videoFit = BoxFit.none;
  Size? _videoNativeSize;

  // 传感器
  StreamSubscription? _accelSub;

  Map<String, dynamic>? _roomData;

  // 房间解散检测
  bool _hasReceivedRoomInfo = false;
  Timer? _roomInfoTimeout;

  // 播报板 + 在线用户
  final List<String> _broadcastMessages = [];
  final ValueNotifier<int> _broadcastVersion = ValueNotifier(0);
  int _onlineUserCount = 0;
  StreamSubscription? _presenceSubscription;
  final ScrollController _broadcastScrollController = ScrollController();
  String? _audienceName;

  // 剧集资源列表
  List<EpisodeInfo> _episodes = [];
  String _seriesName = '';
  int _currentEpisodeIndex = -1;
  bool _isSwitchingMedia = false;
  bool _hasEpisodeList = false;
  bool _isPlayerReady = false;
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);

  // 分组缓存（由 _rebuildGroups 从扁平数组计算）
  List<_ResourceGroup> _resourceGroups = [];

  void _rebuildGroups() {
    final groups = <String, _ResourceGroup>{};

    for (int i = 0; i < _episodes.length; i++) {
      final ep = _episodes[i];

      final groupName = ep.isMovie ? '电影' : ep.seriesName;

      final item = _ResourceItem(
        id: ep.id,
        name: ep.name,
        season: ep.season,
        number: ep.number,
        poster: ep.poster,
        seriesName: ep.seriesName,
      );

      groups.putIfAbsent(groupName, () => _ResourceGroup(
        name: groupName,
        isMovie: ep.isMovie,
        seasons: [],
      ));

      final group = groups[groupName]!;
      _SeasonGroup seasonGroup = group.seasons.cast<_SeasonGroup?>().firstWhere(
        (s) => s!.seasonNumber == ep.season,
        orElse: () => _SeasonGroup(seasonNumber: ep.season, episodes: []),
      )!;

      if (!group.seasons.any((s) => s.seasonNumber == ep.season)) {
        group.seasons.add(seasonGroup);
        group.seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      }

      seasonGroup.episodes.add(item);
    }

    _resourceGroups = groups.values.toList();
    // 电影组排在前面
    _resourceGroups.sort((a, b) {
      if (a.isMovie && !b.isMovie) return -1;
      if (!a.isMovie && b.isMovie) return 1;
      return a.name.compareTo(b.name);
    });

    // 恢复折叠状态：当前播放的集所在组自动展开
    if (_currentEpisodeIndex >= 0 && _currentEpisodeIndex < _episodes.length) {
      final curEp = _episodes[_currentEpisodeIndex];
      final curGroupName = curEp.isMovie ? '电影' : curEp.seriesName;
      for (final g in _resourceGroups) {
        if (g.name == curGroupName) {
          g.collapsed = false;
          for (final s in g.seasons) {
            if (s.seasonNumber == curEp.season) {
              s.collapsed = false;
            }
          }
        }
      }
    }
  }
  bool _roomSyncInitializing = false;

  // 同步调试面板
  String _syncRtmChannel = '-';
  String _syncRtmStatus = '未连接';
  String _syncMetadataTestResult = '-'; // 自检结果
  String _voStatus = '-'; // 视频输出驱动
  String _videoCodec = '-'; // 视频编码格式
  String _videoResolution = '-'; // 视频分辨率
  String _actualDecoderFull = ''; // 实际解码器完整描述
  String _hdrType = 'SDR'; // HDR 类型标签
  bool _isDolbyVisionP5 = false; // 当前是否 DV P5（控制解码模式显示）
  bool _isSwitchingDecode = false; // 并发保护：防止快速切换模式导致状态错乱
  List<String> _syncEvents = [];
  final ValueNotifier<int> _syncEventsVersion = ValueNotifier(0);
  final GlobalKey _qrKey = GlobalKey();

  // 调试面板拖拽位置
  double _debugPanelX = 20;
  double _debugPanelY = 100;

  void _logSyncEvent(String event) {
    LogService().log('Sync', event);
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _syncEvents.add('[$time] $event');
    if (_syncEvents.length > 15) _syncEvents.removeAt(0);
    _syncEventsVersion.value++;
  }

  Future<void> _queryHwdecStatus() async {
    try {
      // fvp: 通过 property 获取编解码器信息
      final codec = _player.getProperty('video.decoder') ?? 'auto';
      if (mounted) {
        setState(() {
          _voStatus = 'fvp/libmdk';
          _videoCodec = codec;
        });
      }
    } catch (_) {}
  }

  /// 检测杜比视界内容并应用相应策略
  Future<void> _detectDolbyVision() async {
    try {
      // 优先使用 Emby API 的 extendedVideoType（可靠）
      bool isDV = false;
      String hdrType = 'SDR';
      
      if (_embyVideoStream != null) {
        // 使用 Emby API 数据
        isDV = _embyVideoStream!.isDolbyVision;
        hdrType = _embyVideoStream!.hdrLabel;
        LogService().log('Player', 'DV 检测(Emby API): isDV=$isDV, hdrType=$hdrType');
      }
      
      if (!mounted) return;
      
      setState(() {
        _hdrType = hdrType;
        _isDolbyVisionP5 = isDV && _embyVideoStream?.isDolbyVisionProfile5 == true;
      });
      
      // fvp/libmdk 原生支持 Dolby Vision（包括 P5），无需手动设置
      if (isDV) {
        final profile = _embyVideoStream?.extendedVideoSubType ?? 'unknown';
        LogService().log('Player', 'DV $profile: fvp 原生处理');
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = mdk.Player();
    // 字幕属性配置
    _player.setProperty('subtitle', '1');
    _player.setProperty('subtitle.font.size', '40');
    _player.setProperty('subtitle.border', '2');
    _player.setProperty('subtitle.shadow', '1');
    _player.setProperty('subtitle.margin.y', '22');
    // 立体声降混：将多声道音频降混为立体声（用户可选）
    final settings = ref.read(settingsProvider);
    if (settings.stereoDownmix) {
      _player.setProperty('audio.avfilter', 'aresample=ochl=stereo');
    }
    // 音频后端：OpenSL 时钟精度更高，可改善 TrueHD 等高复杂度音频的播放流畅度
    if (settings.audioRenderer != 'auto') {
      _player.audioBackends = [settings.audioRenderer];
    }
    // 音量默认 80%
    _player.volume = 0.8;
    _myUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';

    _isHost = widget.isHost;
    _audienceName = widget.audienceName.isNotEmpty
        ? widget.audienceName
        : (_isHost ? '房主' : '观众');

    // 主持人：优先从 Riverpod provider 读取 episodes/movie；观众通过 RTM 接收
    if (_isHost) {
      final pendingEpisodes = ref.read(pendingRoomEpisodesProvider);
      final pendingMovie = ref.read(pendingRoomMovieProvider);
      if (pendingEpisodes != null && pendingEpisodes.isNotEmpty) {
        // 电视剧：从完整数据提取所有字段
        _episodes = pendingEpisodes.map((e) => EpisodeInfo(
          id: e['id'] as String,
          name: e['name'] as String? ?? '',
          season: e['season'] as int? ?? 0,
          number: e['number'] as int? ?? 0,
          poster: e['poster'] as String? ?? '',
          seriesName: e['seriesName'] as String? ?? '',
        )).toList();
        _seriesName = pendingEpisodes.first['seriesName'] as String? ?? '';
        _hasEpisodeList = true;
        ref.read(pendingRoomEpisodesProvider.notifier).state = null;
      } else if (pendingMovie != null) {
        _episodes = [EpisodeInfo(
          id: pendingMovie['id'] as String,
          name: pendingMovie['name'] as String? ?? '电影',
          poster: pendingMovie['poster'] as String? ?? '',
          mediaSourceId: widget.mediaSourceId,
        )];
        _seriesName = '';
        _hasEpisodeList = true;
        ref.read(pendingRoomMovieProvider.notifier).state = null;
      }
      _rebuildGroups();
    }

    _setupPlayerListeners();
    _startOrientationSensor();

    if (widget.roomCode != null) {
      _setupRoomSync();
      _switchToLandscape(_OrientationMode.landscapeLeft);
    }

    // 先完成硬件解码设置，再启动播放，避免竞态
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 并行执行：亮度读取 + 播放器属性初始化
      await Future.wait([
        Future(() async {
          try {
            _brightness = await ScreenBrightness().application;
          } catch (_) {}
        }),
        _initPlayerProperties(),
      ]);
      if (_isHost && _hasEpisodeList && _episodes.isNotEmpty && widget.roomCode == null) {
        final targetIndex = _episodes.indexWhere((e) => e.id == widget.itemId);
        try {
          await _loadEpisodeStream(targetIndex >= 0 ? targetIndex : 0);
        } catch (_) {
          LogService().log('Player', '_loadEpisodeStream 异常，强制设置 _isPlayerReady');
          if (mounted) {
            setState(() {
              _isPlayerReady = true;
            });
          }
        }
      }
    });
  }

  Future<void> _initPlayerProperties() async {
    final settings = ref.read(settingsProvider);

    // 配置解码器
    final decoders = DecodeModeService.resolveDecoders(settings.decodeMode);
    _player.videoDecoders = decoders;

    // 锁屏保持
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }


  Future<void> _loadEpisodeStream(int episodeIndex) async {
    if (episodeIndex < 0 || episodeIndex >= _episodes.length) return;

    final ep = _episodes[episodeIndex];
    final itemId = ep.id;
    final epMediaSourceId = ep.mediaSourceId;

    // 先设置 _currentEpisodeIndex，这样 publishPlayInfo 能拿到正确的值
    setState(() {
      _currentEpisodeIndex = episodeIndex;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final config = ref.read(embyConfigProvider);

      // 并行：加载流 + 获取 Emby 详情，互不阻塞
      final textureReadyF = _loadStream(itemId: itemId, mediaSourceId: epMediaSourceId);
      final detailsF = (config != null && config.isAuthenticated)
          ? embyService.getItemDetails(itemId).catchError((e) {
              LogService().log('Player', '获取 Emby 详情失败: $e');
              return null;
            })
          : Future.value(null);

      await textureReadyF;

      // 处理 Emby 详情（不阻塞播放）
      try {
        final details = await detailsF;
        if (details != null && mounted) {
          final source = details.mediaSources.firstWhere(
            (s) => s.id == epMediaSourceId,
            orElse: () =>
                details.mediaSources.firstOrNull ?? MediaSource(id: '', name: ''),
          );
          setState(() {
            _embyAudioStreams = source.audioStreams;
            _embySubtitleStreams = source.subtitleStreams;
            _embyVideoStream = source.videoStream;
            _embyDefaultAudioIndex = source.defaultAudioStreamIndex;
          });
        }
      } catch (_) {}

      // _loadStream 已在 updateTexture() 后设置播放状态，此处仅同步 UI
      if (mounted) {
        _syncPlayState();
      }
    } catch (e) {
      LogService().log('Player', '_loadEpisodeStream 异常: $e');
    }

    // 无论成功或失败，都标记播放器已就绪，避免卡在 placeholder
    if (mounted) {
      setState(() {
        _isPlayerReady = true;
      });
    }

    // 单人模式自动横屏
    if (widget.roomCode == null && mounted) {
      _switchToLandscape(_OrientationMode.landscapeLeft);
    }
    _rebuildGroups();
  }

  /// 同步从 mediaInfo 获取视频原生尺寸，用于缩放计算
  void _syncVideoNativeSize() {
    try {
      final info = _player.mediaInfo;
      final videos = info.video;
      if (videos != null && videos.isNotEmpty) {
        var v = videos[0];
        for (final i in videos) {
          if (i.codec.width > v.codec.width) v = i;
        }
        final vc = v.codec;
        if (vc.width > 0 && vc.height > 0) {
          double w = vc.width.toDouble();
          double h = (vc.height.toDouble() / vc.par).roundToDouble();
          if (v.rotation % 180 == 90) {
            final tmp = w; w = h; h = tmp;
          }
          final size = Size(w, h);
          if (_videoNativeSize != size) {
            _videoNativeSize = size;
          }
        }
      }
    } catch (_) {}
  }

  /// 确保纹理存在：首次播放时创建，后续复用现有纹理避免黑屏
  Future<void> _ensureTexture() async {
    if (_player.textureId.value != null) return;
    try {
      await _player.updateTexture().timeout(const Duration(seconds: 5));
    } catch (_) {
      LogService().log('Player', 'updateTexture 失败');
    }
  }

  /// 加载流并返回 texture 是否就绪
  Future<bool> _loadStream({
    String? itemId,
    int? subtitleStreamIndex,
    String? mediaSourceId,
  }) async {
    final targetItemId = itemId ?? widget.itemId;
    final effectiveMediaSourceId = mediaSourceId ??
        (targetItemId == widget.itemId ? widget.mediaSourceId : null);

    final embyService = ref.read(embyServiceProvider);
    final config = ref.read(embyConfigProvider);
    final token = config?.accessToken ?? '';

    try {
      final streamUrl = embyService.getStreamUrl(
        targetItemId,
        mediaSourceId: effectiveMediaSourceId,
        subtitleStreamIndex: subtitleStreamIndex,
      );

      _currentPlayUrl = streamUrl;
      _currentToken = token;

      // 重置进度（与首次播放状态一致）
      _position = Duration.zero;
      _positionNotifier.value = Duration.zero;
      _videoNativeSize = null;

      final wasPlaying = _player.state == mdk.PlaybackState.playing;

      // 设置媒体并准备播放
      if (token.isNotEmpty) {
        _player.setProperty('avio.headers', 'X-Emby-Token: $token');
      }
      _isSwitchingMedia = true;
      _player.media = streamUrl;
      await _player.prepare();

      // 确保纹理存在（首次创建，后续复用，避免切集黑屏）
      await _ensureTexture();

      // 同步设置视频原生尺寸（从 mediaInfo 读取）
      _syncVideoNativeSize();

      // 启动播放
      if (mounted) {
        if (wasPlaying) {
          _player.state = mdk.PlaybackState.playing;
          _syncPlayState();
        }
        setState(() {});
      }
      Future.delayed(const Duration(seconds: 2), () async {
        await _detectDolbyVision();
      });

      // 延迟清除切换锁，确保旧媒体的 MediaStatus.end 事件被完全过滤
      Future.delayed(const Duration(milliseconds: 500), () {
        _isSwitchingMedia = false;
      });

      return _player.textureId.value != null;
    } catch (e) {
      LogService().log('Player', '加载流失败: $e');
      _isSwitchingMedia = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
      return false;
    }
  }


  /// 观众播放：从 syncPlay 消息中的 playUrl 直接播放
  void _playFromUrl({
    required String playUrl,
    required String token,
    double position = 0.0,
    int? epIndex,
  }) async {
    if (!mounted) return;

    final requestId = ++_playRequestId;
    _isSyncing = true;
    try {
      _addBroadcastMessage('同步主持人播放');

      // fvp 原生处理重定向，直接使用 playUrl
      LogService().log('Sync', '直接使用 playUrl: ${playUrl.length}字符');

      // 检查是否已被更新的请求抢占
      if (requestId != _playRequestId || !mounted) return;

      // 切换视频前重置进度（与首次播放状态一致）
      _position = Duration.zero;
      _positionNotifier.value = Duration.zero;
      _videoNativeSize = null;

      // 设置媒体并准备播放
      if (token.isNotEmpty) {
        _player.setProperty('avio.headers', 'X-Emby-Token: $token');
      }
      _isSwitchingMedia = true;
      _player.media = playUrl;
      await _player.prepare();

      // 确保纹理存在（首次创建，后续复用，避免切集黑屏）
      await _ensureTexture();
      // 同步设置视频原生尺寸（从 mediaInfo 读取）
      _syncVideoNativeSize();

      // 缓冲完成，再次检查是否已被抢占
      if (requestId != _playRequestId || !mounted) return;

      setState(() {
        if (epIndex != null) _currentEpisodeIndex = epIndex;
        _isPlayerReady = true;
      });

      // 仅在 texture 就绪时启动播放，避免有声无画
      if (_player.textureId.value != null) {
        if (position > 0) {
          await _player.seek(position: (position * 1000).toInt(), flags: mdk.SeekFlag(mdk.SeekFlag.keyFrame));
        }

        _player.state = mdk.PlaybackState.playing;
        _syncPlayState();
      }
      _rebuildGroups();
      _logSyncEvent('播放器打开成功');
      Future.delayed(const Duration(seconds: 2), _queryHwdecStatus);
      LogService().log('Sync', '播放器打开成功');

      // 延迟清除切换锁，确保旧媒体的 MediaStatus.end 事件被完全过滤
      Future.delayed(const Duration(milliseconds: 500), () {
        _isSwitchingMedia = false;
      });
    } catch (e) {
      _isSwitchingMedia = false;
      _logSyncEvent('播放器打开失败: $e');
      LogService().log('Sync', '播放器打开失败: $e');
      _addBroadcastMessage('同步播放失败: $e');
    } finally {
      if (requestId == _playRequestId) _isSyncing = false;
    }
  }

  void _setupPlayerListeners() {
    // 使用 onStateChanged 监听播放状态变化
    _player.onStateChanged.listen((event) {
      if (!mounted) return;
      // 更新音量
      _volume = _player.volume * 100;
      _volumeNotifier.value = _volume;
      _syncPlayState();
    });

    // 使用 onMediaStatus 监听媒体状态变化
    _player.onMediaStatus.listen((event) {
      if (!mounted) return;
      
      // 检查是否加载完成
      if (event.newValue.test(mdk.MediaStatus.loaded)) {
        _duration = Duration(milliseconds: _player.mediaInfo.duration);
        _durationNotifier.value = _duration;
        _refreshTracks();
        // 注意：不再在此处设置 _player.state = playing
        // loaded 通过 ReceivePort 异步到达，此时 updateTexture() 可能还没创建 texture
        // 播放状态由 _loadStream 在 updateTexture() 之后统一设置
      }
      
      // 检查是否播放结束
      if (event.newValue.test(mdk.MediaStatus.end)) {
        if (_isSwitchingMedia) return;
        if (!_hasEpisodeList || !_canControlPlayback) return;
        final nextIndex = _currentEpisodeIndex + 1;
        if (nextIndex < _episodes.length) {
          _switchToEpisode(nextIndex);
        } else {
          _addBroadcastMessage('所有剧集播放完毕');
        }
      }
    });

    // 定时更新播放位置（fvp 没有直接的 position stream）
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_isDraggingSlider) return; // 拖动中不更新，避免进度条回弹
      final pos = _player.position;
      if (pos != _positionNotifier.value.inMilliseconds) {
        _position = Duration(milliseconds: pos);
        _positionNotifier.value = _position;
      }
    });
  }

  void _autoSelectDefaultTracks() {
    // fvp: 自动选择第一个字幕轨道
    _player.activeSubtitleTracks = [0];

    if (_embyDefaultAudioIndex != null) {
      final embyIdx = _embyAudioStreams.indexWhere(
        (s) => s.index == _embyDefaultAudioIndex!,
      );
      if (embyIdx >= 0) {
        _player.activeAudioTracks = [embyIdx];
      }
    }
  }

  void _refreshTracks() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (!_subtitleAutoSelected) {
        _subtitleAutoSelected = true;
        _autoSelectDefaultTracks();
      }
    });
  }

  void _setupRoomSync() async {
    if (_roomSyncInitializing) return;
    _roomSyncInitializing = true;

    // 仅主持人需要检查声网配置
    if (_isHost) {
      final agoraConfig = ref.read(agoraConfigProvider);
      if (agoraConfig == null || !agoraConfig.isConfigured) {
        _roomSyncInitializing = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('声网未配置')),
          );
        }
        return;
      }
    }

    _roomData ??= RoomCode.decode(widget.roomCode!);
    if (_roomData == null) {
      _roomSyncInitializing = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('房间码无效')),
        );
      }
      return;
    }

    _rtmChannel = _roomData!['channel'] as String?;
    _rtmAppId = _roomData!['appId'] as String?;

    if (_rtmChannel == null || _rtmAppId == null) {
      _roomSyncInitializing = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('房间数据不完整')),
        );
      }
      return;
    }

    final rtmService = ref.read(rtmServiceProvider);

    // Host: 使用自己的 userId 初始化; Audience: 从 token 中获取 tokenId
    String? loginToken;
    String rtmUserId;

    if (_isHost) {
      rtmUserId = _myUserId!;
      await rtmService.initialize(
        appId: _rtmAppId!,
        userId: rtmUserId,
      );
      final agoraConfig = ref.read(agoraConfigProvider)!;
      loginToken = RtmTokenBuilder.buildToken(
        appId: _rtmAppId!,
        appCertificate: agoraConfig.appCertificate,
        userId: rtmUserId,
        tokenExpireSeconds: 86400,
      );
    } else {
      final tokenData = RoomCode.consumeToken(_roomData!);
      if (tokenData == null) {
        _roomSyncInitializing = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无可用水_token')),
          );
        }
        return;
      }
      rtmUserId = tokenData['tokenId'] as String;
      loginToken = tokenData['token'] as String;

      await rtmService.initialize(
        appId: _rtmAppId!,
        userId: rtmUserId,
      );
    }

    final loginOk = await rtmService.login(_rtmAppId!, token: loginToken);
    if (!loginOk) {
      _roomSyncInitializing = false;
      setState(() => _syncRtmStatus = '登录失败');
      _logSyncEvent('RTM 登录失败');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RTM 登录失败，请检查声网配置')),
        );
      }
      return;
    }
    final subscribeOk = await rtmService.subscribe(_rtmChannel!);
    if (!subscribeOk) {
      _roomSyncInitializing = false;
      setState(() => _syncRtmStatus = '订阅失败');
      _logSyncEvent('RTM 订阅失败');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RTM 频道订阅失败，请检查网络')),
        );
      }
      return;
    }

    setState(() {
      _syncRtmChannel = _rtmChannel ?? '-';
      _syncRtmStatus = '已连接';
    });
    _logSyncEvent('RTM 已连接, 频道: $_rtmChannel');

    // 观众：检测频道内是否有人（房主是否在线）
    if (!_isHost) {
      final onlineCount = await rtmService.getOnlineUserCount(_rtmChannel!);
      _logSyncEvent('频道在线人数: $onlineCount');
      if (onlineCount == 0) {
        _logSyncEvent('频道无人在线，房间已解散');
        _showRoomDestroyedDialog();
        return;
      }
      // 启动 roomInfo 等待超时（10 秒）
      _roomInfoTimeout?.cancel();
      _roomInfoTimeout = Timer(const Duration(seconds: 10), () {
        if (mounted && !_hasReceivedRoomInfo) {
          _logSyncEvent('等待 roomInfo 超时，房间可能已解散');
          _showRoomDestroyedDialog();
        }
      });
    }

    // 元数据自检（延迟 1 秒等 channel 稳定）
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted || _rtmChannel == null) return;
      final rtmService = ref.read(rtmServiceProvider);
      final result = await rtmService.testMetadata(_rtmChannel!);
      if (mounted) {
        setState(() {
          _syncMetadataTestResult = result;
        });
        _logSyncEvent('元数据自检: $result');
      }
    });

    // 1. 设置消息监听器（subscribe 之后立即设置，确保不丢消息）
    LogService().log('Room', '${_isHost ? "主持人" : "观众"} 设置消息监听器, userId=$_myUserId, channel=$_rtmChannel, episodes=${_episodes.length}');
    _rtmSubscription = rtmService.messageStream.listen((message) async {
      if (!mounted) return;
      final senderId = message['userId'];
      if (senderId == _myUserId) return;

      final type = message['type'];
      LogService().log('Room', '收到消息 type=$type, sender=$senderId');
      if (type == AppConstants.msgTypeHeartbeat) {
        _handleHeartbeat(message);
      } else if (type == AppConstants.msgTypeRoomInfo) {
        LogService().log('Room', '收到 roomInfo, episodeIds=${message['episodeIds']?.length ?? 0}');
        _logSyncEvent('收到 roomInfo (${message['episodeIds']?.length ?? 0}集)');
        _handleRoomInfo(message);
      } else if (type == AppConstants.msgTypeCommand) {
        final action = message['action'] as String?;
        LogService().log('Room', '收到命令 action=$action');
        if (action == 'join') {
          final name = message['userName'] as String? ?? '观众';
          _addBroadcastMessage('$name 加入了房间');
          _logSyncEvent('$name 加入房间');
          _refreshOnlineCount(rtmService);
          // 主持人发送房间信息（含媒体数据 + 剧集列表 + playUrl）
          if (_isHost) {
            LogService().log('Room', '主持人发送 roomInfo, episodeCount=${_episodes.length}');
            await rtmService.sendRoomInfo(
              channelName: _rtmChannel!,
              mediaItemId: widget.itemId,
              mediaSourceId: widget.mediaSourceId,
              mediaItemName: _episodes.isNotEmpty
                  ? _episodes.first.name
                  : null,
              seriesName: _seriesName,
              episodeIds: _episodes.map((e) => e.id).toList(),
              episodeNames: _episodes.map((e) => e.name).toList(),
              episodeSeasons: _episodes.map((e) => e.season).toList(),
              episodeNumbers: _episodes.map((e) => e.number).toList(),
              episodePosters: _episodes.map((e) => e.poster).toList(),
              episodeSeriesNames: _episodes.map((e) => e.seriesName).toList(),
              playUrl: _currentPlayUrl,
              token: _currentToken,
              subtitleStreams: _embySubtitleStreams.map((s) => s.toJson()).toList(),
              audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
              videoStream: _embyVideoStream?.toJson(),
              defaultAudioStreamIndex: _embyDefaultAudioIndex,
            );
            // 主持人发送当前播放状态（同步播放进度）
            if (_isPlayerReady && _currentEpisodeIndex >= 0) {
              final position = _player.position / 1000.0;
              LogService().log('Room', '主持人发送 syncPlay: episode=$_currentEpisodeIndex, pos=$position');
              await rtmService.sendCommand(
                action: AppConstants.actionSyncPlay,
                episodeIndex: _currentEpisodeIndex,
                itemId: _episodes[_currentEpisodeIndex].id,
                position: position,
                playUrl: _currentPlayUrl,
                token: _currentToken,
              );
            }
          }
        } else if (action == 'leave') {
          final name = message['userName'] as String? ?? '观众';
          _addBroadcastMessage('$name 离开了房间');
          _refreshOnlineCount(rtmService);
        } else if (action == AppConstants.actionRequestRoomInfo) {
          // 观众请求房间信息，主持人重新发送
          if (_isHost) {
            rtmService.sendRoomInfo(
              channelName: _rtmChannel!,
              mediaItemId: widget.itemId,
              mediaSourceId: widget.mediaSourceId,
              mediaItemName: _episodes.isNotEmpty
                  ? _episodes.first.name
                  : null,
              seriesName: _seriesName,
              episodeIds: _episodes.map((e) => e.id).toList(),
              episodeNames: _episodes.map((e) => e.name).toList(),
              episodeSeasons: _episodes.map((e) => e.season).toList(),
              episodeNumbers: _episodes.map((e) => e.number).toList(),
              episodePosters: _episodes.map((e) => e.poster).toList(),
              episodeSeriesNames: _episodes.map((e) => e.seriesName).toList(),
              playUrl: _currentPlayUrl,
              token: _currentToken,
              subtitleStreams: _embySubtitleStreams.map((s) => s.toJson()).toList(),
              audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
              videoStream: _embyVideoStream?.toJson(),
              defaultAudioStreamIndex: _embyDefaultAudioIndex,
            );
          }
        } else {
          _handleCommand(message);
        }
      }
    });

    // 2. 监听 Presence 事件（在线人数变化）
    _presenceSubscription = rtmService.presenceStream.listen((event) async {
      if (mounted && !_isHost && _hostUserId != null) {
        final type = event['type'];
        final publisher = event['publisher'] as String?;
        if (publisher == _hostUserId &&
            (type == RtmPresenceEventType.remoteLeaveChannel ||
             type == RtmPresenceEventType.remoteTimeout)) {
          _showRoomDestroyedDialog();
          return;
        }
      }
      if (mounted) {
        _refreshOnlineCount(rtmService);
      }
    });

    // 3. 发送 join 命令（通知已在频道的人）
    _addBroadcastMessage('${_audienceName} 加入了房间');
    rtmService.sendJoinLeave(
      action: 'join',
      userName: _audienceName!,
    );

    // 初始化在线人数（自己）
    _onlineUserCount = 1;
    setState(() {});

    // 延迟刷新在线人数（等待 RTM presence 同步）
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _refreshOnlineCount(rtmService);
      }
    });

    // 主持人开始心跳
    if (_isHost) {
      _startHeartbeat();
    }
  }

  void _refreshOnlineCount(RtmService rtmService) async {
    if (_rtmChannel == null) return;
    final count = await rtmService.getOnlineUserCount(_rtmChannel!);
    if (mounted) {
      setState(() {
        _onlineUserCount = count;
      });
    }
  }

  void _handleHeartbeat(Map<String, dynamic> message) {
    if (_isHost) return;
    if (_syncPaused) return;
    if (_isSyncing) return;
    // fvp: 检查是否在缓冲中
    if (_player.mediaStatus.test(mdk.MediaStatus.buffering)) return;
    if (_player.mediaStatus.test(mdk.MediaStatus.seeking)) return;

    final position = (message['position'] as num).toDouble();
    final playing = message['playing'] as bool;
    final rate = (message['rate'] as num).toDouble();
    final timestamp = message['ts'] as int;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final elapsed = now - timestamp;
    final expectedPos = position + (elapsed * rate);

    final currentPos = _player.position / 1000.0;
    final diff = (expectedPos - currentPos).abs();

    if (diff < AppConstants.syncThresholdMicro) {
      // 差值 < 0.3s，不做操作
    } else if (diff < AppConstants.syncThresholdMedium) {
      _rateRestoreTimer?.cancel();
      _player.playbackRate = 1.02;
      _rateRestoreTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _player.playbackRate = rate;
      });
    } else {
      // seek 防抖：距上次 seek 不足 2 秒则跳过
      if (_lastSeekTime != null &&
          DateTime.now().difference(_lastSeekTime!).inMilliseconds < 2000) {
        return;
      }
      _lastSeekTime = DateTime.now();
      try {
        _player.seek(position: (expectedPos * 1000).toInt(), flags: mdk.SeekFlag(mdk.SeekFlag.keyFrame));
      } catch (_) {}
    }

    // 主持人控制播放/暂停状态
    if (playing && _player.state != mdk.PlaybackState.playing) {
      _player.state = mdk.PlaybackState.playing;
      _syncPlayState();
    } else if (!playing && _player.state == mdk.PlaybackState.playing) {
      _player.state = mdk.PlaybackState.paused;
      _syncPlayState();
    }
  }

  void _handleCommand(Map<String, dynamic> message) {
    final action = message['action'] as String;

    _syncPaused = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _syncPaused = false;
    });

    switch (action) {
      case AppConstants.actionPlay:
        _player.state = mdk.PlaybackState.playing;
        _syncPlayState();
        break;
      case AppConstants.actionPause:
        _player.state = mdk.PlaybackState.paused;
        _syncPlayState();
        break;
      case AppConstants.actionSeek:
        final pos = (message['position'] as num).toDouble();
        try {
          _player.seek(position: (pos * 1000).toInt(), flags: mdk.SeekFlag(mdk.SeekFlag.keyFrame));
        } catch (_) {}
        break;
      case AppConstants.actionRate:
        final r = (message['rate'] as num).toDouble();
        _player.playbackRate = r;
        break;
      case AppConstants.actionSyncPlay:
        final position = (message['position'] as num?)?.toDouble() ?? 0.0;
        final playUrl = message['playUrl'] as String?;
        final token = message['token'] as String?;
        final epIndex = message['episodeIndex'] as int?;
        _logSyncEvent('收到 syncPlay, pos=${position.toStringAsFixed(1)}s, urlLen=${playUrl?.length ?? 0}');
        if (playUrl != null && playUrl.isNotEmpty) {
          _playFromUrl(playUrl: playUrl, token: token ?? '', position: position, epIndex: epIndex);
        }
        break;
      case AppConstants.actionRemoveEpisode:
        final epIndex = message['episodeIndex'] as int?;
        if (epIndex != null) {
          _removeEpisode(epIndex, sendRtm: false);
        }
        break;
      case AppConstants.actionAddResource:
        _handleAddResource(message);
        break;
      case AppConstants.actionRoomDestroyed:
        _showRoomDestroyedDialog();
        break;
    }
  }

  void _handleRoomInfo(Map<String, dynamic> message) {
    if (_isHost) return;
    if (_hasEpisodeList) return;

    // 收到 roomInfo，取消超时
    _hasReceivedRoomInfo = true;
    _roomInfoTimeout?.cancel();

    // 记录房主 userId（用于 Presence 检测房主离线）
    final hostId = message['userId'] as String?;
    if (hostId != null && hostId.isNotEmpty) {
      _hostUserId = hostId;
    }

    LogService().log('Room', '_handleRoomInfo: keys=${message.keys.toList()}');
    final epIds = message['episodeIds'];
    LogService().log('Room', '_handleRoomInfo: epIds type=${epIds.runtimeType}, len=${epIds is List ? epIds.length : "N/A"}');
    if (epIds is List && epIds.isNotEmpty) {
      // 电视剧：接收完整剧集列表
      final names = List<String>.from(message['episodeNames'] ?? []);
      final seasons = List<int>.from(message['episodeSeasons'] ?? []);
      final numbers = List<int>.from(message['episodeNumbers'] ?? []);
      final posters = List<String>.from(message['episodePosters'] ?? []);
      final seriesNames = List<String>.from(message['episodeSeriesNames'] ?? []);
      setState(() {
        _episodes = List.generate(epIds.length, (i) => EpisodeInfo(
          id: epIds[i] as String,
          name: i < names.length ? names[i] : '',
          season: i < seasons.length ? seasons[i] : 0,
          number: i < numbers.length ? numbers[i] : 0,
          poster: i < posters.length ? posters[i] : '',
          seriesName: i < seriesNames.length ? seriesNames[i] : '',
        ));
        _seriesName = message['seriesName'] ?? '';
        _hasEpisodeList = true;
      });
    } else {
      // 电影：用 mediaItemId 构建单集
      final mediaItemId = message['mediaItemId'] as String?;
      final mediaItemName = message['mediaItemName'] as String?;
      if (mediaItemId != null && mediaItemId.isNotEmpty) {
        setState(() {
          _episodes = [EpisodeInfo(
            id: mediaItemId,
            name: mediaItemName ?? '电影',
          )];
          _seriesName = '';
          _hasEpisodeList = true;
        });
      }
    }
    _rebuildGroups();

    if (_hasEpisodeList) {
      _addBroadcastMessage('已同步房间资源列表');

      // 解析字幕/音轨数据
      final subtitleStreamsRaw = message['subtitleStreams'];
      final audioStreamsRaw = message['audioStreams'];
      if (subtitleStreamsRaw is List) {
        _embySubtitleStreams = subtitleStreamsRaw
            .whereType<Map<String, dynamic>>()
            .map((s) => MediaStream.fromJson(s))
            .toList();
      }
      if (audioStreamsRaw is List) {
        _embyAudioStreams = audioStreamsRaw
            .whereType<Map<String, dynamic>>()
            .map((s) => MediaStream.fromJson(s))
            .toList();
      }
      // 接收视频流信息（用于 DV 检测）
      final videoStreamRaw = message['videoStream'];
      if (videoStreamRaw is Map<String, dynamic>) {
        _embyVideoStream = MediaStream.fromJson(videoStreamRaw);
      }
      _embyDefaultAudioIndex = message['defaultAudioStreamIndex'] as int?;
      LogService().log('Room', '字幕=${_embySubtitleStreams.length}条, 音轨=${_embyAudioStreams.length}条, 视频=${_embyVideoStream?.codec ?? "无"}');

      // 从 roomInfo 消息中获取 playUrl 并播放
      final playUrl = message['playUrl'] as String?;
      final token = message['token'] as String?;
      if (playUrl != null && playUrl.isNotEmpty) {
        _playFromUrl(playUrl: playUrl, token: token ?? '');
      }
    }
  }

  void _showRoomDestroyedDialog() {
    _heartbeatTimer?.cancel();
    _player.state = mdk.PlaybackState.stopped;
    _syncPlayState();
    if (_rtmChannel != null) {
      try {
        final rtmService = ref.read(rtmServiceProvider);
        rtmService.unsubscribe(_rtmChannel!);
      } catch (_) {}
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('房间已解散'),
        content: const Text('房主已离开，房间已解散'),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<bool> _confirmLeaveRoom() async {
    if (!_isHost || widget.roomCode == null) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散房间'),
        content: const Text('离开将解散当前房间，所有观众将被退出。确定离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定离开'),
          ),
        ],
      ),
    );
    if (result == true && _rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);
      await rtmService.sendJoinLeave(
        action: AppConstants.actionRoomDestroyed,
        userName: _audienceName ?? '房主',
      );
      await rtmService.sendJoinLeave(
        action: AppConstants.actionRoomDestroyed,
        userName: _audienceName ?? '房主',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return result ?? false;
  }

  void _addBroadcastMessage(String msg) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _broadcastMessages.add('[$time] $msg');
    _broadcastVersion.value++;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_broadcastScrollController.hasClients) {
        _broadcastScrollController.animateTo(
          _broadcastScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  int get _totalEpisodeCount => _episodes.length;

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.rtmHeartbeatIntervalMs),
      (_) {
        if (!mounted || _player.state != mdk.PlaybackState.playing) return;
        final rtmService = ref.read(rtmServiceProvider);
        rtmService.sendHeartbeat(
          position: _player.position / 1000.0,
          playing: _player.state == mdk.PlaybackState.playing,
          rate: _player.playbackRate,
        );
      },
    );
  }

  void _sendCommand(String action, {double? position, double? rate}) {
    final rtmService = ref.read(rtmServiceProvider);
    rtmService.sendCommand(
      action: action,
      position: position,
      rate: rate,
    );
  }

  void _togglePlayPause() {
    if (_player.state == mdk.PlaybackState.playing) {
      _player.state = mdk.PlaybackState.paused;
      if (widget.roomCode != null) {
        _sendCommand(AppConstants.actionPause);
      }
    } else {
      _player.state = mdk.PlaybackState.playing;
      if (widget.roomCode != null) {
        _sendCommand(AppConstants.actionPlay);
      }
    }
    _syncPlayState();
  }

  void _syncPlayState() {
    final playing = _player.state == mdk.PlaybackState.playing;
    if (_isPlayingNotifier.value != playing) {
      _isPlayingNotifier.value = playing;
    }
  }

  void _startOrientationSensor() {
    double filteredX = 0;
    const alpha = 0.2;
    int flipCount = 0;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      filteredX = alpha * event.x + (1 - alpha) * filteredX;

      // 仅在横屏模式下检测180度翻转
      if (_orientationMode == _OrientationMode.landscapeLeft) {
        if (filteredX < -8.0) {
          flipCount++;
          if (flipCount >= 3) {
            _switchToLandscape(_OrientationMode.landscapeRight);
            flipCount = 0;
          }
        } else {
          flipCount = 0;
        }
      } else if (_orientationMode == _OrientationMode.landscapeRight) {
        if (filteredX > 8.0) {
          flipCount++;
          if (flipCount >= 3) {
            _switchToLandscape(_OrientationMode.landscapeLeft);
            flipCount = 0;
          }
        } else {
          flipCount = 0;
        }
      }
    });
  }

  void _switchToLandscape(_OrientationMode mode) {
    if (!mounted) return;
    setState(() => _orientationMode = mode);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _toggleOrientation() {
    if (_orientationMode == _OrientationMode.portraitUp) {
      _switchToLandscape(_OrientationMode.landscapeLeft);
    } else {
      setState(() => _orientationMode = _OrientationMode.portraitUp);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _onSeekStart(double value) {
    _isDraggingSlider = true;
    _positionNotifier.value = Duration(milliseconds: value.toInt());
  }

  void _onSeekEnd(double value) {
    _isDraggingSlider = false;
    // 立即更新 UI 到目标位置，不等 Timer.periodic
    _position = Duration(milliseconds: value.toInt());
    _positionNotifier.value = _position;
    try {
      _player.seek(position: value.toInt(), flags: mdk.SeekFlag(mdk.SeekFlag.keyFrame));
    } catch (_) {}
    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionSeek, position: value / 1000);
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _player.state == mdk.PlaybackState.playing) {
          setState(() {
            _showControls = false;
            _showSubtitleMenu = false;
            _showAudioMenu = false;
            _showDecodeModeMenu = false;
          });
        }
      });
    }
  }

  void _closeAllMenus() {
    setState(() {
      _showSubtitleMenu = false;
      _showAudioMenu = false;
      _showDecodeModeMenu = false;
    });
    _showBrightnessBarNotifier.value = false;
    _showVolumeBarNotifier.value = false;
  }

  // 切集（房主操作 + 发送RTM命令）
  void _switchToEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    if (index == _currentEpisodeIndex && _isPlayerReady) return;

    final requestId = ++_playRequestId;

    // Host: 发送 syncPlay 命令
    if (_isHost && _rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);
      final position = _player.position / 1000.0;
      _logSyncEvent('发送 syncPlay: ep=$index, pos=${position.toStringAsFixed(1)}s');
      await rtmService.sendCommand(
        action: AppConstants.actionSyncPlay,
        episodeIndex: index,
        itemId: _episodes[index].id,
        position: position,
      );
    }

    if (requestId != _playRequestId || !mounted) return;
    await _loadEpisodeStream(index);
    _rebuildGroups();
  }

  // 删除剧集（sendRtm=true 时为房主操作，false 时为观众端本地删除）
  void _removeEpisode(int index, {bool sendRtm = true}) {
    if (index < 0 || index >= _episodes.length) return;
    if (sendRtm && !_isHost) return;

    final removedName = _episodes[index].name;
    _episodes.removeAt(index);

    if (_currentEpisodeIndex == index) {
      _currentEpisodeIndex = -1;
      _isPlayerReady = false;
      _player.state = mdk.PlaybackState.stopped;
      _syncPlayState();
    } else if (_currentEpisodeIndex > index) {
      _currentEpisodeIndex--;
    }

    _hasEpisodeList = _episodes.isNotEmpty;
    _addBroadcastMessage('已移除: $removedName');
    setState(() { _rebuildGroups(); });

    // 房主发送删除命令
    if (sendRtm && _rtmChannel != null) {
      ref.read(rtmServiceProvider).sendCommand(
        action: AppConstants.actionRemoveEpisode,
        episodeIndex: index,
      );
    }
  }

  void _handleAddResource(Map<String, dynamic> message) {
    _addResourceLocally(message);
  }

  void _addResourceLocally(Map<String, dynamic> data) {
    final isSeries = data['isSeries'] as bool? ?? false;
    final name = data['name'] as String? ?? '';
    final poster = data['poster'] as String? ?? '';
    final seriesName = data['seriesName'] as String? ?? '';

    if (isSeries) {
      final episodes = data['episodes'] as List<dynamic>?;
      if (episodes != null && episodes.isNotEmpty) {
        for (final ep in episodes) {
          final epMap = ep as Map<String, dynamic>;
          _episodes.add(EpisodeInfo(
            id: epMap['id'] as String,
            name: epMap['name'] as String? ?? '',
            season: epMap['season'] as int? ?? 0,
            number: epMap['number'] as int? ?? 0,
            poster: epMap['poster'] as String? ?? '',
            seriesName: seriesName,
          ));
        }
        if (_seriesName.isEmpty) {
          _seriesName = seriesName;
        }
        _hasEpisodeList = true;
        _addBroadcastMessage('已添加: $name (${episodes.length}集)');
      }
    } else {
      final itemId = data['itemId'] as String?;
      if (itemId != null && itemId.isNotEmpty) {
        _episodes.add(EpisodeInfo(
          id: itemId,
          name: name,
          poster: poster,
          mediaSourceId: data['mediaSourceId'] as String?,
        ));
        _hasEpisodeList = true;
        _addBroadcastMessage('已添加: $name');
      }
    }
    setState(() { _rebuildGroups(); });
  }

  void _sendAddResourceRTM(Map<String, dynamic> data) {
    if (_rtmChannel == null) return;
    final rtmService = ref.read(rtmServiceProvider);
    final isSeries = data['isSeries'] as bool? ?? false;
    rtmService.sendAddResource(
      itemId: data['itemId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      poster: data['poster'] as String? ?? '',
      isSeries: isSeries,
      seriesName: data['seriesName'] as String? ?? '',
      episodes: isSeries ? (data['episodes'] as List<Map<String, dynamic>>?) : null,
    );
  }

  // 复制房间码
  void _copyRoomCode() {
    if (widget.roomCode == null) return;
    Clipboard.setData(ClipboardData(text: widget.roomCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制房间码')),
    );
  }

  Future<Uint8List?> _captureQrImage() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveQrToGallery() async {
    final bytes = await _captureQrImage();
    if (bytes == null || !mounted) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/himi_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (Platform.isAndroid) {
        final dcimDir = Directory('/storage/emulated/0/DCIM/Himi');
        if (!dcimDir.existsSync()) dcimDir.createSync(recursive: true);
        await file.copy('${dcimDir.path}/himi_qr.png');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _shareQrImage() async {
    final bytes = await _captureQrImage();
    if (bytes == null || !mounted) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/himi_qr.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'HIMI 房间二维码',
          text: '来一起看电影吧！用 HIMI 扫描二维码加入房间',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  void _showShareRoomSheet() {
    if (widget.roomCode == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '分享加入房间',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: widget.roomCode!,
                    version: QrVersions.auto,
                    size: 180,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.roomCode!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(ctx); _saveQrToGallery(); },
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('保存图片'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () { Navigator.pop(ctx); _shareQrImage(); },
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('分享图片'),
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(ctx); _copyRoomCode(); },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 先停止播放器，确保音频立即停止
    try {
      _player.state = mdk.PlaybackState.stopped;
    } catch (_) {}

    _positionTimer?.cancel();
    _hideControlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rateRestoreTimer?.cancel();
    _gestureHintTimer?.cancel();
    _gestureBarTimer?.cancel();
    _roomInfoTimeout?.cancel();
    _rtmSubscription?.cancel();
    _presenceSubscription?.cancel();
    _tracksSubscription?.cancel();
    _accelSub?.cancel();
    try { _broadcastScrollController.dispose(); } catch (_) {}

    // 释放 ValueNotifier（包 try-catch 确保后续代码执行）
    try { _positionNotifier.dispose(); } catch (_) {}
    try { _durationNotifier.dispose(); } catch (_) {}
    try { _brightnessNotifier.dispose(); } catch (_) {}
    try { _volumeNotifier.dispose(); } catch (_) {}
    try { _isPlayingNotifier.dispose(); } catch (_) {}
    try { _broadcastVersion.dispose(); } catch (_) {}
    try { _syncEventsVersion.dispose(); } catch (_) {}
    try { _showBrightnessBarNotifier.dispose(); } catch (_) {}
    try { _showVolumeBarNotifier.dispose(); } catch (_) {}

    // 恢复屏幕亮度
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}

    // 释放锁屏保持
    try {
      WakelockPlus.disable();
    } catch (_) {}

    // 清理 RTM
    if (widget.roomCode != null) {
      try {
        final rtmService = ref.read(rtmServiceProvider);
        if (_rtmChannel != null) {
          rtmService.unsubscribe(_rtmChannel!);
        }
        rtmService.logout();
      } catch (_) {}
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    WidgetsBinding.instance.removeObserver(this);
    try { _player.dispose(); } catch (_) {}
    super.dispose();
  }

  bool get _canControlPlayback {
    if (widget.roomCode == null) return true;
    return _isHost;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmLeaveRoom();
        if (shouldPop && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            if (_showSubtitleMenu || _showAudioMenu || _showDecodeModeMenu || _showBrightnessBarNotifier.value || _showVolumeBarNotifier.value) {
              _closeAllMenus();
            } else {
              _toggleControls();
            }
          },
          onDoubleTap: _onDoubleTap,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          behavior: HitTestBehavior.opaque,
          child: _buildResponsiveLayout(),
        ),
      ),
    );
  }

  Widget _buildResponsiveLayout() {
    final isPortrait = MediaQuery.of(context).orientation ==
            Orientation.portrait &&
        (Platform.isAndroid || Platform.isIOS);

    final showPanel = widget.roomCode != null && _showPanel;

    if (isPortrait && showPanel) {
      // 手机竖屏：视频在上，资源面板在下
      return Column(
        children: [
          Expanded(flex: 3, child: _buildVideoArea()),
          SizedBox(
            height: 280,
            child: _buildResourcePanel(),
          ),
        ],
      );
    } else if (showPanel) {
      // 桌面/横屏：视频在左，资源面板在右
      return Row(
        children: [
          Expanded(flex: 3, child: _buildVideoArea()),
          SizedBox(
            width: 320,
            child: _buildResourcePanel(),
          ),
        ],
      );
    } else {
      return _buildVideoArea();
    }
  }

  Widget _buildVideoArea() {
    return Stack(
      children: [
        // 视频 / 占位文字
        if (_isPlayerReady || (!_hasEpisodeList && widget.roomCode == null))
          Center(
            child: ValueListenableBuilder<int?>(
              valueListenable: _player.textureId,
              builder: (context, textureId, child) {
                if (textureId == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  );
                }
                // 无视频尺寸时先按原尺寸渲染，拿到尺寸后 setState 重新渲染
                if (_videoNativeSize == null) {
                  return Center(
                    child: Texture(textureId: textureId),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final containerW = constraints.maxWidth;
                    final containerH = constraints.maxHeight;
                    final renderW = _videoNativeSize!.width;
                    final renderH = _videoNativeSize!.height;

                    switch (_videoFit) {
                      case BoxFit.none:
                        return Texture(textureId: textureId);
                      case BoxFit.fill:
                        final scaleX = containerW / renderW;
                        final scaleY = containerH / renderH;
                        return Center(
                          child: Transform.scale(
                            scaleX: scaleX,
                            scaleY: scaleY,
                            child: SizedBox(
                              width: renderW,
                              height: renderH,
                              child: Texture(textureId: textureId),
                            ),
                          ),
                        );
                      case BoxFit.cover:
                        final scale = max(containerW / renderW, containerH / renderH);
                        return ClipRect(
                          child: Center(
                            child: Transform.scale(
                              scale: scale,
                              child: SizedBox(
                                width: renderW,
                                height: renderH,
                                child: Texture(textureId: textureId),
                              ),
                            ),
                          ),
                        );
                      default: // contain
                        final scale = min(containerW / renderW, containerH / renderH);
                        return Center(
                          child: Transform.scale(
                            scale: scale,
                            child: SizedBox(
                              width: renderW,
                              height: renderH,
                              child: Texture(textureId: textureId),
                            ),
                          ),
                        );
                    }
                  },
                );
              },
            ),
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline,
                    size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  '请从资源面板选择要播放的内容',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          ),

        // TopBar（渐变浮层）
        if (_showControls)
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

        // 解码模式选择面板
        if (_showDecodeModeMenu)
          Positioned(
            top: MediaQuery.of(context).padding.top + 48,
            right: 12,
            child: DecodeModePanel(
              isDolbyVisionP5: _isDolbyVisionP5,
              onSwitchMode: _switchDecodeMode,
            ),
          ),

        // 手势提示浮层（快进快退/双击播放暂停）
        if (_showGestureOverlay)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: _buildGestureHint(),
          ),

        // 亮度柱式进度条（右侧）
        ValueListenableBuilder<bool>(
          valueListenable: _showBrightnessBarNotifier,
          builder: (context, show, _) => show ? _buildBrightnessBar() : const SizedBox.shrink(),
        ),

        // 音量柱式进度条（左侧）
        ValueListenableBuilder<bool>(
          valueListenable: _showVolumeBarNotifier,
          builder: (context, show, _) => show ? _buildVolumeBar() : const SizedBox.shrink(),
        ),

        // Controls（底部渐变浮层，仅视频区域底部）
        if (_showControls && (_isPlayerReady || (!_hasEpisodeList && widget.roomCode == null)))
          Positioned(bottom: 0, left: 0, right: 0, child: _buildControls()),

        // 加载指示器
        if (_duration.inMilliseconds == 0 && _isPlayerReady)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          ),

        // 同步调试面板
        if (ref.watch(settingsProvider).showSyncDebug && widget.roomCode != null)
          Positioned(
            left: _debugPanelX,
            top: _debugPanelY,
            child: SyncDebugPanel(
              isHost: _isHost,
              rtmChannel: _syncRtmChannel,
              rtmStatus: _syncRtmStatus,
              metadataTestResult: _syncMetadataTestResult,
              videoCodec: _videoCodec,
              videoResolution: _videoResolution,
              voStatus: _voStatus,
              decodeMode: ref.read(settingsProvider).decodeMode,
              actualDecoder: _actualDecoderFull,
              hdrType: _hdrType,
              isDolbyVisionP5: _isDolbyVisionP5,
              onDrag: (delta) {
                setState(() {
                  _debugPanelX += delta.dx;
                  _debugPanelY += delta.dy;
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 12,
        right: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              final shouldPop = await _confirmLeaveRoom();
              if (shouldPop && context.mounted) Navigator.pop(context);
            },
          ),
          const Spacer(),
          // 解码模式按钮
          GestureDetector(
            onTap: _isDolbyVisionP5 ? null : () => setState(() => _showDecodeModeMenu = !_showDecodeModeMenu),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _showDecodeModeMenu
                    ? const Color(0xFF6366F1)
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.memory, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _isDolbyVisionP5 ? 'SW' : (AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ?? 'Auto'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (widget.roomCode != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: '分享房间',
              onPressed: _showShareRoomSheet,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _switchDecodeMode(String mode) async {
    if (_isSwitchingDecode) return;
    _isSwitchingDecode = true;

    try {
      final wasPlaying = _player.state == mdk.PlaybackState.playing;

      // 获取当前位置
      final currentPos = _player.position;

      // Step1: 暂停（防止切换期间解码器输出帧导致撕裂）
      if (wasPlaying) {
        _player.state = mdk.PlaybackState.paused;
        _syncPlayState();
      }

      // Step2: 切换解码器
      final decoders = DecodeModeService.resolveDecoders(mode);
      _player.videoDecoders = decoders;

      // Step3: seek 触发帧刷新（强制新解码器解码当前帧）
      if (currentPos > 0) {
        try {
          await _player.seek(position: currentPos);
        } catch (_) {}
      }

      // Step4: 恢复播放
      if (wasPlaying) {
        _player.state = mdk.PlaybackState.playing;
        _syncPlayState();
      }

      // Step5: 持久化设置
      await ref.read(settingsProvider.notifier).update(decodeMode: mode);
      setState(() => _showDecodeModeMenu = false);
    } finally {
      _isSwitchingDecode = false;
    }
  }

  // ========== 手势控制 ==========
  double _horizontalDragAccumulator = 0;

  void _onDoubleTap() {
    _togglePlayPause();
    _showGestureIcon(_player.state == mdk.PlaybackState.playing ? Icons.play_arrow : Icons.pause);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragAccumulator += details.primaryDelta ?? 0;
    // 每累计 100 像素显示一次预览
    if (_horizontalDragAccumulator.abs() > 100) {
      final deltaMs = (_horizontalDragAccumulator / 100 * 5000).round().clamp(-60000, 60000);
      final currentMs = _position.inMilliseconds;
      final previewMs = (currentMs + deltaMs).clamp(0, _duration.inMilliseconds);
      final previewDuration = Duration(milliseconds: previewMs);
      final minutes = previewDuration.inMinutes;
      final seconds = (previewDuration.inSeconds % 60).toString().padLeft(2, '0');
      _showGestureHint('$minutes:$seconds');
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // 使用与预览相同的累加器计算，确保预览与实际 seek 位置一致
    final deltaMs = (_horizontalDragAccumulator / 100 * 5000).round().clamp(-60000, 60000);
    _horizontalDragAccumulator = 0;
    if (deltaMs != 0) {
      _seekRelative(deltaMs);
    } else {
      // 没有足够拖动距离时使用速度回退
      final delta = details.primaryVelocity ?? 0;
      final seekDelta = (delta / 100 * 5000).round();
      if (seekDelta != 0) _seekRelative(seekDelta);
    }
  }

  void _seekRelative(int deltaMs) {
    // 限制最大跳转 ±60 秒
    final clampedDelta = deltaMs.clamp(-60000, 60000);
    final currentMs = _position.inMilliseconds;
    final targetMs = (currentMs + clampedDelta).clamp(0, _duration.inMilliseconds);

    // 立即更新 UI
    _position = Duration(milliseconds: targetMs);
    _positionNotifier.value = _position;

    try {
      _player.seek(position: targetMs, flags: mdk.SeekFlag(mdk.SeekFlag.keyFrame));
    } catch (_) {}

    final seconds = (clampedDelta / 1000).round();
    _showGestureHint(seconds > 0 ? '+${seconds}s' : '${seconds}s');

    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionSeek, position: targetMs / 1000);
    }
  }

  void _showGestureIcon(IconData icon) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureOverlayIcon = icon;
      _showGestureOverlay = true;
    });
    _gestureHintTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showGestureOverlay = false);
    });
  }

  void _showGestureHint(String text) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureHintText = text;
      _gestureOverlayIcon = null;
      _showGestureOverlay = true;
    });
    _gestureHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showGestureOverlay = false);
    });
  }

  Widget _buildGestureHint() {
    if (_gestureOverlayIcon != null) {
      return Center(
        child: Icon(_gestureOverlayIcon!, color: Colors.white70, size: 48),
      );
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _gestureHintText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ========== 垂直手势：亮度/音量 ==========
  void _onVerticalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isLeftSide = details.globalPosition.dx < screenWidth / 2;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (_isLeftSide) {
      // 左侧：调节亮度
      _brightness = (_brightness - delta / 600).clamp(0.0, 1.0);
      _setBrightness(_brightness);
      _brightnessNotifier.value = _brightness;
      _showBrightnessBarNotifier.value = true;
      _showVolumeBarNotifier.value = false;
    } else {
      // 右侧：调节音量
      final newVol = (_volume - delta / 600 * 100).clamp(0.0, 100.0);
      _volume = newVol;
      _player.volume = newVol / 100.0; // fvp 使用 0.0-1.0 范围
      _volumeNotifier.value = _volume;
      _showVolumeBarNotifier.value = true;
      _showBrightnessBarNotifier.value = false;
    }
    _startGestureBarTimer();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _startGestureBarTimer();
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {}
  }

  void _startGestureBarTimer() {
    _gestureBarTimer?.cancel();
    _gestureBarTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        _showBrightnessBarNotifier.value = false;
        _showVolumeBarNotifier.value = false;
      }
    });
  }

  Widget _buildBrightnessBar() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.15,
      bottom: MediaQuery.of(context).size.height * 0.15,
      right: 20,
      child: ValueListenableBuilder<double>(
        valueListenable: _brightnessNotifier,
        builder: (context, brightness, _) {
          return _buildVerticalBar(
            value: brightness,
            icon: Icons.brightness_6,
            color: const Color(0xFFFFD54F),
          );
        },
      ),
    );
  }

  Widget _buildVolumeBar() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.15,
      bottom: MediaQuery.of(context).size.height * 0.15,
      left: 20,
      child: ValueListenableBuilder<double>(
        valueListenable: _volumeNotifier,
        builder: (context, volume, _) {
          return _buildVerticalBar(
            value: volume / 100,
            icon: volume == 0
                ? Icons.volume_off
                : volume < 50
                    ? Icons.volume_down
                    : Icons.volume_up,
            color: const Color(0xFF6366F1),
          );
        },
      ),
    );
  }

  Widget _buildVerticalBar({
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 8),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: color,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: color,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: value,
                  onChanged: null,
                ),
              ),
            ),
          ),
          Text(
            '${(value * 100).round()}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFF6366F1),
                inactiveTrackColor: Colors.white24,
                thumbColor: const Color(0xFF6366F1),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: ValueListenableBuilder2<Duration, Duration>(
                first: _positionNotifier,
                second: _durationNotifier,
                builder: (context, pos, dur, _) {
                  return Slider(
                    value: dur.inMilliseconds > 0
                        ? pos.inMilliseconds
                            .toDouble()
                            .clamp(0, dur.inMilliseconds.toDouble())
                        : 0,
                    max: dur.inMilliseconds > 0
                        ? dur.inMilliseconds.toDouble()
                        : 1,
                    onChangeStart: _canControlPlayback ? _onSeekStart : null,
                    onChanged: (v) {
                      _positionNotifier.value = Duration(milliseconds: v.toInt());
                    },
                    onChangeEnd: _canControlPlayback ? _onSeekEnd : null,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  ValueListenableBuilder2<Duration, Duration>(
                    first: _positionNotifier,
                    second: _durationNotifier,
                    builder: (context, pos, dur, _) {
                      return Text(
                        '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      );
                    },
                  ),
                ],
              ),
            ),

            if (_showSubtitleMenu) ...[
              _buildExpandablePanel(
                maxHeight: 180,
                child: SubtitleMenuPanel(
                  player: _player,
                  subtitleStreams: _embySubtitleStreams,
                  activeSubtitleIndex: _activeSubtitleIndex,
                  useServerBurnIn: _useServerSubtitleBurnIn,
                    itemId: _episodes.isNotEmpty ? _episodes[_currentEpisodeIndex].id : widget.itemId,
                  mediaSourceId: widget.mediaSourceId,
                  token: _currentToken,
                  onSubtitleSelected: (index) {
                    if (index == null) {
                      _player.activeSubtitleTracks = [];
                      _useServerSubtitleBurnIn = false;
                      _activeSubtitleIndex = null;
                    } else {
                      _selectEmbySubtitle(index);
                    }
                  },
                  onLoadLocal: _loadLocalSubtitle,
                  onClose: () => setState(() => _showSubtitleMenu = false),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_showAudioMenu) ...[
              _buildExpandablePanel(
                maxHeight: 180,
                child: AudioTrackMenuPanel(
                  player: _player,
                  audioStreams: _embyAudioStreams,
                  onAudioSelected: _selectEmbyAudio,
                  onClose: () => setState(() => _showAudioMenu = false),
                ),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                // 上一集
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _totalEpisodeCount > 1)
                  GestureDetector(
                    onTap: _currentEpisodeIndex > 0
                        ? () => _switchToEpisode(_currentEpisodeIndex - 1)
                        : null,
                    child: Icon(
                      Icons.skip_previous,
                      color: _currentEpisodeIndex > 0
                          ? Colors.white
                          : Colors.white24,
                      size: 28,
                    ),
                  ),
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _totalEpisodeCount > 1)
                  const SizedBox(width: 8),

                // 播放/暂停
                if (_canControlPlayback)
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _isPlayingNotifier,
                      builder: (context, isPlaying, child) {
                        return Icon(
                          isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          color: Colors.white,
                          size: 36,
                        );
                      },
                    ),
                  ),
                if (_canControlPlayback) const SizedBox(width: 8),

                // 下一集
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _totalEpisodeCount > 1)
                  GestureDetector(
                    onTap: _currentEpisodeIndex < _totalEpisodeCount - 1
                        ? () =>
                            _switchToEpisode(_currentEpisodeIndex + 1)
                        : null,
                    child: Icon(
                      Icons.skip_next,
                      color: _currentEpisodeIndex < _totalEpisodeCount - 1
                          ? Colors.white
                          : Colors.white24,
                      size: 28,
                    ),
                  ),
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _totalEpisodeCount > 1)
                  const SizedBox(width: 8),

                const Spacer(),

                // 字幕
                _buildControlButton(
                  icon: Icons.subtitles,
                  onTap: () {
                    setState(() {
                      _showSubtitleMenu = !_showSubtitleMenu;
                      _showAudioMenu = false;
                    });
                  },
                  badge: _embySubtitleStreams.isNotEmpty
                      ? '${_embySubtitleStreams.length}'
                      : null,
                ),
                const SizedBox(width: 20),

                // 音轨
                _buildControlButton(
                  icon: Icons.audiotrack,
                  onTap: () {
                    setState(() {
                      _showAudioMenu = !_showAudioMenu;
                      _showSubtitleMenu = false;
                    });
                  },
                  badge: _embyAudioStreams.isNotEmpty
                      ? '${_embyAudioStreams.length}'
                      : null,
                ),

                // 面板切换（仅房间模式）
                if (widget.roomCode != null) ...[
                  const SizedBox(width: 20),
                  _buildControlButton(
                    icon: _showPanel
                        ? Icons.close_fullscreen
                        : Icons.open_in_full,
                    onTap: () => setState(() => _showPanel = !_showPanel),
                  ),
                ],

                // 横竖屏（移动端都显示）
                if (Platform.isAndroid || Platform.isIOS) ...[
                  const SizedBox(width: 20),
                  _buildControlButton(
                    icon: _orientationMode == _OrientationMode.portraitUp
                        ? Icons.screen_lock_landscape
                        : Icons.screen_lock_portrait,
                    onTap: _toggleOrientation,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandablePanel({
    required double maxHeight,
    required Widget child,
  }) {
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          if (badge != null)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ========== 资源面板 ==========
  Widget _buildResourcePanel() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          // 面板头部
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '资源',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_roomData != null && _isHost && _player.state != mdk.PlaybackState.playing) ...[
                  GestureDetector(
                    onTap: () async {
                      SystemChrome.setPreferredOrientations([
                        DeviceOrientation.portraitUp,
                      ]);
                      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                      final itemData = await showSearch<Map<String, dynamic>?>(
                        context: context,
                        delegate: RoomSearchDelegate(ref, roomCode: widget.roomCode!),
                      );
                      _switchToLandscape(_OrientationMode.landscapeLeft);
                      if (itemData != null && mounted) {
                        final resourceData = await context.push<Map<String, dynamic>>(
                          '/detail/${itemData['itemId']}?roomMode=true&roomCode=${Uri.encodeComponent(widget.roomCode!)}',
                        );
                        if (resourceData != null && mounted) {
                          _addResourceLocally(resourceData);
                          _sendAddResourceRTM(resourceData);
                        }
                      }
                    },
                    child: const Icon(Icons.search, color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_roomData != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people,
                            color: Colors.white70, size: 12),
                        const SizedBox(width: 3),
                        Text('$_onlineUserCount',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (_roomData != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          _isHost ? const Color(0xFF6366F1) : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isHost ? '房主' : (_audienceName ?? '观众'),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),

          // 资源分组列表
          Expanded(
            child: _resourceGroups.isEmpty
                ? const Center(
                    child: Text('暂无资源',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 13)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _resourceGroups.length,
                    itemBuilder: (ctx, i) => _buildGroupWidget(_resourceGroups[i]),
                  ),
          ),

          // 播报板（底部）
          if (_roomData != null) _buildBroadcastBoardInPanel(),
        ],
      ),
    );
  }

  Widget _buildGroupWidget(_ResourceGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 组标题（电影 / 剧名）
        InkWell(
          onTap: () => setState(() => group.collapsed = !group.collapsed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16213E),
            child: Row(
              children: [
                Icon(
                  group.collapsed ? Icons.chevron_right : Icons.expand_more,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  group.isMovie ? '(${group.totalCount})' : '(${group.totalCount}集)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // 展开内容
        if (!group.collapsed)
          if (group.isMovie)
            // 电影组：直接列出
            ...group.seasons.first.episodes.map((item) {
              final flatIndex = _findFlatIndex(item.id);
              return _buildEpisodeListItem(flatIndex, item);
            })
          else
            // 电视剧组：按季分组
            ...group.seasons.map((season) => _buildSeasonWidget(group, season)),
      ],
    );
  }

  Widget _buildSeasonWidget(_ResourceGroup group, _SeasonGroup season) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 季标题
        InkWell(
          onTap: () => setState(() => season.collapsed = !season.collapsed),
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 12, top: 6, bottom: 6),
            color: const Color(0xFF1A1A2E),
            child: Row(
              children: [
                Icon(
                  season.collapsed ? Icons.chevron_right : Icons.expand_more,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '第${season.seasonNumber}季',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '(${season.episodes.length}集)',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        // 展开时显示集列表
        if (!season.collapsed)
          ...season.episodes.map((item) {
            final flatIndex = _findFlatIndex(item.id);
            return _buildEpisodeListItem(flatIndex, item);
          }),
      ],
    );
  }

  int _findFlatIndex(String itemId) {
    return _episodes.indexWhere((e) => e.id == itemId);
  }

  Widget _buildEpisodeListItem(int flatIndex, _ResourceItem item) {
    final isPlaying = flatIndex == _currentEpisodeIndex;
    final isMovie = item.isMovie;

    return InkWell(
      onTap: () {
        if (!_isHost) return;
        if (isPlaying) {
          _togglePlayPause();
        } else {
          _switchToEpisode(flatIndex);
        }
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isPlaying
              ? const Color(0xFF6366F1).withValues(alpha: 0.3)
              : null,
          border: Border(
            left: BorderSide(
              color: isPlaying
                  ? const Color(0xFF6366F1)
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // 播放/暂停按钮（仅房主）
            if (_isHost)
              GestureDetector(
                onTap: () {
                  if (isPlaying) {
                    _togglePlayPause();
                  } else {
                    _switchToEpisode(flatIndex);
                  }
                },
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isPlayingNotifier,
                  builder: (context, isPlayingNow, child) {
                    return Icon(
                      isPlaying && isPlayingNow
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      color: isPlaying
                          ? const Color(0xFF6366F1)
                          : Colors.white54,
                      size: 22,
                    );
                  },
                ),
              ),
            if (_isHost) const SizedBox(width: 8),

            // 缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 56,
                height: 36,
                child: item.poster.isNotEmpty
                    ? EmbyImage(url: item.poster, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.movie,
                            size: 16, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(width: 8),

            // 集信息
            Expanded(
              child: isMovie
                  ? Text(
                      item.name,
                      style: TextStyle(
                        color: isPlaying ? Colors.white : Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'S${item.season.toString().padLeft(2, '0')}E${item.number.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: isPlaying
                                ? const Color(0xFF6366F1)
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: isPlaying
                                ? Colors.white
                                : Colors.white54,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),

            // 删除按钮（仅房主）
            if (_isHost)
              GestureDetector(
                onTap: () => _removeEpisode(flatIndex),
                child: const Icon(Icons.close,
                    color: Colors.white24, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBroadcastBoardInPanel() {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: _broadcastVersion,
        builder: (context, version, _) {
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.campaign,
                        color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Text('播报 (${_broadcastMessages.length})',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              Expanded(
                child: _broadcastMessages.isEmpty
                    ? const Center(
                        child: Text('暂无消息',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 11)),
                      )
                    : ListView.builder(
                        controller: _broadcastScrollController,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _broadcastMessages.length,
                        itemBuilder: (ctx, i) => Text(
                          _broadcastMessages[i],
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _selectEmbySubtitle(int embyIndex) {
    final stream = _embySubtitleStreams[embyIndex];
    final isExternal = stream.isExternal ||
        stream.subtitleLocationType == 'ExternalStream';

    if (isExternal) {
      // 外挂字幕：用 fvp setMedia 加载外部文件，不重载流
      final itemId = _episodes.isNotEmpty
          ? _episodes[_currentEpisodeIndex].id
          : widget.itemId;
      final embyService = ref.read(embyServiceProvider);
      final config = ref.read(embyConfigProvider);
      final subtitleUrl = embyService.getSubtitleUrl(
        itemId,
        subtitleIndex: stream.index,
        mediaSourceId: widget.mediaSourceId,
      );
      final token = config?.accessToken ?? '';
      if (token.isNotEmpty) {
        _player.setProperty('avio.headers', 'X-Emby-Token: $token');
      }
      _player.setMedia(subtitleUrl, mdk.MediaType.subtitle);
      _player.activeSubtitleTracks = [embyIndex];
    } else {
      // 内嵌字幕：用 fvp 原生轨道切换，瞬间完成
      _player.activeSubtitleTracks = [embyIndex];
    }

    _useServerSubtitleBurnIn = false;
    _activeSubtitleIndex = stream.index;
  }

  void _selectEmbyAudio(int embyIndex) {
    // fvp: 通过 activeAudioTracks 选择音轨
    _player.activeAudioTracks = [embyIndex];
  }

  Future<void> _loadLocalSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub', 'idx'],
      );
      if (result == null || !mounted) return;

      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) return;

      // 加载本地字幕文件
      _player.setMedia(filePath, mdk.MediaType.subtitle);

      // 获取当前字幕轨道数量，新加载的字幕在末尾
      final subtitleCount = _player.mediaInfo.subtitle?.length ?? 0;
      if (subtitleCount > 0) {
        _player.activeSubtitleTracks = [subtitleCount - 1];
      }

      setState(() {
        _activeSubtitleIndex = -1;
        _useServerSubtitleBurnIn = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载字幕: ${file.name}')),
        );
      }
    } catch (e) {
      LogService().log('Player', '加载本地字幕失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载字幕失败: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 同时监听两个 ValueNotifier 的 Builder
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;
  final Widget? child;

  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, child) {
            return builder(context, a, b, child);
          },
          child: child,
        );
      },
    );
  }
}