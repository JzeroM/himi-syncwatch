import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:himi_syncwatch/core/config.dart';
import 'package:himi_syncwatch/core/constants.dart';
import 'package:himi_syncwatch/models/media_item.dart';
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

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(libass: true));
    _controller = VideoController(_player);
    _myUserId = 'user-${DateTime.now().millisecondsSinceEpoch}';

    _initializePlayer();
    _setupPlayerListeners();

    if (widget.roomId != null) {
      _setupRoomSync();
    }
  }

  Future<void> _initializePlayer() async {
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      await native.setProperty('sub-visibility', 'yes');
      await native.setProperty('sub-auto', 'fuzzy');
      await native.setProperty('sub-font-size', '40');
      await native.setProperty('sub-border-size', '2');
      await native.setProperty('sub-shadow-offset', '1');
      await native.setProperty('sub-margin-y', '22');
    }

    final embyService = ref.read(embyServiceProvider);

    final details = await embyService.getItemDetails(widget.itemId);
    if (details != null && mounted) {
      final source = details.mediaSources.firstWhere(
        (s) => s.id == widget.mediaSourceId,
        orElse: () => details.mediaSources.firstOrNull ??
            MediaSource(id: '', name: ''),
      );
      setState(() {
        _embyAudioStreams = source.audioStreams;
        _embySubtitleStreams = source.subtitleStreams;
        _embyDefaultAudioIndex = source.defaultAudioStreamIndex;
      });
    }

    await _loadStream();
  }

  Future<void> _loadStream({int? subtitleStreamIndex}) async {
    final embyService = ref.read(embyServiceProvider);
    final config = ref.read(embyConfigProvider);
    final token = config?.accessToken ?? '';

    final streamUrl = embyService.getStreamUrl(
      widget.itemId,
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
  }

  void _autoSelectDefaultTracks() {
    _player.setSubtitleTrack(SubtitleTrack.auto());

    if (_embyDefaultAudioIndex != null) {
      final embyIdx = _embyAudioStreams.indexWhere(
        (s) => s.index == _embyDefaultAudioIndex,
      );
      if (embyIdx >= 0 && embyIdx < _audioTracks.length) {
        _player.setAudioTrack(_audioTracks[embyIdx]);
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

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rtmSubscription?.cancel();
    _tracksSubscription?.cancel();

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
        onTap: () {
          if (_showVolumeSlider || _showSubtitleMenu || _showAudioMenu) {
            _closeAllMenus();
          } else {
            _toggleControls();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            Center(
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
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
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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

            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildControlButton(
                  icon: _volumeIcon,
                  onTap: () {
                    setState(() {
                      _showVolumeSlider = !_showVolumeSlider;
                      _showSubtitleMenu = false;
                      _showAudioMenu = false;
                    });
                  },
                ),
                const SizedBox(width: 28),
                _buildControlButton(
                  icon: Icons.subtitles,
                  onTap: () {
                    setState(() {
                      _showSubtitleMenu = !_showSubtitleMenu;
                      _showVolumeSlider = false;
                      _showAudioMenu = false;
                    });
                  },
                  badge: _embySubtitleStreams.isNotEmpty ? '${_embySubtitleStreams.length}' : null,
                ),
                const SizedBox(width: 28),
                _buildControlButton(
                  icon: Icons.audiotrack,
                  onTap: () {
                    setState(() {
                      _showAudioMenu = !_showAudioMenu;
                      _showVolumeSlider = false;
                      _showSubtitleMenu = false;
                    });
                  },
                  badge: _embyAudioStreams.isNotEmpty ? '${_embyAudioStreams.length}' : null,
                ),
                if (_canControlPlayback) ...[
                  const SizedBox(width: 28),
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Icon(
                      _player.state.playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ],
              ],
            ),

            if (_showVolumeSlider) ...[
              const SizedBox(height: 12),
              _buildVolumeSlider(),
            ],

            if (_showSubtitleMenu) ...[
              const SizedBox(height: 12),
              _buildSubtitleList(),
            ],

            if (_showAudioMenu) ...[
              const SizedBox(height: 12),
              _buildAudioTrackList(),
            ],
          ],
        ),
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
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVolumeSlider() {
    return Row(
      children: [
        Icon(
          _volume == 0
              ? Icons.volume_off
              : _volume < 50
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Colors.white70,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF6366F1),
              inactiveTrackColor: Colors.white24,
              thumbColor: const Color(0xFF6366F1),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: _volume.clamp(0, 100),
              min: 0,
              max: 100,
              onChanged: (value) {
                _player.setVolume(value);
              },
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 36,
          child: Text(
            '${_volume.round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitleList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          _buildMenuItem(
            label: '关闭字幕',
            isSelected: _currentSubtitle?.id == 'no' && !_useServerSubtitleBurnIn,
            onTap: () {
              if (_useServerSubtitleBurnIn) {
                _useServerSubtitleBurnIn = false;
                _activeSubtitleIndex = null;
                _loadStream();
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
      ),
    );
  }

  Widget _buildAudioTrackList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
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
      ),
    );
  }

  bool _isEmbySubtitleSelected(int embyIndex) {
    final stream = _embySubtitleStreams[embyIndex];
    if (_useServerSubtitleBurnIn) {
      return _activeSubtitleIndex == stream.index;
    }
    if (_currentSubtitle == null) return false;
    if (_currentSubtitle!.id == 'no') return false;
    final mpvIndex = _findMpvSubtitleIndex(embyIndex);
    if (mpvIndex == null) return false;
    return _currentSubtitle?.id == _subtitleTracks[mpvIndex].id;
  }

  bool _isEmbyAudioSelected(int embyIndex) {
    if (_currentAudio == null) return false;
    final mpvIndex = _findMpvAudioIndex(embyIndex);
    if (mpvIndex == null) return false;
    return _currentAudio?.id == _audioTracks[mpvIndex].id;
  }

  int? _findMpvSubtitleIndex(int embyIndex) {
    if (embyIndex >= _subtitleTracks.length) return null;
    return embyIndex;
  }

  int? _findMpvAudioIndex(int embyIndex) {
    if (embyIndex >= _audioTracks.length) return null;
    return embyIndex;
  }

  void _selectEmbySubtitle(int embyIndex) {
    final stream = _embySubtitleStreams[embyIndex];
    final isExternal = stream.isExternal ||
        stream.subtitleLocationType == 'ExternalStream';

    if (isExternal) {
      _useServerSubtitleBurnIn = true;
      _activeSubtitleIndex = stream.index;
      _loadStream(subtitleStreamIndex: stream.index);
    } else {
      _useServerSubtitleBurnIn = false;
      _activeSubtitleIndex = stream.index;
      for (final track in _subtitleTracks) {
        if (track.id == 'auto' || track.id == 'no') continue;
        final matchLang = stream.language != null &&
            track.language != null &&
            stream.language == track.language;
        final matchTitle = stream.displayTitle != null &&
            track.title != null &&
            stream.displayTitle!.contains(track.title!);
        if (matchLang || matchTitle) {
          _player.setSubtitleTrack(track);
          return;
        }
      }
      final mpvIndex = _findMpvSubtitleIndex(embyIndex);
      if (mpvIndex != null && mpvIndex < _subtitleTracks.length) {
        _player.setSubtitleTrack(_subtitleTracks[mpvIndex]);
      }
    }
  }

  void _selectEmbyAudio(int embyIndex) {
    final mpvIndex = _findMpvAudioIndex(embyIndex);
    if (mpvIndex != null && mpvIndex < _audioTracks.length) {
      _player.setAudioTrack(_audioTracks[mpvIndex]);
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check, size: 16, color: Color(0xFF6366F1))
            else
              const SizedBox(width: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF6366F1) : Colors.white,
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

  IconData get _volumeIcon =>
      _volume == 0
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
