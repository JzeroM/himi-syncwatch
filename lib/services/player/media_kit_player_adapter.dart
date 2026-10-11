import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'player_adapter.dart';

/// media_kit（libmpv）播放器适配器：包装 media_kit Player，实现 [PlayerAdapter] 接口。
///
/// Phase 2 引擎。限制（仅手机/桌面，TV 模式不注册）：
/// - 渲染通道：无 textureId/nativeHandle（Video widget 挂载），updateTexture/
///   textureSize/renderVideo 为 no-op
/// - setProperty/getProperty：走 NativePlayer，非 NativePlayer 时 no-op
/// - setMedia（外挂字幕）：media_kit 无等价 API，抛 UnimplementedError
/// - setBufferRange/videoDecoders/audioDecoders/audioBackends/setColorSpace：
///   media_kit 无等价 API，no-op
///
/// 刻度转换：volume 0.0-1.0 ↔ media_kit 0-100；position/duration ms ↔ Duration。
class MediaKitPlayerAdapter implements PlayerAdapter {
  MediaKitPlayerAdapter() : _player = Player();

  final Player _player;

  /// 诊断面板直接访问底层 media_kit Player（仅 media_kit 档）。
  Player get raw => _player;

  // ── 播放控制 ──────────────────────────────────────────────

  @override
  AdapterPlaybackState get state {
    final s = _player.state;
    if (s.playing) return AdapterPlaybackState.playing;
    return AdapterPlaybackState.paused;
  }

  @override
  set state(AdapterPlaybackState value) {
    switch (value) {
      case AdapterPlaybackState.playing:
        _player.play();
      case AdapterPlaybackState.paused:
        _player.pause();
      case AdapterPlaybackState.stopped:
        _player.pause();
    }
  }

  @override
  Future<void> seek({required int positionMs}) async {
    await _player.seek(Duration(milliseconds: positionMs));
  }

  // ── 媒体加载 ──────────────────────────────────────────────

  String? _currentUri;

  @override
  set media(String uri) {
    _currentUri = uri;
  }

  @override
  Future<void> prepare() async {
    final uri = _currentUri;
    if (uri == null) return;
    await _player.open(Media(uri));
  }

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position => _player.state.position.inMilliseconds;

  @override
  int get duration => _player.state.duration.inMilliseconds;

  @override
  AdapterMediaInfo get mediaInfo {
    final s = _player.state;
    return AdapterMediaInfo(
      duration: s.duration.inMilliseconds,
      audio: const [],
      video: const [],
      subtitleCount: s.tracks.subtitle.length,
    );
  }

  @override
  double get volume => _player.state.volume / 100.0;

  @override
  set volume(double value) => _player.setVolume((value * 100).clamp(0, 100));

  @override
  double get playbackRate => _player.state.rate;

  @override
  set playbackRate(double value) => _player.setRate(value);

  @override
  AdapterMediaStatus get mediaStatus {
    final s = _player.state;
    if (s.completed) return AdapterMediaStatus.end;
    if (s.buffering) return AdapterMediaStatus.buffering;
    if (s.playing) return AdapterMediaStatus.loaded;
    return AdapterMediaStatus.loaded;
  }

  @override
  int buffered() => 0;

  @override
  ValueListenable<int?> get textureId => _kNoTexture;

  @override
  int get nativeHandle => 0;

  // ── 渲染（no-op）───────────────────────────────────────────

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
    final tracks = _player.state.tracks.audio;
    final current = _player.state.track.audio;
    final idx = tracks.indexOf(current);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeAudioTracks(List<int> tracks) {
    final list = _player.state.tracks.audio;
    if (tracks.isEmpty) {
      _player.setAudioTrack(AudioTrack.no());
      return;
    }
    final idx = tracks.first;
    if (idx >= 0 && idx < list.length) {
      _player.setAudioTrack(list[idx]);
    }
  }

  @override
  List<int> get activeSubtitleTracks {
    final tracks = _player.state.tracks.subtitle;
    final current = _player.state.track.subtitle;
    final idx = tracks.indexOf(current);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeSubtitleTracks(List<int> tracks) {
    final list = _player.state.tracks.subtitle;
    if (tracks.isEmpty) {
      _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final idx = tracks.first;
    if (idx >= 0 && idx < list.length) {
      _player.setSubtitleTrack(list[idx]);
    }
  }

  // ── 事件（media_kit 事件模型不同，统一为流桥接）─────────

  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged {
    return _player.stream.playing.map((playing) {
      final newValue = playing
          ? AdapterPlaybackState.playing
          : AdapterPlaybackState.paused;
      return (oldValue: newValue, newValue: newValue);
    });
  }

  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus {
    // 监听 duration 变化：从 0（loading）→ >0（loaded）
    AdapterMediaStatus last = AdapterMediaStatus.loading;
    return _player.stream.duration.map((d) {
      final newValue = d.inMilliseconds > 0
          ? AdapterMediaStatus.loaded
          : AdapterMediaStatus.loading;
      final oldValue = last;
      last = newValue;
      return (oldValue: oldValue, newValue: newValue);
    }).where((e) => e.oldValue != e.newValue);
  }

  @override
  Stream<AdapterMediaEvent> get onEvent => const Stream.empty();

  // ── 属性通道 ──────────────────────────────────────────────

  NativePlayer? get _native {
    final p = _player.platform;
    return p is NativePlayer ? p : null;
  }

  @override
  void setProperty(String name, String value) {
    _native?.setProperty(name, value);
  }

  @override
  String? getProperty(String name) {
    final n = _native;
    if (n == null) return null;
    try {
      return n.getProperty(name) as String?;
    } catch (_) {
      return null;
    }
  }

  /// 应用 media_kit 引擎设置（mpv 属性，通过 NativePlayer.setProperty 直写）。
  /// 由 player_screen 在引擎初始化/切换时调用。
  void applySettings({
    required String hwdec,
    required String toneMapping,
    required double cacheSizeMb,
  }) {
    setProperty('hwdec', hwdec);
    setProperty('tone-mapping', toneMapping);
    setProperty('cache-size', '${(cacheSizeMb * 1024 * 1024).toInt()}');
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
    throw UnimplementedError('media_kit 不支持外挂字幕 setMedia');
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) =>
      _player.screenshot();

  // ── 生命周期 ──────────────────────────────────────────────

  @override
  void dispose() => _player.dispose();

  static final _kNoTexture = ValueNotifier<int?>(null);
}
