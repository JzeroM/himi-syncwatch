import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

export 'himi_mpv_android_surface_view.dart';

/// Android MPV 会话：SurfaceView 由原生插件提供，libmpv 由 media_kit 驱动。
///
/// 与鸿蒙共用 [MpvSession] 契约；渲染目标通过 `wid` 指向 SurfaceView 的
/// Java Surface 全局引用，Flutter 只保留透明覆盖层。
class HimiMpvAndroidSession implements MpvSession {
  HimiMpvAndroidSession._({
    required this.width,
    required this.height,
    required this.hwdecMode,
    required this.nativeSurface,
    required this.nativeUi,
    required this.hdr,
    required this.hlg,
  });

  static const MethodChannel _methods = MethodChannel('himi_mpv_android');
  static const EventChannel _surfaceEvents =
      EventChannel('himi_mpv_android/surface');

  final int width;
  final int height;
  final String hwdecMode;
  final bool nativeSurface;

  /// 是否启用全屏原生播放器 UI（Dialog + SurfaceView）。
  final bool nativeUi;
  final bool hdr;
  final bool hlg;

  final StreamController<Map<Object?, Object?>> _events =
      StreamController<Map<Object?, Object?>>.broadcast();
  StreamSubscription<dynamic>? _surfaceSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;

  Player? _player;
  VideoController? _controller;
  VoidCallback? _textureIdListener;
  int _surfaceHandle = 0;
  int _textureId = 0;
  bool _disposed = false;
  int _positionMs = 0;
  int _durationMs = 0;
  int _bufferedMs = 0;
  bool _paused = true;
  bool _eof = false;

  String? _pendingUrl;
  Map<String, String> _pendingHeaders = const {};
  int _pendingStartMs = 0;
  bool _pendingPause = false;
  double? _pendingVolume;
  double? _pendingSpeed;
  final Map<String, String> _pendingProperties = <String, String>{};

  /// 最近一次成功发起播放的地址（Surface 重建后据此恢复，见 [_detachPlayer]）。
  String? _lastUrl;
  Map<String, String> _lastHeaders = const {};

  static Future<HimiMpvAndroidSession> create({
    int width = 1920,
    int height = 1080,
    String hwdecMode = 'performance',
    bool nativeSurface = true,
    bool nativeUi = false,
    bool hdr = false,
    bool hlg = false,
  }) async {
    final session = HimiMpvAndroidSession._(
      width: width,
      height: height,
      hwdecMode: hwdecMode,
      nativeSurface: nativeSurface,
      nativeUi: nativeUi,
      hdr: hdr,
      hlg: hlg,
    );
    await session._start();
    return session;
  }

  static Future<MpvHdrCapabilities> queryHdrCapabilities() async {
    try {
      final raw = await _methods.invokeMapMethod<String, Object?>(
        'queryHdrCapabilities',
      );
      final formats = (raw?['formats'] as List<Object?>?) ?? const [];
      return MpvHdrCapabilities(
        hdr10: formats.contains('hdr10'),
        hlg: formats.contains('hlg'),
        displayHdr: formats.isNotEmpty,
      );
    } catch (e) {
      return MpvHdrCapabilities(error: '$e');
    }
  }

  @override
  int get textureId => _textureId;

  @override
  bool get usesNativeSurface => nativeSurface;

  /// HDR 实际状态本平台暂未单独上报，由适配器按输出策略推断。
  @override
  bool? get hdrOutputActive => null;

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  Future<void> _start() async {
    if (!nativeSurface) {
      await _ensurePlayer();
      return;
    }
    _surfaceSub = _surfaceEvents.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      final type = raw['type'];
      if (type == 'surface') {
        final handle = raw['handle'];
        if (handle is int && handle > 0) {
          _surfaceHandle = handle;
          unawaited(_ensurePlayer());
        }
      } else if (type == 'surfaceDestroyed') {
        _surfaceHandle = 0;
        unawaited(_detachPlayer());
      }
    });
    try {
      final current = await _methods.invokeMapMethod<String, dynamic>(
        'getCurrentSurface',
      );
      final handle = current?['handle'];
      if (handle is int && handle > 0) {
        _surfaceHandle = handle;
        await _ensurePlayer();
      }
    } catch (_) {}
  }

  Future<void> _detachPlayer() async {
    if (_disposed) return;
    final player = _player;
    _player = null;
    // Surface 重建（旋转 / 原生 UI 宿主重建）：记住当前播放点，等新
    // surface 到达后由 _ensurePlayer 用同一地址 + 当前位置重建，避免黑屏
    // 或从头播（计划书 §6.3「Surface handle 顺序与重建」）。
    final lastUrl = _lastUrl;
    if (lastUrl != null && lastUrl.isNotEmpty) {
      _pendingUrl = lastUrl;
      _pendingHeaders = _lastHeaders;
      _pendingStartMs = _positionMs > 0 ? _positionMs : _pendingStartMs;
      _pendingPause = _paused || _eof;
    }
    try {
      await player?.dispose();
    } catch (_) {}
  }

  Future<void> _ensurePlayer() async {
    if (_disposed || _player != null) return;
    if (nativeSurface && _surfaceHandle == 0) return;
    final options = <String, String>{
      if (nativeSurface) 'vo': 'gpu-next',
      'vid': 'auto',
      'aid': 'auto',
      'force-window': 'no',
      if (nativeSurface) 'wid': '$_surfaceHandle',
      // The stock Android libmpv build used by media_kit is built without
      // Vulkan (libplacebo HAVE_VULKAN=0). Use the EGL/GLES Android context;
      // the HDR data-space patch tags the native window as BT.2020 PQ/HLG.
      if (nativeSurface) 'gpu-api': 'opengl',
      if (nativeSurface) 'gpu-context': 'android',
      'hwdec': hwdecMode == 'software' ? 'no' : 'auto',
      'hwdec-software-fallback': 'yes',
      'cache': 'yes',
      'demuxer-max-bytes': '${256 * 1024 * 1024}',
      'demuxer-max-back-bytes': '${128 * 1024 * 1024}',
      'sub-ass': 'yes',
      'sub-visibility': 'yes',
      'osd-level': '0',
      'osc': 'no',
      if (hdr && nativeSurface) ...<String, String>{
        'target-colorspace-hint': 'yes',
        'target-prim': 'bt.2020',
        'target-trc': hlg ? 'hlg' : 'pq',
        'hdr-compute-peak': 'auto',
        'tone-mapping': 'clip',
      },
    };
    final player = Player(
      configuration: PlayerConfiguration(
        vo: nativeSurface ? 'gpu-next' : 'libmpv',
        wid: nativeSurface ? _surfaceHandle : null,
        options: options,
        libass: true,
        logLevel: MPVLogLevel.error,
      ),
    );
    _player = player;
    if (!nativeSurface) {
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: 'libmpv',
          hwdec: 'auto-copy',
          width: width,
          height: height,
        ),
      );
      _controller = controller;
      void updateTextureId() {
        final id = controller.id.value;
        if (id != null && id > 0 && id != _textureId) {
          _textureId = id;
          _emit('texture-id', id);
        }
      }

      _textureIdListener = updateTextureId;
      controller.id.addListener(updateTextureId);
      try {
        _textureId = await _waitForTextureId(controller);
      } catch (_) {
        rethrow;
      }
    }
    _wire(player);
    try {
      await (player.platform as dynamic)?.setProperty?.call('vid', 'auto');
      for (final entry in _pendingProperties.entries) {
        await (player.platform as dynamic)
            ?.setProperty
            ?.call(entry.key, entry.value);
      }
      _pendingProperties.clear();
      if (_pendingVolume != null) await player.setVolume(_pendingVolume!);
      if (_pendingSpeed != null) await player.setRate(_pendingSpeed!);
    } catch (_) {}
    final pending = _pendingUrl;
    if (pending != null && pending.isNotEmpty) {
      _pendingUrl = null;
      await _openNow(pending);
    }
  }

  Future<int> _waitForTextureId(VideoController controller) {
    final existing = controller.id.value;
    if (existing != null && existing > 0) return Future<int>.value(existing);
    final completer = Completer<int>();
    void listener() {
      final id = controller.id.value;
      if (id != null && id > 0 && !completer.isCompleted) {
        completer.complete(id);
      }
    }

    controller.id.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 10)).whenComplete(
          () => controller.id.removeListener(listener),
        );
  }

  void _wire(Player player) {
    _positionSub = player.stream.position.listen((d) {
      _positionMs = d.inMilliseconds;
      _emit('time-pos/full', _positionMs / 1000.0);
    });
    _durationSub = player.stream.duration.listen((d) {
      _durationMs = d.inMilliseconds;
      _emit('duration/full', _durationMs / 1000.0);
    });
    player.stream.buffer.listen((d) {
      _bufferedMs = d.inMilliseconds;
      _emit('demuxer-cache-time', _bufferedMs / 1000.0);
    });
    _playingSub = player.stream.playing.listen((playing) {
      _paused = !playing;
      _emit('pause', _paused);
    });
    _completedSub = player.stream.completed.listen((completed) {
      _eof = completed;
      _emit('eof-reached', completed);
    });
    player.stream.buffering.listen((b) {
      _emit('paused-for-cache', b);
    });
  }

  void _emit(String name, Object? value) {
    if (_disposed || _events.isClosed) return;
    _events.add(<Object?, Object?>{
      'type': 'property',
      'name': name,
      'value': value,
    });
  }

  Future<void> _openNow(String url) async {
    final player = _player;
    if (player == null) {
      _pendingUrl = url;
      return;
    }
    await (player.platform as dynamic)?.setProperty?.call('vid', 'auto');
    await player.open(
      Media(
        url,
        httpHeaders: _pendingHeaders,
        start: Duration(milliseconds: _pendingStartMs),
      ),
      play: !_pendingPause,
    );
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    int startMs = 0,
    bool pause = false,
  }) async {
    _lastUrl = url;
    _lastHeaders = headers;
    _pendingUrl = url;
    _pendingHeaders = headers;
    _pendingStartMs = startMs;
    _pendingPause = pause;
    if (_player != null) {
      _pendingUrl = null;
      await _openNow(url);
    }
  }

  @override
  Future<bool> isReady() async => _player != null;

  @override
  Future<void> kickStart() async {
    await _player?.play();
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> seek(int positionMs) async {
    await _player?.seek(Duration(milliseconds: positionMs));
  }

  @override
  Future<void> setVolume(double volume) async {
    _pendingVolume = (volume * 100).clamp(0, 100);
    await _player?.setVolume(_pendingVolume!);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _pendingSpeed = speed;
    await _player?.setRate(speed);
  }

  @override
  Future<void> setAudioTrack(int id) async {
    if (id <= 0) {
      await _player?.setAudioTrack(AudioTrack.no());
    } else {
      final tracks = _player?.state.tracks.audio ?? const <AudioTrack>[];
      if (id - 1 < tracks.length) {
        await _player?.setAudioTrack(tracks[id - 1]);
      }
    }
  }

  @override
  Future<void> setSubtitleTrack(int id) async {
    if (id <= 0) {
      await _player?.setSubtitleTrack(SubtitleTrack.no());
    } else {
      final tracks = _player?.state.tracks.subtitle ?? const <SubtitleTrack>[];
      if (id - 1 < tracks.length) {
        await _player?.setSubtitleTrack(tracks[id - 1]);
      }
    }
  }

  @override
  Future<void> addSubtitle(
    String url, {
    String title = 'external',
    String lang = 'auto',
  }) async {
    await _player?.setSubtitleTrack(
      SubtitleTrack.uri(url, title: title, language: lang),
    );
  }

  @override
  Future<void> setProperty(String name, Object value) async {
    _pendingProperties[name] = '$value';
    try {
      await (_player?.platform as dynamic)?.setProperty?.call(name, '$value');
    } catch (_) {}
  }

  @override
  Future<String?> getProperty(String name) async {
    try {
      final v = await (_player?.platform as dynamic)?.getProperty?.call(name);
      return v?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> resizeTexture(int width, int height) async {
    if (nativeSurface || width <= 0 || height <= 0) return;
    try {
      await _controller?.setSize(width: width, height: height);
    } catch (_) {}
  }

  @override
  Future<Uint8List?> screenshot() async {
    try {
      return await (_player?.platform as dynamic)?.screenshot?.call();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getTracks() async {
    final tracks = _player?.state.tracks;
    if (tracks == null) return null;
    return jsonEncode(<String, dynamic>{
      'video': tracks.video.map(_trackJson).toList(),
      'audio': tracks.audio.map(_trackJson).toList(),
      'subtitle': tracks.subtitle.map(_trackJson).toList(),
    });
  }

  Map<String, dynamic> _trackJson(dynamic track) => <String, dynamic>{
        'id': track.id,
        'title': track.title,
        'language': track.language,
        'codec': track.codec,
        'external': track.isExternal,
      };

  @override
  Future<String?> getVideoParams() async {
    final w = _player?.state.width;
    final h = _player?.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return jsonEncode(<String, dynamic>{'w': w, 'h': h});
  }

  @override
  Future<String?> getAudioParams() async => null;

  @override
  Future<MpvPollResult?> pollState() async {
    final player = _player;
    if (player == null) return null;
    final state = player.state;
    return MpvPollResult(
      durationMs: _durationMs,
      positionMs: _positionMs,
      bufferedMs: _bufferedMs,
      paused: _paused,
      eofReached: _eof || state.completed,
      idleActive: state.playlist.medias.isEmpty,
      playlistCount: state.playlist.medias.length,
      pausedForCache: state.buffering,
      cachePercent: state.bufferingPercentage,
      videoParams: await getVideoParams(),
      hwdecCurrent: await getProperty('hwdec-current'),
      gpuContext: await getProperty('gpu-context'),
      currentVo: await getProperty('current-vo'),
      mediaTitle: state.playlist.medias.isEmpty
          ? null
          : state.playlist.medias.first.uri,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final controller = _controller;
    final listener = _textureIdListener;
    if (controller != null && listener != null) {
      controller.id.removeListener(listener);
    }
    _controller = null;
    _textureIdListener = null;
    _textureId = 0;
    await _surfaceSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      await _methods.invokeMethod<void>('releaseSurface');
    } catch (_) {}
    await _events.close();
  }
}
