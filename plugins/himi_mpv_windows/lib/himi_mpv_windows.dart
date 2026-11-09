import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'src/windows_mpv_log.dart';

export 'himi_mpv_windows_surface_view.dart';

/// Windows MPV 初始化 options。
///
/// `vid`/`aid` 必须在 `mpv_initialize` 前显式设为 auto：media_kit 默认
/// 写入 `vid=no`，初始化后再改用 dynamic setProperty 存在失败可能，表现为
/// Player 创建成功但没有 video-params。
Map<String, String> buildWindowsMpvOptions({
  required bool hdr,
  required bool hlg,
}) =>
    <String, String>{
      'vo': 'gpu-next',
      'vid': 'auto',
      'aid': 'auto',
      'force-window': 'no',
      'gpu-api': 'd3d11',
      'gpu-context': 'd3d11',
      'd3d11-output-mode': 'window',
      'd3d11-output-format': hdr ? 'rgb10_a2' : 'auto',
      'd3d11-output-csp': 'auto',
      'gpu-hwdec-interop': 'auto',
      'hwdec': 'auto-copy',
      'hwdec-software-fallback': 'yes',
      'cache': 'yes',
      'cache-on-disk': 'no',
      'msg-level':
          'all=warn,vo/gpu-next=v,vo/gpu-next/d3d11=debug,gpu=debug,vd=debug,ao=debug,ao/wasapi=debug,af=debug,cplayer=debug',
      'demuxer-max-bytes': '${256 * 1024 * 1024}',
      'demuxer-max-back-bytes': '${128 * 1024 * 1024}',
      'sub-ass': 'yes',
      'sub-visibility': 'yes',
      'osd-level': '0',
      'osc': 'no',
      if (hdr) ...<String, String>{
        'target-colorspace-hint': 'yes',
        'target-prim': 'bt.2020',
        'target-trc': hlg ? 'hlg' : 'pq',
        'hdr-compute-peak': 'auto',
        'tone-mapping': 'clip',
      },
    };

/// Windows MPV 纹理输出 options。
///
/// 使用 media_kit_video 的 render API 把 libmpv 画面注册成 Flutter 纹理，
/// 避免 Windows 原生子 HWND 被 Flutter 不透明窗口遮挡。HDR 内容在此路径
/// 由 mpv 色调映射到 SDR；原生 HDR 直出仍保留在 [buildWindowsMpvOptions]。
Map<String, String> buildWindowsMpvTextureOptions({
  required bool hdr,
  required bool hlg,
}) =>
    <String, String>{
      'vid': 'auto',
      'aid': 'auto',
      'hwdec': 'auto-copy',
      'hwdec-software-fallback': 'yes',
      'cache': 'yes',
      'cache-on-disk': 'no',
      'msg-level':
          'all=warn,vo=debug,gpu=debug,vd=debug,ao=debug,ao/wasapi=debug,af=debug,cplayer=debug',
      'demuxer-max-bytes': '${256 * 1024 * 1024}',
      'demuxer-max-back-bytes': '${128 * 1024 * 1024}',
      'sub-ass': 'yes',
      'sub-visibility': 'yes',
      'osd-level': '0',
      'osc': 'no',
      if (hdr) ...<String, String>{
        'target-colorspace-hint': 'no',
      },
    };

String _redactUrls(String text) {
  return text.replaceAllMapped(RegExp(r'https?://[^\s"\\]+'), (match) {
    final raw = match.group(0)!;
    final uri = Uri.tryParse(raw);
    if (uri == null) return '<url:${raw.length}>';
    return '${uri.scheme}://${uri.host}/...?len=${raw.length}';
  });
}

String redactWindowsMpvLog(String text) {
  var safe = _redactUrls(text);
  safe = safe.replaceAllMapped(
    RegExp(
      r'(X-Emby-Token|Authorization|api_key|token)(\s*[:=]\s*)(?:Bearer\s+)?([^\s",\]]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}${match.group(2)}<redacted>',
  );
  return safe;
}

void _log(String message) {
  final safe = redactWindowsMpvLog(message);
  WindowsMpvLog.write('session', safe);
  MpvLog.log('windows', safe);
}

const Set<String> _allowedOptionOverrides = <String>{
  'vo',
  'hwdec',
  'gpu-api',
  'gpu-context',
  'd3d11-output-mode',
  'd3d11-output-format',
  'd3d11-output-csp',
  'gpu-hwdec-interop',
  'target-colorspace-hint',
  'target-colorspace-hint-mode',
  'target-prim',
  'target-trc',
  'hdr-compute-peak',
  'tone-mapping',
  'ao',
  'audio-exclusive',
  'audio-device',
};

/// 解析 `%TEMP%\\himi_mpv_windows_options.ini` 内容。
///
/// 只接受白名单键，忽略注释、空行和空值，便于在真机上逐项隔离
/// D3D11/WASAPI 问题而无需重新构建。
Map<String, String> parseWindowsMpvOptionOverrides(Iterable<String> lines) {
  final result = <String, String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    final split = line.indexOf('=');
    if (split <= 0) continue;
    final key = line.substring(0, split).trim();
    final value = line.substring(split + 1).trim();
    if (_allowedOptionOverrides.contains(key) && value.isNotEmpty) {
      result[key] = value;
    }
  }
  return result;
}

Map<String, String> _loadOptionOverrides() {
  try {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'himi_mpv_windows_options.ini',
    );
    if (!file.existsSync()) return <String, String>{};
    return parseWindowsMpvOptionOverrides(file.readAsLinesSync());
  } catch (_) {
    return <String, String>{};
  }
}

/// Windows MPV 会话：原生插件创建子 HWND，libmpv 通过 `wid` 直出。
class HimiMpvWindowsSession implements MpvSession, MpvHostWindowSession {
  HimiMpvWindowsSession._({
    required this.width,
    required this.height,
    required this.hwdecMode,
    required this.nativeSurface,
    required this.hdr,
    required this.hlg,
    this.nativeUi = false,
  });

  static const MethodChannel _methods = MethodChannel('himi_mpv_windows');
  static const EventChannel _surfaceEvents =
      EventChannel('himi_mpv_windows/surface');

  final int width;
  final int height;
  final String hwdecMode;
  final bool nativeSurface;
  final bool hdr;
  final bool hlg;

  /// 646：是否走**原生顶层窗口**（Windows HDR 直出）。
  ///
  /// true 时插件创建独立 `WS_POPUP` 顶层窗口，MPV 用 `vo=gpu-next` +
  /// `wid` 渲染进去（真 HDR 直出）；Flutter 播放页视频层退场。
  /// false 时沿用旧的子 HWND / Flutter 纹理路径。
  final bool nativeUi;

  final StreamController<Map<Object?, Object?>> _events =
      StreamController<Map<Object?, Object?>>.broadcast();

  /// 648：原生窗口事件（关闭/按键/点击）——独立窗口独占焦点，Flutter
  /// 收不到这些输入，必须由原生转发。
  final StreamController<Map<Object?, Object?>> _hostEvents =
      StreamController<Map<Object?, Object?>>.broadcast();

  /// 648：原生窗口事件流。
  @override
  Stream<Map<Object?, Object?>> get hostEvents => _hostEvents.stream;

  StreamSubscription<dynamic>? _surfaceSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<PlayerLog>? _logSub;
  StreamSubscription<String>? _errorSub;
  Timer? _diagTimer;
  bool _diagInFlight = false;

  Player? _player;
  VideoController? _controller;
  VoidCallback? _textureIdListener;
  int _surfaceHandle = 0;
  int _textureId = 0;
  Map<String, String> _optionOverrides = const <String, String>{};
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

  static Future<HimiMpvWindowsSession> create({
    int width = 1920,
    int height = 1080,
    String hwdecMode = 'performance',
    bool nativeSurface = true,
    bool hdr = false,
    bool hlg = false,
    bool nativeUi = false,
  }) async {
    final session = HimiMpvWindowsSession._(
      width: width,
      height: height,
      hwdecMode: hwdecMode,
      // 646：nativeUi 模式下强制走原生 surface（顶层窗口渲染）。
      nativeSurface: nativeUi ? true : nativeSurface,
      hdr: hdr,
      hlg: hlg,
      nativeUi: nativeUi,
    );
    await session._start();
    return session;
  }

  /// 649：聚焦已有原生独立窗口（详情页重复点播放时用）。
  ///
  /// 返回 true 表示窗口已存在并被置前；false 表示尚未创建。
  static Future<bool> focusHostWindow() async {
    try {
      final ok = await _methods.invokeMethod<bool>('focusHostWindow');
      return ok ?? false;
    } catch (_) {
      return false;
    }
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
  bool get usesNativeSurface => nativeSurface && _textureId == 0;

  /// HDR 实际状态本平台暂未单独上报，由适配器按输出策略推断。
  @override
  bool? get hdrOutputActive => null;

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  Future<void> _start() async {
    _optionOverrides = _loadOptionOverrides();
    _log('session start overrides=$_optionOverrides nativeUi=$nativeUi');
    // 646：原生顶层窗口模式。
    //
    // 创建 WS_POPUP 顶层窗口 + 渲染子窗口，用渲染子窗口的 HWND 作为
    // mpv 的 `wid` → `vo=gpu-next` 直出到该窗口（真 HDR）。
    // 不走 Flutter 纹理（那条路必崩：flutter_windows.dll 0x1551f）。
    if (nativeUi) {
      try {
        // 648：独立标准窗口——不再依赖 Flutter 几何，给固定初始尺寸，
        // 由用户自由拖动/缩放/最大化。
        final host = await _methods.invokeMethod<int>('createHostWindow', {
          'x': 0,
          'y': 0,
          'width': width,
          'height': height,
        });
        final render = await _methods.invokeMethod<int>('createRenderSurface');
        _log('nativeUi host=$host render=$render');
        // 648：监听原生窗口事件（关闭/按键/点击），转发给 Dart 层。
        _surfaceSub ??= _surfaceEvents.receiveBroadcastStream().listen((raw) {
          if (raw is! Map) return;
          final type = raw['type'];
          if (type is String) {
            _hostEvents.add(<Object?, Object?>{'type': type});
          }
        });
        if (render != null && render > 0) {
          _surfaceHandle = render;
          await _ensurePlayer();
          return;
        }
      } catch (e) {
        _log('nativeUi create failed: $e');
      }
      return;
    }
    if (!nativeSurface) {
      await _ensurePlayer();
      return;
    }
    _surfaceSub = _surfaceEvents.receiveBroadcastStream().listen((raw) {
      if (raw is! Map) return;
      if (raw['type'] == 'surface') {
        final handle = raw['handle'];
        if (handle is int && handle > 0) {
          _surfaceHandle = handle;
          _log('surface event handle=$handle');
          unawaited(_ensurePlayer());
        }
      } else if (raw['type'] == 'surfaceDestroyed') {
        _surfaceHandle = 0;
        _log('surface destroyed');
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
        _log('getCurrentSurface handle=$handle');
        await _ensurePlayer();
      } else {
        _log('getCurrentSurface empty');
      }
    } catch (_) {}
  }

  Future<void> _detachPlayer() async {
    final player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (_) {}
  }

  Future<void> _ensurePlayer() async {
    if (_disposed || _player != null) return;
    if (nativeSurface && _surfaceHandle == 0) return;
    _log('creating Player hwnd=$_surfaceHandle hdr=$hdr '
        'native=$nativeSurface');
    final options = <String, String>{
      ...(nativeSurface
          ? buildWindowsMpvOptions(hdr: hdr, hlg: hlg)
          : buildWindowsMpvTextureOptions(hdr: hdr, hlg: hlg)),
      ..._optionOverrides,
    };
    _log('init options=$options');
    final player = Player(
      configuration: PlayerConfiguration(
        vo: nativeSurface ? (_optionOverrides['vo'] ?? 'gpu-next') : 'libmpv',
        wid: nativeSurface ? _surfaceHandle : null,
        options: options,
        libass: true,
        logLevel: MPVLogLevel.debug,
        // 【631 真机回归：Windows 从 MPV 切引擎「点击即闪退」】
        //
        // 618 曾设 `async: false` 追求切轨速度，但那是**同步 FFI**：
        //   mpv_set_property_string(ctx, ...) / mpv_command(ctx, ...)
        // 直接解引用 `ctx`，**没有有效性检查**。
        //
        // 而 media_kit 的 `Player.dispose()` 内部顺序是：
        //   NativeReferenceHolder.remove(ctx) → stop() → 才置 disposed = true
        // 也就是说 `stop()` 执行时 `disposed` 仍是 false，同步 `mpv_command`
        // 会真的往 `ctx` 里写；一旦与释放竞态（切换引擎时 `_disposeOldEngine`
        // 只有 2s 超时，超时后继续建新引擎，旧 session 仍在后台销毁），
        // 就会访问已释放内存 → 段错误（Dart 层 try/catch 抓不到）。
        //
        // 回退默认 `async: true`：命令走 `mpv_command_async` **入队**，由
        // libmpv 内部串行处理，dispose 时安全。切轨加速仍由
        // `_selectTrackNoLock`（跳过 media_kit 全局 static Lock）承担。
        //
        // Android 保持 `async: false`（未观察到同类崩溃）。
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
        if (id == null || id <= 0 || id == _textureId) return;
        _textureId = id;
        _log('texture id=$_textureId');
        _emit('texture-id', id);
      }

      _textureIdListener = updateTextureId;
      controller.id.addListener(updateTextureId);
      try {
        _textureId = await _waitForTextureId(controller);
        _log('texture id=$_textureId');
      } catch (e) {
        _log('texture init failed: $e');
        rethrow;
      }
    }
    _log('Player created');
    _wire(player);
    _startDiagnostics();
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
      for (final name in const [
        'vo',
        'gpu-api',
        'gpu-context',
        'current-vo',
        'cache-on-disk',
        'hwdec',
        'ao',
      ]) {
        try {
          _log('mpv $name=${await getProperty(name)}');
        } catch (_) {}
      }
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

  void _startDiagnostics() {
    _diagTimer?.cancel();
    var ticks = 0;
    _diagTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_disposed || _diagInFlight || _player == null) return;
      ticks++;
      if (ticks > 40) {
        _diagTimer?.cancel();
        _diagTimer = null;
        return;
      }
      _diagInFlight = true;
      try {
        final values = <String, String?>{};
        for (final name in const [
          'idle-active',
          'core-idle',
          'pause',
          'vid',
          'path',
          'playlist-count',
          'current-vo',
          'vo-configured',
          'video-format',
          'video-params',
          'hwdec-current',
          'track-list',
          'ao',
          'audio-device',
          'audio-codec-name',
          'audio-out-params',
        ]) {
          final value = await getProperty(name);
          if (name == 'path' || name == 'media-title') {
            values[name] = _maskUrl(value);
          } else {
            values[name] = _clip(_redactUrls(value ?? ''));
          }
        }
        _log('diag t=${ticks * 500}ms $values');
      } catch (e) {
        _log('diag failed: $e');
      } finally {
        _diagInFlight = false;
      }
    });
  }

  static String? _clip(String? value) {
    if (value == null) return null;
    if (value.length <= 800) return value;
    return '${value.substring(0, 800)}...(${value.length})';
  }

  static String _maskUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null) return '<len=${raw.length}>';
    return '${uri.scheme}://${uri.host}?len=${raw.length}';
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
    player.stream.buffering.listen((b) => _emit('paused-for-cache', b));
    _logSub = player.stream.log.listen((entry) {
      _log('mpv log [${entry.prefix}/${entry.level}] ${entry.text}');
    });
    _errorSub = player.stream.error.listen((error) {
      _log('mpv error $error');
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
    _log('open ${_maskUrl(url)} hwnd=$_surfaceHandle');
    final player = _player;
    if (player == null) {
      _pendingUrl = url;
      return;
    }
    await (player.platform as dynamic)?.setProperty?.call('vid', 'auto');
    _log('open: calling media_kit open');
    await player.open(
      Media(
        url,
        httpHeaders: _pendingHeaders,
        start: Duration(milliseconds: _pendingStartMs),
      ),
      play: !_pendingPause,
    );
    _log('open: returned');
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    int startMs = 0,
    bool pause = false,
  }) async {
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
    _log('kickStart');
    await _player?.play();
  }

  @override
  Future<void> play() async {
    _log('play called');
    try {
      await _player?.play();
      _log('play returned');
    } catch (e) {
      _log('play failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    _log('pause called');
    await _player?.pause();
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> seek(int positionMs) async {
    _log('seek positionMs=$positionMs');
    try {
      await _player?.seek(Duration(milliseconds: positionMs));
      _log('seek returned');
    } catch (e) {
      _log('seek failed: $e');
      rethrow;
    }
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

  /// media_kit 的 `state.tracks.*` **前置 `[auto, no]` 两条伪轨**（id 分别是
  /// `'auto'` / `'no'`）。617：与安卓同源的缺陷——旧实现直接 `tracks[id-1]`，
  /// 选第 1 条会落到 `auto`（mpv 自选）、第 2 条落到 `no`（关闭），与面板
  /// 显示完全不一致。跳过伪轨后按 Emby 流顺序取。
  static bool _isRealTrack(dynamic track) {
    final id = track?.id;
    return id != 'auto' && id != 'no';
  }

  List<AudioTrack> _realAudioTracks() =>
      (_player?.state.tracks.audio ?? const <AudioTrack>[])
          .where(_isRealTrack)
          .toList(growable: false);

  List<SubtitleTrack> _realSubtitleTracks() =>
      (_player?.state.tracks.subtitle ?? const <SubtitleTrack>[])
          .where(_isRealTrack)
          .toList(growable: false);

  /// 选轨直调 `platform` 并跳过 media_kit 的全局锁（618，与安卓同修）。
  Future<void> _selectTrackNoLock(
    Future<void> Function(dynamic platform) apply,
  ) async {
    final platform = _player?.platform as dynamic;
    if (platform == null) return;
    try {
      await apply(platform);
    } catch (e) {
      _log('选轨直调失败: $e');
    }
  }

  @override
  Future<void> setAudioTrack(int id) async {
    if (id <= 0) {
      await _selectTrackNoLock(
        (p) => p.setAudioTrack(AudioTrack.no(), synchronized: false),
      );
      return;
    }
    // 617：`id` 可能是真实 mpv track id（映射命中）或 1-based Emby 序号
    //（轨道表未就绪的兜底）。先按真实 id 精确匹配，再按序号兜底。
    final real = _realAudioTracks();
    final byTrackId =
        real.where((t) => int.tryParse(t.id) == id).firstOrNull;
    final track = byTrackId ??
        (id - 1 < real.length ? real[id - 1] : null);
    if (track == null) return;
    await _selectTrackNoLock(
      (p) => p.setAudioTrack(track, synchronized: false),
    );
  }

  @override
  Future<void> setSubtitleTrack(int id) async {
    if (id <= 0) {
      await _selectTrackNoLock(
        (p) => p.setSubtitleTrack(SubtitleTrack.no(), synchronized: false),
      );
      return;
    }
    // 语义同 setAudioTrack：真实 track id 优先、1-based 序号兜底。
    final real = _realSubtitleTracks();
    final byTrackId =
        real.where((t) => int.tryParse(t.id) == id).firstOrNull;
    final track = byTrackId ??
        (id - 1 < real.length ? real[id - 1] : null);
    if (track == null) return;
    await _selectTrackNoLock(
      (p) => p.setSubtitleTrack(track, synchronized: false),
    );
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
    var effective = '$value';
    final override = _optionOverrides[name];
    if (override != null) {
      effective = override;
    }
    _pendingProperties[name] = effective;
    try {
      await (_player?.platform as dynamic)?.setProperty?.call(name, effective);
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

  Map<String, dynamic> _trackJson(dynamic track) => <String, dynamic>{
        'id': track.id,
        'title': track.title,
        'language': track.language,
        'codec': track.codec,
        'external': track.isExternal,
      };

  @override
  Future<String?> getTracks() async {
    final tracks = _player?.state.tracks;
    if (tracks == null) return null;
    // 617：剔除 media_kit 前置的 auto/no 伪轨（与安卓同修）。
    return jsonEncode(<String, dynamic>{
      'video': tracks.video.where(_isRealTrack).map(_trackJson).toList(),
      'audio': tracks.audio.where(_isRealTrack).map(_trackJson).toList(),
      'subtitle': tracks.subtitle.where(_isRealTrack).map(_trackJson).toList(),
    });
  }

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
    // 621：统一位置数据源（与安卓同修）——旧实现读会话缓存字段，而它由
    // 异步 Stream 写入、又异步 emit 给 Dart，两条路径时序不同步会让
    // Dart 侧位置横跳 → 弹幕重锚 → 跳动。改为直读 mpv 实时属性。
    final rawPos = await getProperty('time-pos');
    final parsedPos = rawPos == null ? null : double.tryParse(rawPos);
    final positionMs = parsedPos != null && parsedPos >= 0
        ? (parsedPos * 1000).round()
        : _positionMs;
    return MpvPollResult(
      durationMs: _durationMs,
      positionMs: positionMs,
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
  void setNativeUiActive(bool active) {}

  @override
  Future<void> refreshSurface() async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _log('dispose session begin');
    _diagTimer?.cancel();
    _diagTimer = null;
    await _surfaceSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _completedSub?.cancel();
    await _logSub?.cancel();
    await _errorSub?.cancel();
    final controller = _controller;
    final textureIdListener = _textureIdListener;
    if (controller != null && textureIdListener != null) {
      controller.id.removeListener(textureIdListener);
    }
    _controller = null;
    _textureIdListener = null;
    // 639：VideoController 没有公开 dispose()——它通过
    // `player.platform?.release` 回调在 Player.dispose 时自动释放 mpv
    // render context（见 media_kit_video 的 video_controller.dart）。
    // 因此这里只需确保 player.dispose() 一定被调用且**先于** destroySurface。
    try {
      await _player?.dispose();
    } catch (e) {
      _log('player dispose failed: $e');
    }
    _player = null;
    _textureId = 0;
    // player 已释放后才允许销毁 HWND，避免 libmpv 继续访问已销毁窗口。
    if (nativeUi) {
      // 646：顶层窗口（含渲染子窗口）一并销毁。
      try {
        await _methods.invokeMethod<void>('destroyHostWindow');
      } catch (e) {
        _log('destroyHostWindow failed: $e');
      }
    } else {
      try {
        await _methods.invokeMethod<void>('destroySurface');
      } catch (e) {
        _log('destroySurface failed: $e');
      }
    }
    _log('dispose session end');
    await _hostEvents.close();
    await _events.close();
  }

  /// 646：同步顶层窗口位置/尺寸（播放页几何变化时调用）。
  ///
  /// 顶层窗口不在 Flutter 布局树里，必须由 Dart 侧显式驱动几何，
  /// 否则窗口会停在初始位置（拖动/缩放/全屏时错位）。
  @override
  Future<void> updateHostGeometry({
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    if (!nativeUi || _disposed) return;
    try {
      await _methods.invokeMethod<void>('updateHostWindow', {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
    } catch (e) {
      _log('updateHostWindow failed: $e');
    }
  }
}
