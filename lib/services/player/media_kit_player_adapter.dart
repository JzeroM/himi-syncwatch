import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_adapter.dart';

/// media_kit（libmpv）播放器适配器：包装 media_kit Player + VideoController。
///
/// Phase 2 引擎。限制（仅手机/桌面，TV 模式不注册）：
/// - 渲染：通过 VideoController 注册 Flutter Texture，textureId 桥接到
///   PlatformVideoController.id；UI 层挂载 Video(controller: ...) 渲染
/// - setProperty/getProperty：走 NativePlayer，非 NativePlayer 时 no-op
/// - setMedia（外挂字幕）：media_kit 无等价 API，抛 UnimplementedError
/// - setBufferRange/videoDecoders/audioDecoders/audioBackends/setColorSpace：
///   media_kit 无等价 API，no-op
///
/// 刻度转换：volume 0.0-1.0 ↔ media_kit 0-100；position/duration ms ↔ Duration。
class MediaKitPlayerAdapter implements PlayerAdapter {
  MediaKitPlayerAdapter()
      : _player = Player(
          configuration: const PlayerConfiguration(
            // 开启 libass → sub-visibility=yes，mpv 将字幕（含 PGS/VobSub
            // 图片字幕）渲染到视频纹理，与 mdk 行为一致。
            // PGS 是图片字幕，mpv 内置解码器直接渲染，不依赖 libass 字体。
            // Android 上文本字幕如遇缺字形，后续可捆绑 Noto 字体解决。
            libass: true,
          ),
        ) {
    _controller = VideoController(_player);
    // 桥接两级 ValueListenable：controller.notifier → platformController.id
    _controller.notifier.addListener(_onControllerNotifier);
  }

  final Player _player;
  late final VideoController _controller;

  /// UI 层挂载 Video widget 用。
  VideoController get videoController => _controller;

  /// 诊断面板直接访问底层 media_kit Player（仅 media_kit 档）。
  Player get raw => _player;

  // ── textureId 桥接 ────────────────────────────────────────

  final ValueNotifier<int?> _textureId = ValueNotifier<int?>(null);
  PlatformVideoController? _platformController;

  void _onControllerNotifier() {
    final pc = _controller.notifier.value;
    if (_platformController != null && _platformController != pc) {
      _platformController!.id.removeListener(_onPlatformId);
    }
    _platformController = pc;
    if (pc != null) {
      pc.id.addListener(_onPlatformId);
      _textureId.value = pc.id.value;
    }
  }

  void _onPlatformId() {
    _textureId.value = _platformController?.id.value;
  }

  // ── HTTP 鉴权头 ───────────────────────────────────────────

  Map<String, String> _httpHeaders = {};

  /// 设置 HTTP 鉴权头（media_kit 通过 Media(httpHeaders:) 传递，
  /// mdk 的 avio.headers 属性对 mpv 无效）。
  @override
  void setHttpHeaders(Map<String, String> headers) {
    _httpHeaders = Map.of(headers);
  }

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
    await _player.open(Media(uri, httpHeaders: _httpHeaders));
  }

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position => _player.state.position.inMilliseconds;

  @override
  int get duration => _player.state.duration.inMilliseconds;

  @override
  AdapterMediaInfo get mediaInfo {
    final s = _player.state;
    // 填充真实音轨/视轨（过滤 auto/no 哨兵），恢复诊断与 codec 回退正确性
    final audioStreams = _realAudioTracks
        .map((t) => AdapterAudioStream(
              codec: (t.codec ?? '').toLowerCase(),
              bitRate: t.bitrate ?? 0,
              channels: t.channelscount ?? 0,
              sampleRate: t.samplerate ?? 0,
            ))
        .toList();
    final videoStreams = _realVideoTracks
        .map((t) => AdapterVideoStream(
              codec: (t.codec ?? '').toLowerCase(),
              width: t.w ?? 0,
              height: t.h ?? 0,
              par: t.par ?? 1.0,
              rotation: t.rotate ?? 0,
              bitRate: t.bitrate ?? 0,
            ))
        .toList();
    return AdapterMediaInfo(
      duration: s.duration.inMilliseconds,
      audio: audioStreams,
      video: videoStreams,
      subtitleCount: _realSubtitleTracks.length,
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
  ValueListenable<int?> get textureId => _textureId;

  @override
  int get nativeHandle => 0;

  // ── 渲染（no-op，由 Video widget 接管）────────────────────

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
  //
  // media_kit 的 state.tracks.{audio,subtitle} 列表头部预置 auto/no 两个
  // 哨兵（id='auto'/'no'），真实轨在后。PlayerAdapter 接口语义是「Emby
  // 位置 = 真实轨位置」（与 mdk 一致），故此处过滤哨兵后再按位置索引。

  /// 纯函数：过滤掉 auto/no 哨兵，返回真实轨列表（便于单测）。
  /// 通过 `id` getter 判等；AudioTrack/VideoTrack/SubtitleTrack 均有 `id`。
  static List<T> filterRealTracks<T>(List<T> tracks,
          String Function(T) idOf) =>
      tracks
          .where((t) {
            final id = idOf(t);
            return id != 'auto' && id != 'no';
          })
          .toList();

  /// 过滤掉 auto/no 哨兵，返回真实音轨列表。
  List<AudioTrack> get _realAudioTracks =>
      filterRealTracks(_player.state.tracks.audio, (t) => t.id);

  /// 过滤掉 auto/no 哨兵，返回真实视轨列表。
  List<VideoTrack> get _realVideoTracks =>
      filterRealTracks(_player.state.tracks.video, (t) => t.id);

  /// 过滤掉 auto/no 哨兵，返回真实字幕轨列表。
  List<SubtitleTrack> get _realSubtitleTracks =>
      filterRealTracks(_player.state.tracks.subtitle, (t) => t.id);

  @override
  List<int> get activeAudioTracks {
    final real = _realAudioTracks;
    final current = _player.state.track.audio;
    final idx = real.indexOf(current);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeAudioTracks(List<int> tracks) {
    if (tracks.isEmpty) {
      _player.setAudioTrack(AudioTrack.no());
      return;
    }
    final real = _realAudioTracks;
    final idx = tracks.first;
    if (idx >= 0 && idx < real.length) {
      _player.setAudioTrack(real[idx]);
    }
  }

  @override
  List<int> get activeSubtitleTracks {
    final real = _realSubtitleTracks;
    final current = _player.state.track.subtitle;
    final idx = real.indexOf(current);
    return idx >= 0 ? [idx] : const [];
  }

  @override
  set activeSubtitleTracks(List<int> tracks) {
    if (tracks.isEmpty) {
      _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final real = _realSubtitleTracks;
    final idx = tracks.first;
    if (idx >= 0 && idx < real.length) {
      _player.setSubtitleTrack(real[idx]);
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
    switch (type) {
      case AdapterMediaType.subtitle:
        // media_kit 通过 SubtitleTrack.uri → mpv sub-add 加载外挂字幕。
        // 网络 URL 需鉴权头时，mpv 的 sub-add 不走 Media(httpHeaders:)，
        // 需提前设置 http-header-fields 属性。
        if (_httpHeaders.isNotEmpty) {
          final entries = _httpHeaders.entries
              .map((e) => '${e.key}: ${e.value}')
              .join(',');
          setProperty('http-header-fields', entries);
        }
        await _player.setSubtitleTrack(SubtitleTrack.uri(uri));
      case AdapterMediaType.audio:
        await _player.setAudioTrack(AudioTrack.uri(uri));
    }
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) =>
      _player.screenshot();

  // ── 生命周期 ──────────────────────────────────────────────

  @override
  void dispose() {
    _controller.notifier.removeListener(_onControllerNotifier);
    _platformController?.id.removeListener(_onPlatformId);
    _textureId.dispose();
    _player.dispose();
  }
}
