import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:himi_syncwatch/core/config.dart';
import 'package:himi_syncwatch/core/constants.dart';
import 'package:himi_syncwatch/models/room.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/rtm_provider.dart';
import 'package:himi_syncwatch/services/room_service.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? roomId;
  final String? mediaSourceId;

  const PlayerScreen({
    super.key,
    required this.itemId,
    this.roomId,
    this.mediaSourceId,
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
  Room? _room;
  String? _myUserId;

  double _volume = 100;
  bool _syncPaused = false;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _myUserId = 'user-${DateTime.now().millisecondsSinceEpoch}';

    _initializePlayer();
    _setupPlayerListeners();

    if (widget.roomId != null) {
      _setupRoomSync();
    }
  }

  Future<void> _initializePlayer() async {
    final embyService = ref.read(embyServiceProvider);
    final streamUrl = embyService.getStreamUrl(
      widget.itemId,
      mediaSourceId: widget.mediaSourceId,
    );
    final config = ref.read(embyConfigProvider);
    final token = config?.accessToken ?? '';

    final url = await _resolveStreamUrl(streamUrl, token);

    await _player.open(Media(url, httpHeaders: {
      'X-Emby-Token': token,
    }));
  }

  Future<String> _resolveStreamUrl(String url, String token) async {
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
          return location;
        }
      }

      client.close(force: true);
      return url;
    } catch (_) {
      return url;
    }
  }

  void _setupPlayerListeners() {
    _player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });

    _player.stream.duration.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });

    _player.stream.volume.listen((volume) {
      if (mounted) setState(() => _volume = volume);
    });
  }

  void _setupRoomSync() async {
    final roomService = RoomService();

    final room = await roomService.joinRoom(
      roomId: widget.roomId!,
      userId: _myUserId!,
      userName: '观众',
    );

    if (room == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加入房间失败')),
        );
      }
      return;
    }

    _room = room;
    _isHost = room.hostId == _myUserId;

    final rtmService = ref.read(rtmServiceProvider);
    await rtmService.initialize(
      appId: AgoraConfig.appId,
      userId: _myUserId!,
    );
    await rtmService.login(AgoraConfig.appId);
    await rtmService.subscribe(widget.roomId!);

    _rtmSubscription = rtmService.messageStream.listen((message) {
      if (!mounted) return;
      final senderId = message['userId'];
      if (senderId == _myUserId) return;

      final type = message['type'];
      if (type == AppConstants.msgTypeHeartbeat) {
        _handleHeartbeat(message);
      } else if (type == AppConstants.msgTypeCommand) {
        _handleCommand(message);
      }
    });

    if (_isHost) {
      _startHeartbeat();
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
      _player
          .seek(Duration(milliseconds: (expectedPos * 1000).toInt()));
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
      if (widget.roomId != null) {
        _sendCommand(AppConstants.actionPause);
      }
    } else {
      _player.play();
      if (widget.roomId != null) {
        _sendCommand(AppConstants.actionPlay);
      }
    }
  }

  void _onSeek(double value) {
    _player.seek(Duration(milliseconds: value.toInt()));
    if (widget.roomId != null) {
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
          setState(() => _showControls = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rtmSubscription?.cancel();

    if (widget.roomId != null) {
      final roomService = RoomService();
      roomService.leaveRoom(roomId: widget.roomId!, userId: _myUserId!);
    }

    _player.dispose();
    super.dispose();
  }

  bool get _canControlPlayback {
    if (widget.roomId == null) return true;
    return _isHost;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
              ),
            ),

            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(),
              ),

            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildControls(),
              ),

            if (_duration.inMilliseconds == 0)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 8,
        right: 8,
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
          if (widget.roomId != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isHost ? const Color(0xFF6366F1) : Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_isHost ? "房主" : "房间"}: ${widget.roomId}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            if (_room != null)
              Text(
                '${_room!.members.length}人',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF6366F1),
              inactiveTrackColor: Colors.white24,
              thumbColor: const Color(0xFF6366F1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
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

          // 时间 + 控制按钮
          Row(
            children: [
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const Spacer(),
              // 音量
              _buildVolumeButton(),
              // 字幕
              _buildSubtitleButton(),
              // 音轨
              _buildAudioTrackButton(),
              // 播放/暂停（仅房主/独立播放显示）
              if (_canControlPlayback) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _player.state.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Colors.white,
                    size: 36,
                  ),
                  onPressed: _togglePlayPause,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeButton() {
    return PopupMenuButton<double>(
      offset: const Offset(0, -180),
      onSelected: (value) {
        _player.setVolume(value);
      },
      itemBuilder: (context) => [
        const PopupMenuItem<double>(
          enabled: false,
          child: Text('音量', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        PopupMenuItem<double>(
          value: 0,
          child: Row(
            children: [
              Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up,
                  size: 18),
              const SizedBox(width: 8),
              const Text('静音'),
            ],
          ),
        ),
        PopupMenuItem<double>(
          value: 50,
          child: Row(
            children: [
              Icon(
                _volume >= 50 ? Icons.volume_up : Icons.volume_down,
                size: 18,
                color: _volume == 50 ? const Color(0xFF6366F1) : null,
              ),
              const SizedBox(width: 8),
              Text('50%',
                  style: TextStyle(
                    color: _volume == 50 ? const Color(0xFF6366F1) : null,
                  )),
            ],
          ),
        ),
        PopupMenuItem<double>(
          value: 100,
          child: Row(
            children: [
              Icon(Icons.volume_up,
                  size: 18,
                  color: _volume == 100 ? const Color(0xFF6366F1) : null),
              const SizedBox(width: 8),
              Text('100%',
                  style: TextStyle(
                    color: _volume == 100 ? const Color(0xFF6366F1) : null,
                  )),
            ],
          ),
        ),
      ],
      child: Icon(
        _volume == 0
            ? Icons.volume_off
            : _volume < 50
                ? Icons.volume_down
                : Icons.volume_up,
        color: Colors.white,
        size: 22,
      ),
    );
  }

  Widget _buildSubtitleButton() {
    final tracks = _player.state.tracks;
    final subtitleTracks = tracks.subtitle;
    final currentSubtitle = _player.state.track.subtitle;

    return PopupMenuButton<String>(
      offset: const Offset(0, -180),
      onSelected: (value) {
        if (value == 'off') {
          _player.setSubtitleTrack(SubtitleTrack.no());
        } else {
          final idx = int.tryParse(value);
          if (idx != null && idx < subtitleTracks.length) {
            _player.setSubtitleTrack(subtitleTracks[idx]);
          }
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuItem<String>>[
          const PopupMenuItem<String>(
            enabled: false,
            child:
                Text('字幕', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          PopupMenuItem<String>(
            value: 'off',
            child: Row(
              children: [
                if (currentSubtitle.id == 'no')
                  const Icon(Icons.check, size: 18, color: Color(0xFF6366F1))
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('关闭'),
              ],
            ),
          ),
        ];

        for (int i = 0; i < subtitleTracks.length; i++) {
          final track = subtitleTracks[i];
          final lang = track.language?.isNotEmpty == true
              ? track.language!
              : track.title ?? '字幕 ${i + 1}';
          final isActive = currentSubtitle.id == track.id;
          items.add(
            PopupMenuItem<String>(
              value: '$i',
              child: Row(
                children: [
                  if (isActive)
                    const Icon(Icons.check, size: 18, color: Color(0xFF6366F1))
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return items;
      },
      child: const Icon(Icons.subtitles, color: Colors.white, size: 22),
    );
  }

  Widget _buildAudioTrackButton() {
    final tracks = _player.state.tracks;
    final audioTracks = tracks.audio;
    final currentAudio = _player.state.track.audio;

    return PopupMenuButton<String>(
      offset: const Offset(0, -180),
      onSelected: (value) {
        final idx = int.tryParse(value);
        if (idx != null && idx < audioTracks.length) {
          _player.setAudioTrack(audioTracks[idx]);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuItem<String>>[
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('音轨', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ];

        for (int i = 0; i < audioTracks.length; i++) {
          final track = audioTracks[i];
          final lang = track.language?.isNotEmpty == true
              ? track.language!
              : track.title ?? '音轨 ${i + 1}';
          final isActive = currentAudio.id == track.id;
          items.add(
            PopupMenuItem<String>(
              value: '$i',
              child: Row(
                children: [
                  if (isActive)
                    const Icon(Icons.check, size: 18, color: Color(0xFF6366F1))
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lang,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return items;
      },
      child: const Icon(Icons.audiotrack, color: Colors.white, size: 22),
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
