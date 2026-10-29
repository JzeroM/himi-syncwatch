import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'surface_rebind_policy.dart';

export 'himi_mpv_android_surface_view.dart';
export 'surface_rebind_policy.dart';

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
  static const SurfaceRebindPolicy _policy = SurfaceRebindPolicy();
  StreamSubscription<dynamic>? _surfaceSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<PlayerLog>? _logSub;

  Player? _player;
  VideoController? _controller;
  VoidCallback? _textureIdListener;
  int _surfaceHandle = 0;
  int _textureId = 0;
  bool _disposed = false;
  /// 原生播放器 UI 是否接管中（adapter 在 open 前/关闭后同步）。
  /// 决定 surface 事件来源过滤：接管中只认 `src=native`。
  bool _nativeUiActive = false;
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

  /// 诊断日志出口（adapter 注入 LogService；未注入时走 debugPrint）。
  static void Function(String message)? debugLog;

  static void _log(String message) {
    final sink = debugLog;
    if (sink != null) {
      sink(message);
    } else {
      debugPrint('[HimiMpvAndroid] $message');
    }
  }

  @override
  void setNativeUiActive(bool active) {
    if (_nativeUiActive == active) return;
    _nativeUiActive = active;
    _log('nativeUiActive=$active（surface 来源过滤切换）');
  }

  /// 主动重同步 surface：事件通道可能丢事件（宿主销毁不发回调 / 事件早于
  /// 监听），按 `getCurrentSurface` 轮询兜底。
  @override
  Future<void> refreshSurface() async {
    if (_disposed || !nativeSurface) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      if (_disposed) return;
      try {
        final current = await _methods.invokeMapMethod<String, dynamic>(
          'getCurrentSurface',
        );
        final handle = current?['handle'];
        final src = current?['src'] as String?;
        if (handle is int && handle > 0) {
          if (!_policy.accept(
              nativeUiActive: _nativeUiActive, eventSrc: src)) {
            // 当前来源还没有 surface（原生宿主窗口尚未完成创建）。
            _log('refreshSurface #$attempt: 跳过 src=$src '
                'handle=$handle（nativeUiActive=$_nativeUiActive）');
          } else if (handle != _surfaceHandle) {
            _log('refreshSurface #$attempt: 重同步 handle=$handle '
                '（原 $_surfaceHandle, src=$src）');
            _surfaceHandle = handle;
            unawaited(_player == null
                ? _ensurePlayer()
                : _rebindToSurface());
            return;
          } else {
            _log('refreshSurface #$attempt: 已同步 handle=$handle');
            if (_player == null) {
              unawaited(_ensurePlayer());
            }
            return;
          }
        }
      } catch (e) {
        _log('refreshSurface #$attempt 失败: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    _log('refreshSurface 超时：原生宿主未报出当前来源的 surface');
  }

  Future<void> _start() async {
    if (!nativeSurface) {
      await _ensurePlayer();
      return;
    }
    _surfaceSub = _surfaceEvents.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      final type = raw['type'];
      final handle = raw['handle'];
      final handleInt = handle is int ? handle : 0;
      final src = raw['src'] as String?;
      // 来源过滤：原生 UI 接管中只认 native，未接管只认 platform。
      // 垂死平台视图的 surfaceChanged 会把绑定抢回即将销毁的 handle，
      // 过滤掉就不会再搁浅（v1.5.4 安卓黑屏根因）。
      if (!_policy.accept(nativeUiActive: _nativeUiActive, eventSrc: src)) {
        _log('忽略过期来源事件: $type src=$src handle=$handleInt '
            '（nativeUiActive=$_nativeUiActive）');
        return;
      }
      if (type == 'surface') {
        final action = _policy.plan(
          currentHandle: _surfaceHandle,
          newHandle: handleInt,
          playerAlive: _player != null,
        );
        _log('surface 事件: src=$src handle=$handleInt current=$_surfaceHandle '
            'playerAlive=${_player != null} → ${action.name}');
        switch (action) {
          case SurfaceAction.ensurePlayer:
            _surfaceHandle = handleInt;
            unawaited(_ensurePlayer());
          case SurfaceAction.rebind:
            // surface 变化（原生 UI Dialog 抢占 / 旋转重建）：旧播放器绑在
            // 已销毁的 surface 上，必须重建到新 handle（计划书 §6.3）。
            _surfaceHandle = handleInt;
            unawaited(_rebindToSurface());
          case SurfaceAction.none:
          case SurfaceAction.detach:
            break;
        }
      } else if (type == 'surfaceDestroyed') {
        final action = _policy.onDestroyed(
          currentHandle: _surfaceHandle,
          destroyedHandle: handleInt,
          playerAlive: _player != null,
        );
        _log('surfaceDestroyed: src=$src handle=$handleInt '
            'current=$_surfaceHandle → ${action.name}');
        // 只处理当前绑定 surface 的销毁：原生 UI（Dialog）与 Flutter 平台
        // 视图各有自己的 SurfaceView，旧宿主销毁不能拆掉新 surface 的绑定
        // （否则表现为「解码正常但黑屏」）。
        if (action == SurfaceAction.detach) {
          _surfaceHandle = 0;
          unawaited(_detachPlayer());
        }
      }
    });
    try {
      final current = await _methods.invokeMapMethod<String, dynamic>(
        'getCurrentSurface',
      );
      final handle = current?['handle'];
      if (handle is int && handle > 0) {
        _surfaceHandle = handle;
        _log('初始 surface: handle=$handle src=${current?['src']}');
        await _ensurePlayer();
      }
    } catch (_) {}
  }

  Future<void> _detachPlayer() async {
    if (_disposed) return;
    final player = _player;
    _log('detachPlayer: handle=$_surfaceHandle');
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

  /// 换绑到新 surface：销毁绑在旧 surface 上的播放器，用同一地址 + 当前
  /// 播放点在新 handle 上重建（见 [_detachPlayer] 的恢复逻辑）。
  Future<void> _rebindToSurface() async {
    if (_disposed) return;
    await _detachPlayer();
    if (_disposed || _surfaceHandle == 0) return;
    await _ensurePlayer();
  }

  /// media_kit_video 原生 channel（与 AndroidVideoController 同一通道）。
  static const MethodChannel _videoOutChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  /// 主动踢纹理注册：调 `VideoOutputManager.SetSurfaceSize` 强制 native
  /// `onSurfaceAvailable()` → `VideoOutput.Resize` → `controller.id/wid`。
  /// 打破「vo=null 不产 video-params → 不 SetSurfaceSize → Resize 不触发 →
  /// wid 上不来 → vo 永远 null」的死锁。
  Future<void> _kickTextureSurface(Player player) async {
    try {
      final handle = await player.handle;
      await _videoOutChannel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
        'handle': '$handle',
        'width': '$width',
        'height': '$height',
      });
      _log('踢纹理注册: SetSurfaceSize handle=$handle ${width}x$height');
    } catch (e) {
      _log('踢纹理注册失败: $e');
    }
  }

  Future<void> _ensurePlayer() async {
    if (_disposed || _player != null) return;
    if (nativeSurface && _surfaceHandle == 0) return;
    _log('创建播放器: wid=$_surfaceHandle hwdec=$hwdecMode');
    final options = <String, String>{
      if (nativeSurface) 'vo': 'gpu-next',
      'vid': 'auto',
      'aid': 'auto',
      // force-window 仅 surface 模式设 no（显式 wid 已给窗口）；纹理模式
      // 由 AndroidVideoController 后置设 yes，此处若设 no 会与其冲突。
      if (nativeSurface) 'force-window': 'no',
      if (nativeSurface) 'wid': '$_surfaceHandle',
      // The stock Android libmpv build used by media_kit is built without
      // Vulkan (libplacebo HAVE_VULKAN=0). Use the EGL/GLES Android context;
      // the HDR data-space patch tags the native window as BT.2020 PQ/HLG.
      if (nativeSurface) 'gpu-api': 'opengl',
      if (nativeSurface) 'gpu-context': 'android',
      // 纹理模式（!nativeSurface）必须 copy-back 硬解：渲染纹理没有真实
      // Surface 给 MediaCodec 直写，`auto` 会先试零拷贝 → "Both surface and
      // native_window are NULL" → 首帧解码失败 → 上层弹「播放失败」。
      // copy-back 解到系统内存再上传 GPU。Surface 模式保留 auto（可直写）。
      'hwdec': !nativeSurface
          ? 'auto-copy'
          : (hwdecMode == 'software' ? 'no' : 'auto'),
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
        // Android 纹理模式必须 vo=gpu（media_kit AndroidVideoController 走
        // TextureRegistry Surface + wid + vo=gpu，非 libmpv 渲染 API）。
        // 传 libmpv 会让 native VideoOutputManager 的 VideoOutput.Resize
        // 事件永不触发 → texture id 恒 null → _waitForTextureId 10s 超时。
        vo: nativeSurface ? 'gpu-next' : 'gpu',
        wid: nativeSurface ? _surfaceHandle : null,
        options: options,
        libass: true,
        logLevel: MPVLogLevel.info,
      ),
    );
    _player = player;
    // 日志订阅必须在纹理等待之前：纹理路径若卡住/超时，也应有 mpv 日志
    // 可查（曾因订阅在等待之后，纹理失败时全程零 mpv 日志 → 盲调）。
    _wire(player);
    if (!nativeSurface) {
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          // 与上一致：Android 纹理走 gpu（wid），不走 libmpv。
          vo: 'gpu',
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
      // 主动踢：native onSurfaceAvailable（→VideoOutput.Resize→id/wid）原
      // 依赖 videoParams→SetSurfaceSize，而 vo=null 时 mpv 可能不产出
      // video-params → 死锁（id 恒 null、wid=0、vo 永远上不来）。这里在
      // 注册后直接 SetSurfaceSize 强制 surface 就绪，打破对 videoParams
      // 的时序依赖。
      unawaited(_kickTextureSurface(player));
      try {
        _textureId = await _waitForTextureId(controller);
      } catch (e) {
        // 纹理注册失败：带上已等时长与当前 id，便于下次定位（不应再出现
        // 「零日志 + 裸 TimeoutException」）。
        _log('纹理注册失败: $e（当前 id=${controller.id.value}）');
        rethrow;
      }
    }
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
    // 20s：4K HEVC + copy-back 首帧注册慢；超时前再复查一次，防错过瞬时
    // 注册（listener 可能晚于实际赋值一帧）。
    return completer.future.timeout(const Duration(seconds: 20)).whenComplete(() {
      controller.id.removeListener(listener);
      if (!completer.isCompleted) {
        final id = controller.id.value;
        if (id != null && id > 0) {
          _log('纹理注册超时前复查命中 id=$id');
        }
      }
    });
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
    // mpv 自身日志（logLevel=info 才有 [vd]/[vo]/[ffmpeg] 关键行）：
    // 黑屏定性全靠它——解码器选择、vo 初始化、EGL/surface 报错都在这里。
    // info 级别量可控（每秒个位数），直接进 LogService 落盘。
    _logSub = player.stream.log.listen((log) {
      if (_disposed) return;
      _log('mpv[${log.level}][${log.prefix}] ${log.text}');
    }, onError: (_) {});
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

  /// 数值属性直读（属性缺失/格式异常返回 null，不让轮询整体失败）。
  Future<double?> _readDouble(String name) async {
    final raw = await getProperty(name);
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<int?> _readInt(String name) async {
    final raw = await getProperty(name);
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw) ?? double.tryParse(raw)?.round();
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
      voConfigured: await getProperty('vo-configured'),
      // 黑屏定性三元组：直读 mpv 属性（media_kit state 曾失真）。
      videoFps: await _readDouble('estimated-vf-fps'),
      frameDropCount: await _readInt('frame-drop-count'),
      videoWidth: await _readInt('width'),
      videoHeight: await _readInt('height'),
      // Android 侧 wid 直接指向 SurfaceView 的 Java Surface 全局引用：
      // 播放器存在且有有效 handle 即视为已附着（诊断行靠它定位黑屏）。
      surfaceAttached: _player != null && _surfaceHandle > 0,
      surfaceId: _surfaceHandle > 0 ? '$_surfaceHandle' : null,
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
    await _logSub?.cancel();
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
