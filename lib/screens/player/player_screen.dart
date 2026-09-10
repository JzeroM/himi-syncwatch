import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:himi_syncwatch/core/constants.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/rtm_provider.dart';
import 'package:himi_syncwatch/services/rtm_service.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

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

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  Timer? _heartbeatTimer;
  StreamSubscription? _rtmSubscription;
  bool _isHost = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _myUserId;
  String? _rtmChannel;
  String? _rtmAppId;

  double _volume = 100;
  bool _syncPaused = false;
  Timer? _hideControlsTimer;

  bool _showVolumeSlider = false;
  bool _showSubtitleMenu = false;
  bool _showAudioMenu = false;

  List<SubtitleTrack> _subtitleTracks = [];
  SubtitleTrack? _currentSubtitle;
  List<AudioTrack> _audioTracks = [];
  AudioTrack? _currentAudio;
  StreamSubscription? _tracksSubscription;
  bool _subtitleAutoSelected = false;

  List<MediaStream> _embySubtitleStreams = [];
  List<MediaStream> _embyAudioStreams = [];
  int? _embyDefaultAudioIndex;
  int? _activeSubtitleIndex;
  bool _useServerSubtitleBurnIn = false;
  bool _isLandscape = false;
  BoxFit _videoFit = BoxFit.contain;

  Map<String, dynamic>? _roomData;

  // 播报板 + 在线用户
  final List<String> _broadcastMessages = [];
  int _onlineUserCount = 0;
  StreamSubscription? _presenceSubscription;
  final ScrollController _broadcastScrollController = ScrollController();
  String? _audienceName;

  // 剧集资源列表
  List<String> _episodeIds = [];
  List<String> _episodeNames = [];
  List<int> _episodeSeasons = [];
  List<int> _episodeNumbers = [];
  List<String> _episodePosters = [];
  String _seriesName = '';
  int _currentEpisodeIndex = -1;
  bool _hasEpisodeList = false;
  bool _isPlayerReady = false;
  bool _seriesCollapsed = false;
  bool _roomSyncInitializing = false;

  // 同步调试面板
  bool _showSyncDebug = false;
  String _syncRtmChannel = '-';
  String _syncRtmStatus = '未连接';
  String _syncMetadataPlayUrl = '空';
  String _syncMetadataIndex = '-';
  String _syncMetadataAllKeys = '-'; // metadata 全量 key 列表
  String _syncMetadataWriteDiag = '-'; // 最后一次写入诊断
  String _syncMetadataReadDiag = '-'; // 最后一次读取诊断
  String _syncMetadataTestResult = '-'; // 自检结果
  List<String> _syncEvents = [];

  void _logSyncEvent(String event) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _syncEvents.add('[$time] $event');
      if (_syncEvents.length > 15) _syncEvents.removeAt(0);
    });
  }

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(libass: true),
    );
    _controller = VideoController(_player);
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
        _episodeIds = pendingEpisodes.map((e) => e['id'] as String).toList();
        _episodeNames = pendingEpisodes.map((e) => e['name'] as String? ?? '').toList();
        _episodeSeasons = pendingEpisodes.map((e) => e['season'] as int? ?? 0).toList();
        _episodeNumbers = pendingEpisodes.map((e) => e['number'] as int? ?? 0).toList();
        _episodePosters = pendingEpisodes.map((e) => e['poster'] as String? ?? '').toList();
        _seriesName = pendingEpisodes.first['seriesName'] as String? ?? '';
        _hasEpisodeList = true;
        // 读完清空 provider，避免重复使用
        ref.read(pendingRoomEpisodesProvider.notifier).state = null;
      } else if (pendingMovie != null) {
        // 电影：单条记录
        _episodeIds = [pendingMovie['id'] as String];
        _episodeNames = [pendingMovie['name'] as String? ?? '电影'];
        _episodeSeasons = [0];
        _episodeNumbers = [0];
        _episodePosters = [pendingMovie['poster'] as String? ?? ''];
        _seriesName = '';
        _hasEpisodeList = true;
        ref.read(pendingRoomMovieProvider.notifier).state = null;
      }
    }

    _initPlayerProperties();
    _setupPlayerListeners();

    if (widget.roomCode != null) {
      _setupRoomSync();
    }
  }

  void _initPlayerProperties() async {
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      await native.setProperty('sub-visibility', 'yes');
      await native.setProperty('sub-auto', 'fuzzy');
      await native.setProperty('sub-font-size', '40');
      await native.setProperty('sub-border-size', '2');
      await native.setProperty('sub-shadow-offset', '1');
      await native.setProperty('sub-margin-y', '22');
    }
  }

  Future<void> _loadEpisodeStream(int episodeIndex) async {
    if (episodeIndex < 0 || episodeIndex >= _episodeIds.length) return;

    final itemId = _episodeIds[episodeIndex];

    // 先设置 _currentEpisodeIndex，这样 publishPlayInfo 能拿到正确的值
    setState(() {
      _currentEpisodeIndex = episodeIndex;
    });

    // 获取 Emby 详情（字幕/音轨信息）
    final embyService = ref.read(embyServiceProvider);
    final config = ref.read(embyConfigProvider);

    // 如果没有配置 Emby，跳过详情获取
    if (config != null && config.isAuthenticated) {
      try {
        final details = await embyService.getItemDetails(itemId);
        if (details != null && mounted) {
          final source = details.mediaSources.firstWhere(
            (s) => s.id == widget.mediaSourceId,
            orElse: () =>
                details.mediaSources.firstOrNull ?? MediaSource(id: '', name: ''),
          );
          setState(() {
            _embyAudioStreams = source.audioStreams;
            _embySubtitleStreams = source.subtitleStreams;
            _embyDefaultAudioIndex = source.defaultAudioStreamIndex;
          });
        }
      } catch (e) {
        print('[Player] 获取 Emby 详情失败: $e');
      }
    }

    // 加载流
    await _loadStream(itemId: itemId);

    setState(() {
      _isPlayerReady = true;
    });
    _autoExpandSeries();
  }

  Future<String?> _loadStream({
    String? itemId,
    int? subtitleStreamIndex,
  }) async {
    final targetItemId = itemId ?? widget.itemId;

    final embyService = ref.read(embyServiceProvider);
    final config = ref.read(embyConfigProvider);
    final token = config?.accessToken ?? '';

    try {
      final streamUrl = embyService.getStreamUrl(
        targetItemId,
        mediaSourceId: widget.mediaSourceId,
        subtitleStreamIndex: subtitleStreamIndex,
      );

      final url = await _resolveStreamUrl(streamUrl, token);

      final pos = _player.state.position;
      final wasPlaying = _player.state.playing;

      await _player.open(Media(url, httpHeaders: {
        'X-Emby-Token': token,
      }));

      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        await native.setProperty('sub-visibility', 'yes');
        await native.setProperty('sid', 'auto');
      }

      if (pos > Duration.zero) {
        await _player.seek(pos);
      }
      if (wasPlaying) {
        await _player.play();
      }

      // Host: 发布播放信息到频道元数据
      if (_isHost && _rtmChannel != null) {
        final rtmService = ref.read(rtmServiceProvider);
        final isPublic = _isPublicUrl(url);
        final writeDiag = await rtmService.publishPlayInfo(
          channelName: _rtmChannel!,
          playUrl: url,
          itemId: targetItemId,
          mediaSourceId: widget.mediaSourceId,
          currentEpisodeIndex: _currentEpisodeIndex,
          token: isPublic ? null : token,
        );
        setState(() {
          _syncMetadataWriteDiag = writeDiag;
        });
        _logSyncEvent('publishPlayInfo: len=${url.length}, public=$isPublic, 写入=$writeDiag');
        print('[Stream] metadata 已更新: isPublic=$isPublic, playUrlLen=${url.length}, writeDiag=$writeDiag');
      }

      return url;
    } catch (e) {
      print('[Player] 加载流失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
      return null;
    }
  }

  /// 检测 URL 是否为公开可访问（不需要认证）
  bool _isPublicUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.startsWith('192.168.')) return false;
      if (host.startsWith('10.')) return false;
      if (host.startsWith('172.')) {
        final secondOctet = int.tryParse(host.split('.')[1]) ?? 0;
        if (secondOctet >= 16 && secondOctet <= 31) return false;
      }
      if (host == 'localhost' || host == '127.0.0.1') return false;
      if (url.contains('x-amz-') || url.contains('Signature=')) return true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _resolveStreamUrl(String url, String token) async {
    print('[Stream] _resolveStreamUrl: 原始URL=${url.substring(0, url.length.clamp(0, 120))}');
    try {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('X-Emby-Token', token);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          request.abort();
          throw Exception('连接超时');
        },
      );

      if (response.statusCode == 302 || response.statusCode == 301) {
        final location = response.headers.value('location');
        if (location != null && location.isNotEmpty) {
          client.close(force: true);
          print('[Stream] 302 重定向到: ${location.substring(0, location.length.clamp(0, 120))}');
          return location;
        }
      }

      client.close(force: true);
      print('[Stream] 无重定向, status=${response.statusCode}, 返回原始URL');
      return url;
    } catch (e) {
      print('[Stream] _resolveStreamUrl 异常: $e, 返回原始URL');
      return url;
    }
  }

  /// 从 metadata 读取播放地址并播放（观众端统一入口）
  void _fetchPlayUrlFromMetadata({double position = 0.0, int retryCount = 0}) async {
    if (_rtmChannel == null || !mounted) return;

    final rtmService = ref.read(rtmServiceProvider);
    final (metadata, readDiag) = await rtmService.getChannelMetadata(_rtmChannel!);
    final playUrl = metadata['playUrl'];
    final epIndexStr = metadata['currentEpisodeIndex'];
    final token = metadata['token'];

    setState(() {
      _syncMetadataPlayUrl = playUrl != null && playUrl.isNotEmpty ? '已获取(${playUrl.length}字符)' : '空';
      _syncMetadataIndex = epIndexStr ?? '-';
      _syncMetadataAllKeys = metadata.keys.isNotEmpty ? metadata.keys.toList().toString() : '无';
      _syncMetadataReadDiag = readDiag;
    });

    print('[Sync] metadata 读取: playUrlLen=${playUrl?.length}, epIndex=$epIndexStr, hasToken=${token != null}, retry=$retryCount');

    // 安全网：playUrl 为空时重试一次
    if ((playUrl == null || playUrl.isEmpty || epIndexStr == null) && retryCount < 1) {
      _logSyncEvent('metadata 未就绪, 500ms后重试');
      print('[Sync] metadata 未就绪，500ms 后重试');
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _fetchPlayUrlFromMetadata(position: position, retryCount: retryCount + 1);
      }
      return;
    }

    if (playUrl == null || playUrl.isEmpty || epIndexStr == null || !mounted) return;

    final epIndex = int.tryParse(epIndexStr);
    if (epIndex == null || epIndex < 0 || epIndex >= _episodeIds.length) return;

    _addBroadcastMessage('同步主持人播放');

    try {
      if (token != null && token.isNotEmpty) {
        await _player.open(Media(playUrl, httpHeaders: {'X-Emby-Token': token}));
      } else {
        await _player.open(Media(playUrl));
      }

      setState(() {
        _currentEpisodeIndex = epIndex;
        _isPlayerReady = true;
      });

      if (position > 0) {
        await _player.seek(Duration(milliseconds: (position * 1000).toInt()));
      }

      await _player.play();
      _autoExpandSeries();
      _logSyncEvent('播放器打开成功');
      print('[Sync] 播放器打开成功');
    } catch (e) {
      _logSyncEvent('播放器打开失败: $e');
      print('[Sync] 播放器打开失败: $e');
      _addBroadcastMessage('同步播放失败: $e');
    }
  }

  void _setupPlayerListeners() {
    _player.stream.playing.listen((_) {
      if (mounted) setState(() {});
    });

    _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });

    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
        _refreshTracks();
      }
    });

    _player.stream.volume.listen((volume) {
      if (mounted) setState(() => _volume = volume);
    });

    _tracksSubscription = _player.stream.tracks.listen((tracks) {
      if (!mounted) return;
      final subs = tracks.subtitle;
      final audios = tracks.audio;
      setState(() {
        _subtitleTracks = subs;
        _audioTracks = audios;
      });
      if (!_subtitleAutoSelected) {
        _subtitleAutoSelected = true;
        _autoSelectDefaultTracks();
      }
    });

    _player.stream.track.listen((_) {
      if (mounted) {
        setState(() {
          _currentSubtitle = _player.state.track.subtitle;
          _currentAudio = _player.state.track.audio;
        });
      }
    });

    // 自动播下一集
    _player.stream.completed.listen((completed) {
      if (!mounted || !completed) return;
      if (!_hasEpisodeList) return;

      final nextIndex = _currentEpisodeIndex + 1;
      if (nextIndex < _episodeIds.length) {
        _switchToEpisode(nextIndex);
        _addBroadcastMessage('自动播放下一集');
      } else {
        _addBroadcastMessage('所有剧集播放完毕');
      }
    });
  }

  void _autoSelectDefaultTracks() {
    _player.setSubtitleTrack(SubtitleTrack.auto());

    if (_embyDefaultAudioIndex != null) {
      final embyIdx = _embyAudioStreams.indexWhere(
        (s) => s.index == _embyDefaultAudioIndex!,
      );
      final real = _realAudioTracks;
      if (embyIdx >= 0 && embyIdx < real.length) {
        _player.setAudioTrack(real[embyIdx]);
      }
    }
  }

  void _refreshTracks() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final subs = _player.state.tracks.subtitle;
      final audios = _player.state.tracks.audio;
      setState(() {
        _subtitleTracks = subs;
        _audioTracks = audios;
        _currentSubtitle = _player.state.track.subtitle;
        _currentAudio = _player.state.track.audio;
      });
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
    print('[Room] ${_isHost ? "主持人" : "观众"} 设置消息监听器, userId=$_myUserId, channel=$_rtmChannel, episodes=${_episodeIds.length}');
    _rtmSubscription = rtmService.messageStream.listen((message) async {
      if (!mounted) return;
      final senderId = message['userId'];
      if (senderId == _myUserId) return;

      final type = message['type'];
      print('[Room] 收到消息 type=$type, sender=$senderId');
      if (type == AppConstants.msgTypeHeartbeat) {
        _handleHeartbeat(message);
      } else if (type == AppConstants.msgTypeRoomInfo) {
        print('[Room] 收到 roomInfo, episodeIds=${message['episodeIds']?.length ?? 0}');
        _logSyncEvent('收到 roomInfo (${message['episodeIds']?.length ?? 0}集)');
        _handleRoomInfo(message);
      } else if (type == AppConstants.msgTypeCommand) {
        final action = message['action'] as String?;
        print('[Room] 收到命令 action=$action');
        if (action == 'join') {
          final name = message['userName'] as String? ?? '观众';
          _addBroadcastMessage('$name 加入了房间');
          _logSyncEvent('$name 加入房间');
          _refreshOnlineCount(rtmService);
          // 主持人发送房间信息（含媒体数据 + 剧集列表）
          if (_isHost) {
            print('[Room] 主持人发送 roomInfo, episodeCount=${_episodeIds.length}');
            await rtmService.sendRoomInfo(
              channelName: _rtmChannel!,
              mediaItemId: widget.itemId,
              mediaSourceId: widget.mediaSourceId,
              mediaItemName: _episodeNames.isNotEmpty
                  ? _episodeNames.first
                  : null,
              seriesName: _seriesName,
              episodeIds: _episodeIds,
              episodeNames: _episodeNames,
              episodeSeasons: _episodeSeasons,
              episodeNumbers: _episodeNumbers,
              episodePosters: _episodePosters,
            );
            // 主持人发送当前播放状态（同步播放进度）
            if (_isPlayerReady && _currentEpisodeIndex >= 0) {
              // 确认 metadata playUrl 已同步后再发 syncPlay
              bool metadataReady = false;
              String joinVerifyDiag = '';
              for (int i = 0; i < 3; i++) {
                final (metadata, diag) = await rtmService.getChannelMetadata(_rtmChannel!);
                joinVerifyDiag = diag;
                if (metadata['playUrl'] != null && metadata['playUrl']!.isNotEmpty) {
                  metadataReady = true;
                  break;
                }
                await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
              }
              final position = _player.state.position.inMilliseconds / 1000.0;
              print('[Room] 主持人发送 syncPlay: episode=$_currentEpisodeIndex, pos=$position, metadataReady=$metadataReady, diag=$joinVerifyDiag');
              await rtmService.sendCommand(
                action: AppConstants.actionSyncPlay,
                episodeIndex: _currentEpisodeIndex,
                itemId: _episodeIds[_currentEpisodeIndex],
                position: position,
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
              mediaItemName: _episodeNames.isNotEmpty
                  ? _episodeNames.first
                  : null,
              seriesName: _seriesName,
              episodeIds: _episodeIds,
              episodeNames: _episodeNames,
              episodeSeasons: _episodeSeasons,
              episodeNumbers: _episodeNumbers,
              episodePosters: _episodePosters,
            );
          }
        } else {
          _handleCommand(message);
        }
      }
    });

    // 2. 监听 Presence 事件（在线人数变化）
    _presenceSubscription = rtmService.presenceStream.listen((event) {
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

    final position = (message['position'] as num).toDouble();
    final playing = message['playing'] as bool;
    final rate = (message['rate'] as num).toDouble();
    final timestamp = message['ts'] as int;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final elapsed = now - timestamp;
    final expectedPos = position + (elapsed * rate);

    final currentPos = _player.state.position.inMilliseconds / 1000.0;
    final diff = (expectedPos - currentPos).abs();

    if (diff < AppConstants.syncThresholdMicro) {
      // 差值 < 0.3s，不做操作
    } else if (diff < AppConstants.syncThresholdMedium) {
      _player.setRate(1.02);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _player.setRate(rate);
      });
    } else {
      _player.seek(Duration(milliseconds: (expectedPos * 1000).toInt()));
    }

    if (playing && !_player.state.playing) {
      _player.play();
    } else if (!playing && _player.state.playing) {
      _player.pause();
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
        _player.play();
        break;
      case AppConstants.actionPause:
        _player.pause();
        break;
      case AppConstants.actionSeek:
        final pos = (message['position'] as num).toDouble();
        _player.seek(Duration(milliseconds: (pos * 1000).toInt()));
        break;
      case AppConstants.actionRate:
        final r = (message['rate'] as num).toDouble();
        _player.setRate(r);
        break;
      case AppConstants.actionSwitchEpisode:
        final epIndex = message['episodeIndex'] as int?;
        if (epIndex != null) {
          _syncSwitchToEpisode(epIndex);
        }
        break;
      case AppConstants.actionSyncPlay:
        final position = (message['position'] as num?)?.toDouble() ?? 0.0;
        _logSyncEvent('收到 syncPlay, pos=${position.toStringAsFixed(1)}s');
        // 从 metadata 读取播放地址
        _fetchPlayUrlFromMetadata(position: position);
        break;
      case AppConstants.actionRemoveEpisode:
        final epIndex = message['episodeIndex'] as int?;
        if (epIndex != null) {
          _removeEpisodeLocal(epIndex);
        }
        break;
    }
  }

  void _handleRoomInfo(Map<String, dynamic> message) {
    if (_isHost) return;
    if (_hasEpisodeList) return;

    print('[Room] _handleRoomInfo: keys=${message.keys.toList()}');
    final epIds = message['episodeIds'];
    print('[Room] _handleRoomInfo: epIds type=${epIds.runtimeType}, len=${epIds is List ? epIds.length : "N/A"}');
    if (epIds is List && epIds.isNotEmpty) {
      // 电视剧：接收完整剧集列表
      setState(() {
        _episodeIds = List<String>.from(epIds);
        _episodeNames = List<String>.from(message['episodeNames'] ?? []);
        _episodeSeasons = List<int>.from(message['episodeSeasons'] ?? []);
        _episodeNumbers = List<int>.from(message['episodeNumbers'] ?? []);
        _episodePosters = List<String>.from(message['episodePosters'] ?? []);
        _seriesName = message['seriesName'] ?? '';
        _hasEpisodeList = true;
      });
    } else {
      // 电影：用 mediaItemId 构建单集
      final mediaItemId = message['mediaItemId'] as String?;
      final mediaItemName = message['mediaItemName'] as String?;
      if (mediaItemId != null && mediaItemId.isNotEmpty) {
        setState(() {
          _episodeIds = [mediaItemId];
          _episodeNames = [mediaItemName ?? '电影'];
          _episodeSeasons = [0];
          _episodeNumbers = [0];
          _episodePosters = [''];
          _seriesName = '';
          _hasEpisodeList = true;
        });
      }
    }

    if (_hasEpisodeList) {
      _addBroadcastMessage('已同步房间资源列表');
      // 从 metadata 读取播放地址并播放
      _fetchPlayUrlFromMetadata();
    }
  }

  void _addBroadcastMessage(String msg) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    setState(() => _broadcastMessages.add('[$time] $msg'));
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

  bool get _isSeries => _seriesName.isNotEmpty && _episodeIds.length > 1;

  void _autoExpandSeries() {
    if (_isSeries && _seriesCollapsed) {
      setState(() => _seriesCollapsed = false);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.rtmHeartbeatIntervalMs),
      (_) {
        if (!mounted || !_player.state.playing) return;
        final rtmService = ref.read(rtmServiceProvider);
        rtmService.sendHeartbeat(
          position: _player.state.position.inMilliseconds / 1000.0,
          playing: _player.state.playing,
          rate: _player.state.rate,
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
    if (_player.state.playing) {
      _player.pause();
      if (widget.roomCode != null) {
        _sendCommand(AppConstants.actionPause);
      }
    } else {
      _player.play();
      if (widget.roomCode != null) {
        _sendCommand(AppConstants.actionPlay);
      }
    }
  }

  void _toggleOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  static const _videoFitModes = [
    BoxFit.contain,
    BoxFit.cover,
    BoxFit.fill,
    BoxFit.none,
  ];
  static const _videoFitIcons = [
    Icons.fit_screen,
    Icons.fullscreen,
    Icons.zoom_out_map,
    Icons.aspect_ratio,
  ];
  static const _videoFitLabels = ['自适应', '裁剪', '铺满', '原始'];

  void _cycleVideoFit() {
    final nextIndex =
        (_videoFitModes.indexOf(_videoFit) + 1) % _videoFitModes.length;
    setState(() => _videoFit = _videoFitModes[nextIndex]);
  }

  void _onSeek(double value) {
    _player.seek(Duration(milliseconds: value.toInt()));
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
        if (mounted && _player.state.playing) {
          setState(() {
            _showControls = false;
            _showVolumeSlider = false;
            _showSubtitleMenu = false;
            _showAudioMenu = false;
          });
        }
      });
    }
  }

  void _closeAllMenus() {
    setState(() {
      _showVolumeSlider = false;
      _showSubtitleMenu = false;
      _showAudioMenu = false;
    });
  }

  // 切集（房主操作 + 发送RTM命令）
  void _switchToEpisode(int index) async {
    if (index < 0 || index >= _episodeIds.length) return;
    if (index == _currentEpisodeIndex && _isPlayerReady) return;

    await _loadEpisodeStream(index);

    // Host: 确认 metadata playUrl 已同步后，再发送 syncPlay 命令
    if (_isHost && _rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);

      // 等待 metadata 中 playUrl 就绪（最多重试 3 次，间隔递增）
      bool metadataReady = false;
      String switchVerifyDiag = '';
      for (int i = 0; i < 3; i++) {
        final (metadata, diag) = await rtmService.getChannelMetadata(_rtmChannel!);
        switchVerifyDiag = diag;
        final playUrl = metadata['playUrl'];
        if (playUrl != null && playUrl.isNotEmpty) {
          metadataReady = true;
          _logSyncEvent('metadata playUrl 已就绪 (第${i + 1}次)');
          print('[Sync] metadata playUrl 已就绪 (attempt ${i + 1})');
          break;
        }
        print('[Sync] metadata playUrl 未就绪，等待 ${300 * (i + 1)}ms (attempt ${i + 1}/3)');
        await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
      }

      setState(() {
        _syncMetadataReadDiag = switchVerifyDiag;
      });

      if (!metadataReady) {
        _logSyncEvent('警告: metadata playUrl 为空');
        print('[Sync] 警告：metadata playUrl 仍为空，继续发送 syncPlay');
      }

      final position = _player.state.position.inMilliseconds / 1000.0;
      _logSyncEvent('发送 syncPlay: ep=$index, pos=${position.toStringAsFixed(1)}s');
      print('[Sync] 主持人 sendCommand syncPlay: episode=$index, pos=$position');
      await rtmService.sendCommand(
        action: AppConstants.actionSyncPlay,
        episodeIndex: index,
        itemId: _episodeIds[index],
        position: position,
      );
    }
  }

  // 观众同步切集：从 metadata 读取播放地址
  void _syncSwitchToEpisode(int epIndex) async {
    if (epIndex < 0 || epIndex >= _episodeIds.length) return;

    _addBroadcastMessage('同步切集: ${_episodeNames[epIndex]}');
    setState(() {
      _currentEpisodeIndex = epIndex;
    });

    // 从 metadata 读取播放地址
    _fetchPlayUrlFromMetadata();
  }

  // 删除剧集（房主）
  void _removeEpisode(int index) async {
    if (index < 0 || index >= _episodeIds.length) return;
    if (!_isHost) return;

    final removedName = _episodeNames[index];

    _episodeIds.removeAt(index);
    _episodeNames.removeAt(index);
    _episodeSeasons.removeAt(index);
    _episodeNumbers.removeAt(index);
    _episodePosters.removeAt(index);

    if (_currentEpisodeIndex == index) {
      _currentEpisodeIndex = -1;
      _isPlayerReady = false;
      _player.stop();
    } else if (_currentEpisodeIndex > index) {
      _currentEpisodeIndex--;
    }

    _hasEpisodeList = _episodeIds.isNotEmpty;
    _addBroadcastMessage('已移除: $removedName');
    setState(() {});

    // 发送删除命令
    if (_rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);
      await rtmService.sendCommand(
        action: AppConstants.actionRemoveEpisode,
        episodeIndex: index,
      );
    }
  }

  // 删除剧集（观众端，仅修改本地列表）
  void _removeEpisodeLocal(int index) {
    if (index < 0 || index >= _episodeIds.length) return;

    _episodeIds.removeAt(index);
    _episodeNames.removeAt(index);
    _episodeSeasons.removeAt(index);
    _episodeNumbers.removeAt(index);
    _episodePosters.removeAt(index);

    if (_currentEpisodeIndex == index) {
      _currentEpisodeIndex = -1;
      _isPlayerReady = false;
      _player.stop();
    } else if (_currentEpisodeIndex > index) {
      _currentEpisodeIndex--;
    }

    _hasEpisodeList = _episodeIds.isNotEmpty;
    setState(() {});
  }

  // 复制房间码
  void _copyRoomCode() {
    if (widget.roomCode == null) return;
    Clipboard.setData(ClipboardData(text: widget.roomCode!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制房间码')),
    );
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rtmSubscription?.cancel();
    _presenceSubscription?.cancel();
    _tracksSubscription?.cancel();
    _broadcastScrollController.dispose();

    // 清理 RTM
    if (widget.roomCode != null) {
      try {
        final rtmService = ref.read(rtmServiceProvider);
        rtmService.sendJoinLeave(
          action: 'leave',
          userName: _audienceName ?? '观众',
        );
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

    _player.dispose();
    super.dispose();
  }

  bool get _canControlPlayback {
    if (widget.roomCode == null) return true;
    return _isHost;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_showVolumeSlider || _showSubtitleMenu || _showAudioMenu) {
            _closeAllMenus();
          } else {
            _toggleControls();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: _buildResponsiveLayout(),
      ),
    );
  }

  Widget _buildResponsiveLayout() {
    final isPortrait = MediaQuery.of(context).orientation ==
            Orientation.portrait &&
        (Platform.isAndroid || Platform.isIOS);

    final showPanel = widget.roomCode != null;

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
        if (_isPlayerReady || !_hasEpisodeList)
          Center(
            child: Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: _videoFit,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 50),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      blurRadius: 6,
                      color: Colors.black87,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              ),
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

        // Controls（底部渐变浮层，仅视频区域底部）
        if (_showControls && (_isPlayerReady || !_hasEpisodeList))
          Positioned(bottom: 0, left: 0, right: 0, child: _buildControls()),

        // 加载指示器
        if (_duration.inMilliseconds == 0 && _isPlayerReady)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          ),

        // 同步调试面板
        if (_showSyncDebug)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildSyncDebugPanel(),
          ),
      ],
    );
  }

  Widget _buildSyncDebugPanel() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, color: Colors.green, size: 16),
              const SizedBox(width: 6),
              const Text('同步调试', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showSyncDebug = false),
                child: const Icon(Icons.close, color: Colors.white54, size: 16),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 8),
          _debugRow('角色', _isHost ? '主持人' : '观众'),
          _debugRow('RTM频道', _syncRtmChannel),
          _debugRow('RTM状态', _syncRtmStatus),
          _debugRow('metadata playUrl', _syncMetadataPlayUrl),
          _debugRow('metadata epIndex', _syncMetadataIndex),
          _debugRow('metadata 所有key', _syncMetadataAllKeys),
          _debugRow('metadata 写入诊断', _syncMetadataWriteDiag),
          _debugRow('metadata 读取诊断', _syncMetadataReadDiag),
          _debugRow('metadata 自检', _syncMetadataTestResult),
          if (_syncEvents.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 8),
            const Text('最近事件:', style: TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            ...(_syncEvents.length > 8 ? _syncEvents.sublist(_syncEvents.length - 8) : _syncEvents).map((e) => Text(
              e,
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
            )),
          ],
        ],
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
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
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          if (widget.roomCode != null)
            IconButton(
              icon: Icon(_showSyncDebug ? Icons.sync : Icons.sync_disabled, color: _showSyncDebug ? Colors.green : Colors.white54),
              tooltip: '同步调试',
              onPressed: () => setState(() => _showSyncDebug = !_showSyncDebug),
            ),
          if (widget.roomCode != null)
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.white),
              tooltip: '复制房间码',
              onPressed: _copyRoomCode,
            ),
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
              child: Slider(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds
                        .toDouble()
                        .clamp(0, _duration.inMilliseconds.toDouble())
                    : 0,
                max: _duration.inMilliseconds > 0
                    ? _duration.inMilliseconds.toDouble()
                    : 1,
                onChanged: _canControlPlayback ? _onSeek : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            if (_showSubtitleMenu) ...[
              _buildExpandablePanel(
                maxHeight: 180,
                child: _buildSubtitleListContent(),
              ),
              const SizedBox(height: 8),
            ],
            if (_showAudioMenu) ...[
              _buildExpandablePanel(
                maxHeight: 180,
                child: _buildAudioTrackListContent(),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                // 上一集
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _episodeIds.length > 1)
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
                    _episodeIds.length > 1)
                  const SizedBox(width: 8),

                // 播放/暂停
                if (_canControlPlayback)
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Icon(
                      _player.state.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                if (_canControlPlayback) const SizedBox(width: 8),

                // 下一集
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _episodeIds.length > 1)
                  GestureDetector(
                    onTap: _currentEpisodeIndex < _episodeIds.length - 1
                        ? () =>
                            _switchToEpisode(_currentEpisodeIndex + 1)
                        : null,
                    child: Icon(
                      Icons.skip_next,
                      color: _currentEpisodeIndex < _episodeIds.length - 1
                          ? Colors.white
                          : Colors.white24,
                      size: 28,
                    ),
                  ),
                if (_canControlPlayback &&
                    _hasEpisodeList &&
                    _episodeIds.length > 1)
                  const SizedBox(width: 8),

                // 音量
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showVolumeSlider = !_showVolumeSlider;
                      _showSubtitleMenu = false;
                      _showAudioMenu = false;
                    });
                  },
                  onLongPress: () {
                    final newVol = _volume > 0 ? 0.0 : 100.0;
                    _player.setVolume(newVol);
                    setState(() => _volume = newVol);
                  },
                  child:
                      Icon(_volumeIcon, color: Colors.white, size: 24),
                ),
                if (_showVolumeSlider) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: const Color(0xFF6366F1),
                        inactiveTrackColor: Colors.white24,
                        thumbColor: const Color(0xFF6366F1),
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7),
                        trackHeight: 2,
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _volume.clamp(0, 100),
                        min: 0,
                        max: 100,
                        onChanged: (v) {
                          _player.setVolume(v);
                          setState(() => _volume = v);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${_volume.round()}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],

                const Spacer(),

                // 字幕
                _buildControlButton(
                  icon: Icons.subtitles,
                  onTap: () {
                    setState(() {
                      _showSubtitleMenu = !_showSubtitleMenu;
                      _showVolumeSlider = false;
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
                      _showVolumeSlider = false;
                      _showSubtitleMenu = false;
                    });
                  },
                  badge: _embyAudioStreams.isNotEmpty
                      ? '${_embyAudioStreams.length}'
                      : null,
                ),

                // 横竖屏 + 画面比例
                if (Platform.isAndroid || Platform.isIOS) ...[
                  const SizedBox(width: 20),
                  _buildControlButton(
                    icon: _isLandscape
                        ? Icons.screen_lock_portrait
                        : Icons.screen_lock_landscape,
                    onTap: _toggleOrientation,
                  ),
                  const SizedBox(width: 20),
                  _buildControlButton(
                    icon: _videoFitIcons[
                        _videoFitModes.indexOf(_videoFit)],
                    onTap: _cycleVideoFit,
                    badge: _videoFitLabels[
                        _videoFitModes.indexOf(_videoFit)],
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
                Expanded(
                  child: Text(
                    _seriesName.isNotEmpty ? _seriesName : '资源',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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

          // 剧集列表
          Expanded(
            child: _episodeIds.isEmpty
                ? const Center(
                    child: Text('暂无资源',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 13)),
                  )
                : _isSeries
                    ? _buildSeriesCollapseList()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _episodeIds.length,
                        itemBuilder: (ctx, i) =>
                            _buildEpisodeListItem(i),
                      ),
          ),

          // 播报板（底部）
          if (_roomData != null) _buildBroadcastBoardInPanel(),
        ],
      ),
    );
  }

  Widget _buildSeriesCollapseList() {
    return Column(
      children: [
        // 折叠标题栏
        InkWell(
          onTap: () => setState(() => _seriesCollapsed = !_seriesCollapsed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16213E),
            child: Row(
              children: [
                Icon(
                  _seriesCollapsed ? Icons.chevron_right : Icons.expand_more,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _seriesName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '(${_episodeIds.length}集)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // 展开时显示集列表
        if (!_seriesCollapsed)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _episodeIds.length,
              itemBuilder: (ctx, i) => _buildEpisodeListItem(i),
            ),
          ),
      ],
    );
  }

  Widget _buildEpisodeListItem(int index) {
    final isPlaying = index == _currentEpisodeIndex;
    final season =
        _episodeSeasons.length > index ? _episodeSeasons[index] : 0;
    final number =
        _episodeNumbers.length > index ? _episodeNumbers[index] : 0;
    final name =
        _episodeNames.length > index ? _episodeNames[index] : '';
    final poster =
        _episodePosters.length > index ? _episodePosters[index] : null;

    // 电影：season==0 && number==0 时为电影，不显示 S00E00
    final isMovie = season == 0 && number == 0 && _seriesName.isEmpty;

    return InkWell(
      onTap: () {
        if (!_isHost) return;
        if (isPlaying) {
          _togglePlayPause();
        } else {
          _switchToEpisode(index);
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
                    _switchToEpisode(index);
                  }
                },
                child: Icon(
                  isPlaying && _player.state.playing
                      ? Icons.pause_circle
                      : Icons.play_circle,
                  color: isPlaying
                      ? const Color(0xFF6366F1)
                      : Colors.white54,
                  size: 22,
                ),
              ),
            if (_isHost) const SizedBox(width: 8),

            // 缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 56,
                height: 36,
                child: poster != null && poster.isNotEmpty
                    ? EmbyImage(url: poster, fit: BoxFit.cover)
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
                      name,
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
                          'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}',
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
                          name,
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
                onTap: () => _removeEpisode(index),
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
      child: Column(
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
      ),
    );
  }

  // ========== 字幕/音轨选择 ==========
  Widget _buildSubtitleListContent() {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        _buildMenuItem(
          label: '关闭字幕',
          isSelected:
              _currentSubtitle?.id == 'no' && !_useServerSubtitleBurnIn,
          onTap: () {
            if (_useServerSubtitleBurnIn) {
              _useServerSubtitleBurnIn = false;
              _activeSubtitleIndex = null;
              _loadStream(itemId: _episodeIds.isNotEmpty
                  ? _episodeIds[_currentEpisodeIndex]
                  : widget.itemId);
            } else {
              _player.setSubtitleTrack(SubtitleTrack.no());
            }
            setState(() => _showSubtitleMenu = false);
          },
        ),
        for (int i = 0; i < _embySubtitleStreams.length; i++)
          _buildMenuItem(
            label: _embySubtitleStreams[i].displayInfo,
            isSelected: _isEmbySubtitleSelected(i),
            onTap: () {
              _selectEmbySubtitle(i);
              setState(() => _showSubtitleMenu = false);
            },
          ),
        if (_embySubtitleStreams.isEmpty && _subtitleTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '当前视频无字幕轨道',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioTrackListContent() {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (int i = 0; i < _embyAudioStreams.length; i++)
          _buildMenuItem(
            label: _embyAudioStreams[i].displayInfo,
            isSelected: _isEmbyAudioSelected(i),
            onTap: () {
              _selectEmbyAudio(i);
              setState(() => _showAudioMenu = false);
            },
          ),
        if (_embyAudioStreams.isEmpty && _audioTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '当前视频无音轨选项',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
      ],
    );
  }

  List<SubtitleTrack> get _realSubtitleTracks => _subtitleTracks
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  List<AudioTrack> get _realAudioTracks => _audioTracks
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  bool _isEmbySubtitleSelected(int embyIndex) {
    final stream = _embySubtitleStreams[embyIndex];
    if (_useServerSubtitleBurnIn) {
      return _activeSubtitleIndex == stream.index;
    }
    if (_currentSubtitle == null || _currentSubtitle!.id == 'no') {
      return false;
    }
    final real = _realSubtitleTracks;
    if (embyIndex >= real.length) return false;
    return _currentSubtitle?.id == real[embyIndex].id;
  }

  bool _isEmbyAudioSelected(int embyIndex) {
    if (_currentAudio == null) return false;
    final real = _realAudioTracks;
    if (embyIndex >= real.length) return false;
    return _currentAudio?.id == real[embyIndex].id;
  }

  void _selectEmbySubtitle(int embyIndex) {
    final stream = _embySubtitleStreams[embyIndex];
    final isExternal = stream.isExternal ||
        stream.subtitleLocationType == 'ExternalStream';

    if (isExternal) {
      _useServerSubtitleBurnIn = true;
      _activeSubtitleIndex = stream.index;
      _loadStream(
        itemId: _episodeIds.isNotEmpty
            ? _episodeIds[_currentEpisodeIndex]
            : widget.itemId,
        subtitleStreamIndex: stream.index,
      );
      return;
    }

    _useServerSubtitleBurnIn = false;
    _activeSubtitleIndex = stream.index;
    final real = _realSubtitleTracks;
    if (embyIndex < real.length) {
      _player.setSubtitleTrack(real[embyIndex]);
    }
  }

  void _selectEmbyAudio(int embyIndex) {
    final real = _realAudioTracks;
    if (embyIndex < real.length) {
      _player.setAudioTrack(real[embyIndex]);
    }
  }

  Widget _buildMenuItem({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check,
                  size: 16, color: Color(0xFF6366F1))
            else
              const SizedBox(width: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF6366F1)
                      : Colors.white,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _volumeIcon => _volume == 0
      ? Icons.volume_off
      : _volume < 50
          ? Icons.volume_down
          : Icons.volume_up;

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