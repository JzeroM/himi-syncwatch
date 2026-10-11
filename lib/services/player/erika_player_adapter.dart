import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' show Size;

import 'package:himi_syncwatch/services/log_service.dart';

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

  /// position 锚点：**仅 positionChanged 事件更新**（其他事件 positionMicros=0），
  /// 播放中由 [position] getter 按速率外推。duration 同理仅在 >0 时更新。
  int _lastPositionMs = 0;
  DateTime _lastPositionUpdate = DateTime.now();
  int _durationMs = 0;
  double _volume = 1.0;
  double _rate = 1.0;
  bool _buffering = false;

  /// seek 栅栏：忽略 seek 途中迟到的旧 position 事件（与目标距离 >1.5s）。
  int? _pendingSeekTargetMs;
  DateTime? _seekFenceUntil;

  List<ErikaTrackInfo> _audioTracks = const [];
  List<ErikaTrackInfo> _subtitleTracks = const [];
  List<ErikaTrackInfo> _videoTracks = const [];

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

    _buffering = e.buffering;

    // 轨表：仅 tracksChanged/trackSelectionChanged（及其后续事件快照）携带，
    // 其余事件 trackList 为空 → 仅在非空时重建，避免清空。
    if (e.trackList.isNotEmpty) {
      _videoTracks =
          e.trackList.where((t) => t.kind == ErikaTrackKind.video).toList();
      _audioTracks =
          e.trackList.where((t) => t.kind == ErikaTrackKind.audio).toList();
      _subtitleTracks =
          e.trackList.where((t) => t.kind == ErikaTrackKind.subtitle).toList();
    }

    // duration：仅 >0 时更新（其余事件 durationMicros=0）。
    if (e.duration > Duration.zero) {
      _durationMs = e.duration.inMilliseconds;
    }

    // position：仅 positionChanged 事件有效（其余事件 positionMicros=0）。
    if (e.kind == ErikaEventKind.positionChanged &&
        e.position >= Duration.zero) {
      _applyPositionSample(e.position.inMilliseconds);
    }

    final ns = _mapState(e.state);
    if (ns != _state) {
      final old = _state;
      _state = ns;
      _stateCtrl.add((oldValue: old, newValue: ns));
      // 起播后轨表可能才解析完：补刷一次。
      if (ns == AdapterPlaybackState.playing &&
          _audioTracks.isEmpty &&
          _subtitleTracks.isEmpty) {
        unawaited(_refreshTracks());
      }
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

  /// 处理 positionChanged 采样：seek 栅栏期内忽略与目标差距过大的旧位置。
  void _applyPositionSample(int ms) {
    final target = _pendingSeekTargetMs;
    final fence = _seekFenceUntil;
    final now = DateTime.now();
    if (target != null && fence != null && now.isBefore(fence)) {
      if ((ms - target).abs() > 1500) return;
      _pendingSeekTargetMs = null;
      _seekFenceUntil = null;
    } else if (fence != null && !now.isBefore(fence)) {
      _pendingSeekTargetMs = null;
      _seekFenceUntil = null;
    }
    _lastPositionMs = ms;
    _lastPositionUpdate = now;
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
    if (_durationMs > 0) return AdapterMediaStatus.loaded;
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
    final clamped = positionMs < 0 ? 0 : positionMs;
    // 乐观置位 + seek 栅栏：避免 seek 完成前进度条回弹到旧位置。
    _lastPositionMs = clamped;
    _lastPositionUpdate = DateTime.now();
    _pendingSeekTargetMs = clamped;
    _seekFenceUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    await _erikaPlayer.seek(Duration(milliseconds: clamped));
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
      LogService().log('Erika',
          '轨表刷新: V=${_videoTracks.length} A=${_audioTracks.length} S=${_subtitleTracks.length}');
    } catch (e) {
      LogService().log('Erika', '轨表刷新失败: $e');
    }
  }

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position {
    if (_state != AdapterPlaybackState.playing || _buffering) {
      return _lastPositionMs;
    }
    final elapsed =
        DateTime.now().difference(_lastPositionUpdate).inMilliseconds;
    var pos = _lastPositionMs + (elapsed * _rate).round();
    if (pos < 0) pos = 0;
    if (_durationMs > 0 && pos > _durationMs) pos = _durationMs;
    return pos;
  }

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
    // 选中态取自 trackList[i].selected（trackSelection 事件字段多数为空）。
    final idx = _audioTracks.indexWhere((t) => t.selected);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeAudioTracks(List<int> tracks) {
    if (tracks.isEmpty) {
      unawaited(_erikaPlayer.selectAudioTrack(null));
      return;
    }
    unawaited(_selectAudioIndex(tracks.first));
  }

  Future<void> _selectAudioIndex(int idx) async {
    if (idx < 0) return;
    if (idx >= _audioTracks.length) await _refreshTracks();
    if (idx < _audioTracks.length) {
      final id = _audioTracks[idx].id;
      LogService().log(
          'Erika', '选音轨 idx=$idx id=$id (共${_audioTracks.length})');
      await _erikaPlayer.selectAudioTrack(id);
    } else {
      LogService()
          .log('Erika', '选音轨越界 idx=$idx (共${_audioTracks.length})');
    }
  }

  @override
  List<int> get activeSubtitleTracks {
    final idx = _subtitleTracks.indexWhere((t) => t.selected);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeSubtitleTracks(List<int> tracks) {
    if (tracks.isEmpty) {
      unawaited(_erikaPlayer.selectSubtitleTrack(null));
      return;
    }
    unawaited(_selectSubtitleIndex(tracks.first));
  }

  Future<void> _selectSubtitleIndex(int idx) async {
    if (idx < 0) return;
    if (idx >= _subtitleTracks.length) await _refreshTracks();
    if (idx < _subtitleTracks.length) {
      final id = _subtitleTracks[idx].id;
      LogService().log(
          'Erika', '选字幕 idx=$idx id=$id (共${_subtitleTracks.length})');
      await _erikaPlayer.selectSubtitleTrack(id);
    } else {
      LogService()
          .log('Erika', '选字幕越界 idx=$idx (共${_subtitleTracks.length})');
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
