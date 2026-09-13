import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

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
  String? _hostUserId;

  double _volume = 50;
  double _brightness = 0.5;
  bool _syncPaused = false;
  bool _isSyncing = false;
  int _playRequestId = 0;
  DateTime? _lastSeekTime;
  bool _showPanel = true;
  String _currentPlayUrl = '';
  String _currentToken = '';
  Timer? _hideControlsTimer;

  bool _showSubtitleMenu = false;
  bool _showAudioMenu = false;
  bool _showDecodeModeMenu = false;

  // 手势控制
  bool _showGestureOverlay = false;
  String _gestureHintText = '';
  Timer? _gestureHintTimer;
  IconData? _gestureOverlayIcon;
  bool _isLeftSide = false;
  bool _showBrightnessBar = false;
  bool _showVolumeBar = false;
  Timer? _gestureBarTimer;

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

  // 房间解散检测
  bool _hasReceivedRoomInfo = false;
  Timer? _roomInfoTimeout;

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
  String _voStatus = '-'; // 视频输出驱动
  DeviceCodecInfo? _deviceCodecInfo; // 设备硬解码能力
  String _videoCodec = '-'; // 视频编码格式
  String _videoResolution = '-'; // 视频分辨率
  String _actualDecoderFull = ''; // 实际解码器完整描述
  StreamSubscription? _logSubscription; // mpv 日志订阅
  StreamSubscription? _videoParamsSubscription; // 视频参数订阅
  List<String> _syncEvents = [];
  final GlobalKey _qrKey = GlobalKey();

  void _logSyncEvent(String event) {
    final now = DateTime.now();
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _syncEvents.add('[$time] $event');
      if (_syncEvents.length > 15) _syncEvents.removeAt(0);
    });
  }

  Future<void> _queryHwdecStatus() async {
    if (_player.platform is! NativePlayer) return;
    try {
      final native = _player.platform as NativePlayer;
      // 优先使用 hwPixelformat（比 hwdec-current 可靠，Android 上 hwdec-current 有已知 bug）
      final hwPF = await native.getProperty('video-params/hw-pixelformat');
      final hwdec = await native.getProperty('hwdec-current');
      final vo = await native.getProperty('vo');
      final codec = await native.getProperty('video-codec');
      if (mounted) {
        setState(() {
          _voStatus = vo.isEmpty ? '-' : vo;
          if (codec.isNotEmpty) _videoCodec = codec;
          // hwPixelformat 非空 = 硬解码生效
          if (hwPF.isNotEmpty) {
            _actualDecoderFull = '$hwPF ✅';
          } else if (hwdec.isNotEmpty) {
            _actualDecoderFull = hwdec;
          } else {
            _actualDecoderFull = 'no (软解码)';
          }
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _player = Player(
      configuration: PlayerConfiguration(
        libass: true,
        bufferSize: settings.bufferSizeMB * 1024 * 1024,
      ),
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

    _setupPlayerListeners();

    if (widget.roomCode != null) {
      _setupRoomSync();
    }

    // 先完成硬件解码设置，再启动播放，避免竞态
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initPlayerProperties();
      if (_isHost && _hasEpisodeList && _episodeIds.isNotEmpty && widget.roomCode == null) {
        final targetIndex = _episodeIds.indexOf(widget.itemId);
        _loadEpisodeStream(targetIndex >= 0 ? targetIndex : 0);
      }
    });
  }

  Future<void> _initPlayerProperties() async {
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      final settings = ref.read(settingsProvider);

      // Phase 1: 查询设备硬解能力
      final handle = await _player.handle;
      _deviceCodecInfo = await DecodeModeService.queryDeviceCapabilities(handle);

      // Phase 2: 决定 hwdec 值并设置
      final hwdecValue = DecodeModeService.resolveHwdec(
          settings.decodeMode, _deviceCodecInfo);
      await native.setProperty('hwdec', hwdecValue);

      // Phase 3: 设置 fallback 策略 — HW/HW+ 锁死不回退
      final fallbackValue = DecodeModeService.resolveFallback(settings.decodeMode);
      await native.setProperty('vd-lavc-software-fallback', fallbackValue);  // Android mpv 0.36 只认识旧名

      // Phase 3: 监听 mpv 日志 — 实时检测解码状态
      _logSubscription?.cancel();
      _logSubscription = _player.stream.log.listen((log) {
        final status = DecodeModeService.parseLogMessage(log.text);
        // 从日志提取实际解码器
        final decoder = DecodeModeService.parseActualDecoder(log.text);
        if (decoder != null && mounted) {
          setState(() {
            _actualDecoderFull = _formatActualDecoder(decoder, status);
          });
        }
      });

      // Phase 3b: 监听视频参数 — 获取分辨率
      _videoParamsSubscription?.cancel();
      _videoParamsSubscription = _player.stream.videoParams.listen((params) {
        if (mounted && params.w != null && params.h != null) {
          setState(() => _videoResolution = '${params.w}x${params.h}');
        }
      });

      // 字幕
      await native.setProperty('sub-visibility', 'yes');
      await native.setProperty('sub-auto', 'fuzzy');
      await native.setProperty('sub-font-size', '40');
      await native.setProperty('sub-border-size', '2');
      await native.setProperty('sub-shadow-offset', '1');
      await native.setProperty('sub-margin-y', '22');

      // 音量默认 50%
      await native.setProperty('volume', '50');
    }
  }

  String _formatActualDecoder(String decoder, DecodeStatus status) {
    if (decoder == 'no') return 'no (软解码) ❌';
    if (status == DecodeStatus.hwActive) return '$decoder ✅';
    if (status == DecodeStatus.hwFailed) return '$decoder ❌ 已回退';
    return '$decoder';
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

      // 预解析重定向（libmpv 不能可靠跟随 HTTP→HTTPS 跨协议重定向）
      final url = await _resolveStreamUrl(streamUrl, token);

      _currentPlayUrl = streamUrl;
      _currentToken = token;

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
      Future.delayed(const Duration(seconds: 2), _queryHwdecStatus);

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

      // 观众自行解析重定向
      final resolvedUrl = await _resolveStreamUrl(playUrl, token);
      print('[Sync] URL解析完成: ${playUrl.length}字符 → ${resolvedUrl.length}字符');

      // 解析完成，检查是否已被更新的请求抢占
      if (requestId != _playRequestId || !mounted) return;

      if (token.isNotEmpty) {
        await _player.open(Media(resolvedUrl, httpHeaders: {'X-Emby-Token': token}));
      } else {
        await _player.open(Media(resolvedUrl));
      }

      // 等待缓冲完成再 seek
      await for (final buffering in _player.stream.buffering) {
        if (!buffering || !mounted) break;
      }

      // 缓冲完成，再次检查是否已被抢占
      if (requestId != _playRequestId || !mounted) return;

      setState(() {
        if (epIndex != null) _currentEpisodeIndex = epIndex;
        _isPlayerReady = true;
      });

      if (position > 0) {
        await _player.seek(Duration(milliseconds: (position * 1000).toInt()));
      }

      await _player.play();
      _autoExpandSeries();
      _logSyncEvent('播放器打开成功');
      Future.delayed(const Duration(seconds: 2), _queryHwdecStatus);
      print('[Sync] 播放器打开成功');
    } catch (e) {
      _logSyncEvent('播放器打开失败: $e');
      print('[Sync] 播放器打开失败: $e');
      _addBroadcastMessage('同步播放失败: $e');
    } finally {
      if (requestId == _playRequestId) _isSyncing = false;
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
          // 主持人发送房间信息（含媒体数据 + 剧集列表 + playUrl）
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
              playUrl: _currentPlayUrl,
              token: _currentToken,
              subtitleStreams: _embySubtitleStreams.map((s) => s.toJson()).toList(),
              audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
              defaultAudioStreamIndex: _embyDefaultAudioIndex,
            );
            // 主持人发送当前播放状态（同步播放进度）
            if (_isPlayerReady && _currentEpisodeIndex >= 0) {
              final position = _player.state.position.inMilliseconds / 1000.0;
              print('[Room] 主持人发送 syncPlay: episode=$_currentEpisodeIndex, pos=$position');
              await rtmService.sendCommand(
                action: AppConstants.actionSyncPlay,
                episodeIndex: _currentEpisodeIndex,
                itemId: _episodeIds[_currentEpisodeIndex],
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
              mediaItemName: _episodeNames.isNotEmpty
                  ? _episodeNames.first
                  : null,
              seriesName: _seriesName,
              episodeIds: _episodeIds,
              episodeNames: _episodeNames,
              episodeSeasons: _episodeSeasons,
              episodeNumbers: _episodeNumbers,
              episodePosters: _episodePosters,
              playUrl: _currentPlayUrl,
              token: _currentToken,
              subtitleStreams: _embySubtitleStreams.map((s) => s.toJson()).toList(),
              audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
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
    if (_player.state.buffering) return;

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
      // seek 防抖：距上次 seek 不足 2 秒则跳过
      if (_lastSeekTime != null &&
          DateTime.now().difference(_lastSeekTime!).inMilliseconds < 2000) {
        return;
      }
      _lastSeekTime = DateTime.now();
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
          _removeEpisodeLocal(epIndex);
        }
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
      _embyDefaultAudioIndex = message['defaultAudioStreamIndex'] as int?;
      print('[Room] 字幕=${_embySubtitleStreams.length}条, 音轨=${_embyAudioStreams.length}条');

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
    _player.stop();
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
            _showSubtitleMenu = false;
            _showAudioMenu = false;
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
      _showBrightnessBar = false;
      _showVolumeBar = false;
    });
  }

  // 切集（房主操作 + 发送RTM命令）
  void _switchToEpisode(int index) async {
    if (index < 0 || index >= _episodeIds.length) return;
    if (index == _currentEpisodeIndex && _isPlayerReady) return;

    await _loadEpisodeStream(index);

    // Host: 发送 syncPlay 命令（含 playUrl + token）
    if (_isHost && _rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);
      final position = _player.state.position.inMilliseconds / 1000.0;
      _logSyncEvent('发送 syncPlay: ep=$index, pos=${position.toStringAsFixed(1)}s');
      print('[Sync] 主持人 sendCommand syncPlay: episode=$index, pos=$position, urlLen=${_currentPlayUrl.length}');
      await rtmService.sendCommand(
        action: AppConstants.actionSyncPlay,
        episodeIndex: index,
        itemId: _episodeIds[index],
        position: position,
        playUrl: _currentPlayUrl,
        token: _currentToken,
      );
    }
  }

  // 观众同步切集：接收 syncPlay 命令后自动播放（playUrl 已在 syncPlay 消息中）
  void _syncSwitchToEpisode(int epIndex) async {
    if (epIndex < 0 || epIndex >= _episodeIds.length) return;

    _addBroadcastMessage('同步切集: ${_episodeNames[epIndex]}');
    setState(() {
      _currentEpisodeIndex = epIndex;
    });
    // syncPlay 消息会紧随其后到达，直接处理
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
    _hideControlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _roomInfoTimeout?.cancel();
    _rtmSubscription?.cancel();
    _presenceSubscription?.cancel();
    _tracksSubscription?.cancel();
    _logSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    _broadcastScrollController.dispose();

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

    _player.dispose();
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
            if (_showSubtitleMenu || _showAudioMenu || _showDecodeModeMenu || _showBrightnessBar || _showVolumeBar) {
              _closeAllMenus();
            } else {
              _toggleControls();
            }
          },
          onDoubleTap: _onDoubleTap,
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

        // 解码模式选择面板
        if (_showDecodeModeMenu)
          Positioned(
            top: MediaQuery.of(context).padding.top + 48,
            right: 12,
            child: _buildDecodeModePanel(),
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
        if (_showBrightnessBar) _buildBrightnessBar(),

        // 音量柱式进度条（左侧）
        if (_showVolumeBar) _buildVolumeBar(),

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
          const Divider(color: Colors.white24, height: 8),
          _debugRow('设备能力', _buildDeviceCapabilityText()),
          _debugRow('视频信息', _videoCodec != '-' ? '$_videoCodec, $_videoResolution' : _videoResolution),
          _debugRow('视频输出 vo', _voStatus),
          _debugRow('解码模式', AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ?? '-'),
          _debugRow('实际解码', _actualDecoderFull.isNotEmpty ? _actualDecoderFull : '检测中...'),
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

  String _buildDeviceCapabilityText() {
    if (_deviceCodecInfo == null) return '检测中...';
    final info = _deviceCodecInfo!;
    if (info.isUnknown) return '检测失败 (不影响播放)';
    if (!info.hasAnyHw) return '无硬解码器';
    return 'H264${info.hasH264Hw ? "✅" : "❌"} '
        'H265${info.hasHevcHw ? "✅" : "❌"} '
        'VP9${info.hasVp9Hw ? "✅" : "❌"} '
        'AV1${info.hasAv1Hw ? "✅" : "❌"}';
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
            onTap: () => setState(() => _showDecodeModeMenu = !_showDecodeModeMenu),
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
                    AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ?? 'Auto',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (widget.roomCode != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(_showSyncDebug ? Icons.sync : Icons.sync_disabled, color: _showSyncDebug ? Colors.green : Colors.white54),
              tooltip: '同步调试',
              onPressed: () => setState(() => _showSyncDebug = !_showSyncDebug),
            ),
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

  // ========== 解码模式选择面板 ==========
  Widget _buildDecodeModePanel() {
    final currentMode = ref.watch(settingsProvider).decodeMode;
    final modes = ['auto', 'hw+', 'hw', 'sw'];
    final labels = {'auto': 'Auto', 'hw+': 'HW+', 'hw': 'HW', 'sw': 'SW'};
    final descriptions = {
      'auto': '智能选择',
      'hw+': '硬解+回拷',
      'hw': '纯硬解',
      'sw': '纯软解',
    };

    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: modes.map((mode) {
            final isSelected = mode == currentMode;
            return InkWell(
              onTap: () => _switchDecodeMode(mode),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                      : null,
                  border: const Border(
                    bottom: BorderSide(color: Colors.white12, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected ? const Color(0xFF6366F1) : Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels[mode]!,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          Text(
                            descriptions[mode]!,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _switchDecodeMode(String mode) async {
    await ref.read(settingsProvider.notifier).update(decodeMode: mode);

    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;

      // 记住当前状态
      final currentPos = _player.state.position;
      final wasPlaying = _player.state.playing;

      // 设置新 hwdec 属性
      final hwdecValue =
          DecodeModeService.resolveHwdec(mode, _deviceCodecInfo);
      await native.setProperty('hwdec', hwdecValue);

      final fallbackValue = DecodeModeService.resolveFallback(mode);
      await native.setProperty('vd-lavc-software-fallback', fallbackValue);

      // 用 loadfile replace 直接替换当前流（比 open() 更快）
      if (_currentPlayUrl.isNotEmpty) {
        await native.command(['loadfile', _currentPlayUrl, 'replace']);

        // 立即 seek 到原位置
        if (currentPos > Duration.zero) {
          await _player.seek(currentPos);
        }

        // 恢复播放状态
        if (!wasPlaying) {
          await _player.pause();
        }
      }
    }

    setState(() => _showDecodeModeMenu = false);
  }

  // ========== 手势控制 ==========
  void _onDoubleTap() {
    _togglePlayPause();
    _showGestureIcon(_player.state.playing ? Icons.play_arrow : Icons.pause);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final delta = details.primaryVelocity ?? 0;
    final seekDelta = (delta / 100 * 5000).round();
    _seekRelative(seekDelta);
  }

  void _seekRelative(int deltaMs) {
    final currentMs = _position.inMilliseconds;
    final targetMs = (currentMs + deltaMs).clamp(0, _duration.inMilliseconds);
    _player.seek(Duration(milliseconds: targetMs));

    final seconds = (deltaMs / 1000).round();
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
      setState(() {
        _showBrightnessBar = true;
        _showVolumeBar = false;
      });
    } else {
      // 右侧：调节音量
      final newVol = (_volume - delta / 600 * 100).clamp(0.0, 100.0);
      _volume = newVol;
      _player.setVolume(newVol);
      setState(() {
        _showVolumeBar = true;
        _showBrightnessBar = false;
      });
    }
    _startGestureBarTimer();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _startGestureBarTimer();
  }

  Future<void> _setBrightness(double value) async {
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      final mpvValue = ((value - 0.5) * 100).round();
      await native.setProperty('brightness', mpvValue.toString());
    }
  }

  void _startGestureBarTimer() {
    _gestureBarTimer?.cancel();
    _gestureBarTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showBrightnessBar = false;
          _showVolumeBar = false;
        });
      }
    });
  }

  Widget _buildBrightnessBar() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.15,
      bottom: MediaQuery.of(context).size.height * 0.15,
      right: 20,
      child: _buildVerticalBar(
        value: _brightness,
        icon: Icons.brightness_6,
        color: const Color(0xFFFFD54F),
      ),
    );
  }

  Widget _buildVolumeBar() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.15,
      bottom: MediaQuery.of(context).size.height * 0.15,
      left: 20,
      child: _buildVerticalBar(
        value: _volume / 100,
        icon: _volume == 0
            ? Icons.volume_off
            : _volume < 50
                ? Icons.volume_down
                : Icons.volume_up,
        color: const Color(0xFF6366F1),
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
                    icon: _isLandscape
                        ? Icons.screen_lock_portrait
                        : Icons.screen_lock_landscape,
                    onTap: _toggleOrientation,
                  ),
                ],
                // 画面比例（仅本地播放）
                if ((Platform.isAndroid || Platform.isIOS) &&
                    widget.roomCode == null) ...[
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