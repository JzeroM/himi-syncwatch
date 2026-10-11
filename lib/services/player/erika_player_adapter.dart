import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show Size;

import 'player_adapter.dart';

/// Erika（自研 Rust 内核）播放器适配器：包装 [ErikaPlayer]，实现 [PlayerAdapter]。
///
/// 平台：非 TV 平台（Android/iOS/macOS/Linux/Windows）；Android TV 不注册。
/// 特性：手机真 HDR10 + 原生位图字幕（PGS/VobSub）+ 弹幕。
///
/// 渲染：由 Flutter 侧挂载 [ErikaVideoView]（原生 surface / TextureView），
/// 本 adapter 的 [textureId] 仅作为"就绪哨兵"（非真实 Flutter 纹理）。
///
/// 限制：
/// - Erika 无 position/duration getter → 由 [ErikaPlayer.events] 缓存
/// - 外挂音频无对应 API → 抛 [UnimplementedError]
/// - setProperty/解码器/色彩空间/截图等无等价 API → no-op / null
class ErikaPlayerAdapter implements PlayerAdapter {
  ErikaPlayerAdapter({ErikaOutputMode outputMode = ErikaOutputMode.auto}) {
    _erikaPlayer = ErikaPlayer(outputMode: outputMode);
    _subscribe();
  }

  late final ErikaPlayer _erikaPlayer;

  /// 供 player_screen 挂载 [ErikaVideoView]。
  ErikaPlayer get erikaPlayer => _erikaPlayer;

  // ── 内部状态（events 缓存）────────────────────────────────

  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(1);

  final StreamController<
          ({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      _stateCtrl = StreamController.broadcast();
  final StreamController<
          ({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      _statusCtrl = StreamController.broadcast();
  final StreamController<AdapterMediaEvent> _eventCtrl =
      StreamController.broadcast();

  StreamSubscription<ErikaPlayerEvent>? _sub;

  AdapterPlaybackState _state = AdapterPlaybackState.stopped;
  AdapterMediaStatus _status = AdapterMediaStatus.unloaded;
  int _positionMs = 0;
  int _durationMs = 0;
  double _volume = 1.0;
  double _rate = 1.0;

  List<ErikaTrackInfo> _audioTracks = const [];
  List<ErikaTrackInfo> _subtitleTracks = const [];
  List<ErikaTrackInfo> _videoTracks = const [];
  int? _selectedAudioId;
  int? _selectedSubtitleId;

  String? _mediaUri;
  Map<String, String> _httpHeaders = const {};
  bool _disposed = false;

  void _subscribe() {
    _sub = _erikaPlayer.events.listen(
      _onEvent,
      onError: (Object error) {
        if (!_disposed) {
          _eventCtrl.add(AdapterMediaEvent(0, 'erika.error', '$error'));
        }
      },
    );
  }

  void _onEvent(ErikaPlayerEvent e) {
    if (_disposed) return;
    _positionMs = e.position.inMilliseconds;
    _durationMs = e.duration.inMilliseconds;
    _selectedAudioId = e.trackSelection.audio;
    _selectedSubtitleId = e.trackSelection.subtitle;
    if (e.trackList.isNotEmpty) {
      _videoTracks =
          e.trackList.where((t) => t.kind == ErikaTrackKind.video).toList();
      _audioTracks =
          e.trackList.where((t) => t.kind == ErikaTrackKind.audio).toList();
      _subtitleTracks =
          e.trackList.where((t) => t.kind == ErikaTrackKind.subtitle).toList();
    }

    final ns = _mapState(e.state);
    if (ns != _state) {
      final old = _state;
      _state = ns;
      _stateCtrl.add((oldValue: old, newValue: ns));
    }

    final st = _mapStatus(e);
    if (st.rawValue != _status.rawValue) {
      final old = _status;
      _status = st;
      _statusCtrl.add((oldValue: old, newValue: st));
    }

    if (e.kind == ErikaEventKind.error) {
      _eventCtrl.add(AdapterMediaEvent(
        e.status,
        'erika.error',
        e.error ?? e.message ?? 'Erika 播放错误',
      ));
    }
  }

  AdapterPlaybackState _mapState(ErikaPlaybackState s) {
    switch (s) {
      case ErikaPlaybackState.playing:
        return AdapterPlaybackState.playing;
      case ErikaPlaybackState.paused:
      case ErikaPlaybackState.ready:
        return AdapterPlaybackState.paused;
      case ErikaPlaybackState.idle:
      case ErikaPlaybackState.opening:
      case ErikaPlaybackState.stopped:
      case ErikaPlaybackState.closed:
      case ErikaPlaybackState.error:
        return AdapterPlaybackState.stopped;
    }
  }

  AdapterMediaStatus _mapStatus(ErikaPlayerEvent e) {
    switch (e.state) {
      case ErikaPlaybackState.idle:
      case ErikaPlaybackState.stopped:
      case ErikaPlaybackState.closed:
        return AdapterMediaStatus.unloaded;
      case ErikaPlaybackState.error:
        return AdapterMediaStatus.invalid;
      default:
        break;
    }
    if (e.buffering) return AdapterMediaStatus.buffering;
    if (e.duration.inMilliseconds > 0) return AdapterMediaStatus.loaded;
    return AdapterMediaStatus.loading;
  }

  // ── 播放控制 ──────────────────────────────────────────────

  @override
  AdapterPlaybackState get state => _state;

  @override
  set state(AdapterPlaybackState value) {
    switch (value) {
      case AdapterPlaybackState.playing:
        unawaited(_erikaPlayer.play());
      case AdapterPlaybackState.paused:
        unawaited(_erikaPlayer.pause());
      case AdapterPlaybackState.stopped:
        unawaited(_erikaPlayer.stop());
    }
    _state = value;
  }

  @override
  Future<void> seek({required int positionMs}) async {
    await _erikaPlayer.seek(Duration(milliseconds: positionMs));
  }

  // ── 媒体加载 ──────────────────────────────────────────────

  @override
  set media(String uri) {
    _mediaUri = uri;
  }

  @override
  Future<void> prepare() async {
    final uri = _mediaUri;
    if (uri == null) return;
    await _erikaPlayer.open(uri, httpHeaders: _httpHeaders);
    await _refreshTracks();
  }

  Future<void> _refreshTracks() async {
    try {
      final list = await _erikaPlayer.tracks();
      if (_disposed) return;
      _videoTracks =
          list.where((t) => t.kind == ErikaTrackKind.video).toList();
      _audioTracks =
          list.where((t) => t.kind == ErikaTrackKind.audio).toList();
      _subtitleTracks =
          list.where((t) => t.kind == ErikaTrackKind.subtitle).toList();
    } catch (_) {}
  }

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position => _positionMs;

  @override
  int get duration => _durationMs;

  @override
  AdapterMediaInfo get mediaInfo => AdapterMediaInfo(
        duration: _durationMs,
        audio: _audioTracks
            .map((t) => AdapterAudioStream(
                  codec: (t.codec ?? '').toLowerCase(),
                  bitRate: t.bitRate ?? 0,
                  channels: t.channels,
                  sampleRate: t.sampleRate,
                ))
            .toList(),
        video: _videoTracks
            .map((t) => AdapterVideoStream(
                  codec: (t.codec ?? '').toLowerCase(),
                  width: t.width,
                  height: t.height,
                  bitRate: t.bitRate ?? 0,
                ))
            .toList(),
        subtitleCount: _subtitleTracks.length,
      );

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value;
    unawaited(_erikaPlayer.setVolume(value));
  }

  @override
  double get playbackRate => _rate;

  @override
  set playbackRate(double value) {
    _rate = value;
    unawaited(_erikaPlayer.setPlaybackRate(value));
  }

  @override
  AdapterMediaStatus get mediaStatus => _status;

  @override
  int buffered() => 0;

  @override
  ValueListenable<int?> get textureId => _textureId;

  @override
  int get nativeHandle => 0;

  // ── 渲染（由 ErikaVideoView 接管）─────────────────────────

  @override
  Future<int> updateTexture({int? width, int? height, bool? tunnel}) async =>
      -1;

  @override
  Future<Size?> get textureSize async => null;

  @override
  void setColorSpace(AdapterColorSpace cs) {}

  @override
  void renderVideo() {}

  // ── 轨道 ──────────────────────────────────────────────────

  @override
  List<int> get activeAudioTracks {
    final idx = _audioTracks.indexWhere((t) => t.id == _selectedAudioId);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeAudioTracks(List<int> tracks) {
    if (tracks.isEmpty) {
      unawaited(_erikaPlayer.selectAudioTrack(null));
      return;
    }
    final idx = tracks.first;
    if (idx >= 0 && idx < _audioTracks.length) {
      unawaited(_erikaPlayer.selectAudioTrack(_audioTracks[idx].id));
    }
  }

  @override
  List<int> get activeSubtitleTracks {
    final idx = _subtitleTracks.indexWhere((t) => t.id == _selectedSubtitleId);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeSubtitleTracks(List<int> tracks) {
    if (tracks.isEmpty) {
      unawaited(_erikaPlayer.selectSubtitleTrack(null));
      return;
    }
    final idx = tracks.first;
    if (idx >= 0 && idx < _subtitleTracks.length) {
      unawaited(_erikaPlayer.selectSubtitleTrack(_subtitleTracks[idx].id));
    }
  }

  // ── 事件 ──────────────────────────────────────────────────

  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged => _stateCtrl.stream;

  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus => _statusCtrl.stream;

  @override
  Stream<AdapterMediaEvent> get onEvent => _eventCtrl.stream;

  // ── 属性通道 ──────────────────────────────────────────────

  @override
  void setProperty(String name, String value) {}

  @override
  String? getProperty(String name) => null;

  @override
  void setHttpHeaders(Map<String, String> headers) {
    _httpHeaders = Map.of(headers);
  }

  @override
  List<String> get videoDecoders => const [];

  @override
  set videoDecoders(List<String> decoders) {}

  @override
  List<String> get audioDecoders => const [];

  @override
  set audioDecoders(List<String> decoders) {}

  @override
  set audioBackends(List<String> backends) {}

  @override
  void setBufferRange({int min = -1, int max = -1, bool drop = false}) {}

  // ── 字幕 / 截图 ───────────────────────────────────────────

  @override
  Future<void> setMedia(String uri, {required AdapterMediaType type}) async {
    switch (type) {
      case AdapterMediaType.subtitle:
        await _erikaPlayer.addExternalSubtitle(uri);
        await _refreshTracks();
      case AdapterMediaType.audio:
        throw UnimplementedError('Erika 不支持外挂音频 setMedia');
    }
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) async => null;

  // ── 生命周期 ──────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    unawaited(_erikaPlayer.dispose());
    _textureId.dispose();
    _stateCtrl.close();
    _statusCtrl.close();
    _eventCtrl.close();
  }
}
