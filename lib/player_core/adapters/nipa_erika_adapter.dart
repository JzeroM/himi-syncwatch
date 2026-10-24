// ignore_for_file: unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../abstract_player.dart';
import '../player_data_models.dart';
import '../player_enums.dart';
import '../track_selection_queue.dart';

class _ErikaDanmakuConfigPatch {
  _ErikaDanmakuConfigPatch({
    this.enabled,
    this.fontSize,
    this.opacity,
    this.displayArea,
    this.scrollDurationSeconds,
    this.scrollSpeedFactor,
    this.trackGapRatio,
    this.outlineWidth,
    this.shadowStyle,
    this.customFontFamily,
    this.customFontFilePath,
    this.mergeDuplicates,
    this.allowStacking,
    this.maxQuantity,
    this.maxLinesPerMode,
    this.blockTop,
    this.blockBottom,
    this.blockScroll,
    List<String>? blockWords,
  }) : blockWords =
            blockWords == null ? null : List<String>.unmodifiable(blockWords);

  final bool? enabled;
  final double? fontSize;
  final double? opacity;
  final double? displayArea;
  final double? scrollDurationSeconds;
  final double? scrollSpeedFactor;
  final double? trackGapRatio;
  final double? outlineWidth;
  final int? shadowStyle;
  final String? customFontFamily;
  final String? customFontFilePath;
  final bool? mergeDuplicates;
  final bool? allowStacking;
  final int? maxQuantity;
  final int? maxLinesPerMode;
  final bool? blockTop;
  final bool? blockBottom;
  final bool? blockScroll;
  final List<String>? blockWords;

  bool get isEmpty =>
      enabled == null &&
      fontSize == null &&
      opacity == null &&
      displayArea == null &&
      scrollDurationSeconds == null &&
      scrollSpeedFactor == null &&
      trackGapRatio == null &&
      outlineWidth == null &&
      shadowStyle == null &&
      customFontFamily == null &&
      customFontFilePath == null &&
      mergeDuplicates == null &&
      allowStacking == null &&
      maxQuantity == null &&
      maxLinesPerMode == null &&
      blockTop == null &&
      blockBottom == null &&
      blockScroll == null &&
      blockWords == null;

  _ErikaDanmakuConfigPatch merge(_ErikaDanmakuConfigPatch other) {
    return _ErikaDanmakuConfigPatch(
      enabled: other.enabled ?? enabled,
      fontSize: other.fontSize ?? fontSize,
      opacity: other.opacity ?? opacity,
      displayArea: other.displayArea ?? displayArea,
      scrollDurationSeconds:
          other.scrollDurationSeconds ?? scrollDurationSeconds,
      scrollSpeedFactor: other.scrollSpeedFactor ?? scrollSpeedFactor,
      trackGapRatio: other.trackGapRatio ?? trackGapRatio,
      outlineWidth: other.outlineWidth ?? outlineWidth,
      shadowStyle: other.shadowStyle ?? shadowStyle,
      customFontFamily: other.customFontFamily ?? customFontFamily,
      customFontFilePath: other.customFontFilePath ?? customFontFilePath,
      mergeDuplicates: other.mergeDuplicates ?? mergeDuplicates,
      allowStacking: other.allowStacking ?? allowStacking,
      maxQuantity: other.maxQuantity ?? maxQuantity,
      maxLinesPerMode: other.maxLinesPerMode ?? maxLinesPerMode,
      blockTop: other.blockTop ?? blockTop,
      blockBottom: other.blockBottom ?? blockBottom,
      blockScroll: other.blockScroll ?? blockScroll,
      blockWords: other.blockWords ?? blockWords,
    );
  }

  _ErikaDanmakuConfigPatch differenceFrom(_ErikaDanmakuConfigPatch? previous) {
    return _ErikaDanmakuConfigPatch(
      enabled: _changed(enabled, previous?.enabled) ? enabled : null,
      fontSize: _changed(fontSize, previous?.fontSize) ? fontSize : null,
      opacity: _changed(opacity, previous?.opacity) ? opacity : null,
      displayArea:
          _changed(displayArea, previous?.displayArea) ? displayArea : null,
      scrollDurationSeconds:
          _changed(scrollDurationSeconds, previous?.scrollDurationSeconds)
              ? scrollDurationSeconds
              : null,
      scrollSpeedFactor:
          _changed(scrollSpeedFactor, previous?.scrollSpeedFactor)
              ? scrollSpeedFactor
              : null,
      trackGapRatio: _changed(trackGapRatio, previous?.trackGapRatio)
          ? trackGapRatio
          : null,
      outlineWidth:
          _changed(outlineWidth, previous?.outlineWidth) ? outlineWidth : null,
      shadowStyle:
          _changed(shadowStyle, previous?.shadowStyle) ? shadowStyle : null,
      customFontFamily: _changed(customFontFamily, previous?.customFontFamily)
          ? customFontFamily
          : null,
      customFontFilePath:
          _changed(customFontFilePath, previous?.customFontFilePath)
              ? customFontFilePath
              : null,
      mergeDuplicates: _changed(mergeDuplicates, previous?.mergeDuplicates)
          ? mergeDuplicates
          : null,
      allowStacking: _changed(allowStacking, previous?.allowStacking)
          ? allowStacking
          : null,
      maxQuantity:
          _changed(maxQuantity, previous?.maxQuantity) ? maxQuantity : null,
      maxLinesPerMode: _changed(maxLinesPerMode, previous?.maxLinesPerMode)
          ? maxLinesPerMode
          : null,
      blockTop: _changed(blockTop, previous?.blockTop) ? blockTop : null,
      blockBottom:
          _changed(blockBottom, previous?.blockBottom) ? blockBottom : null,
      blockScroll:
          _changed(blockScroll, previous?.blockScroll) ? blockScroll : null,
      blockWords:
          _changedList(blockWords, previous?.blockWords) ? blockWords : null,
    );
  }

  static bool _changed<T>(T? value, T? previous) =>
      value != null && value != previous;

  static bool _changedList(List<String>? value, List<String>? previous) =>
      value != null && !listEquals(value, previous);
}

bool get _erikaWindowOverlayTraceEnabled =>
    !kIsWeb && Platform.environment['ERIKA_WINDOW_OVERLAY_TRACE'] == '1';

class NipaErikaAdapter extends AbstractPlayer
    implements
        PlayerAsyncDisposable,
        PlayerAsyncSeek,
        PlayerAsyncExternalSubtitle,
        PlayerBufferingAware,
        PlayerEventSource,
        MediaStatusPlayer,
        NativeHandlePlayer,
        TextureSizePlayer,
        HttpHeadersPlayer,
        ColorSpacePlayer,
        AudioBackendsPlayer,
        RenderVideoPlayer,
        ErikaViewPlayer,
        ErikaDanmakuCapable,
        PlayerAsyncSetMedia {
  NipaErikaAdapter({
    PlayerErikaAndroidOutputMode androidOutputMode =
        PlayerErikaAndroidOutputMode.sdr,
  }) : _player = ErikaPlayer(
          outputMode: _resolveNativeOutputMode(androidOutputMode),
        ) {
    if (_isSupported) {
      _eventSubscription = _player.events.listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('ErikaPlayerAdapter event error: $error');
        },
      );
    }
  }

  final ErikaPlayer _player;

  @override
  Object get erikaPlayer => _player;

  final ValueNotifier<bool> _buffering = ValueNotifier<bool>(false);
  final _stateCtrl = StreamController<
      ({
        PlayerPlaybackState oldValue,
        PlayerPlaybackState newValue
      })>.broadcast();
  final _statusCtrl = StreamController<
      ({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>.broadcast();
  final _eventCtrl = StreamController<PlayerMediaEvent>.broadcast();
  Map<String, String> _httpHeaders = const {};

  @override
  ValueListenable<bool> get buffering => _buffering;
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: const <String>[],
    PlayerMediaType.audio: const <String>[],
    PlayerMediaType.subtitle: const <String>[],
    PlayerMediaType.unknown: const <String>[],
  };
  final Map<String, String> _properties = <String, String>{};

  StreamSubscription<ErikaPlayerEvent>? _eventSubscription;
  Future<void>? _disposeFuture;
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  bool _playRequested = false;
  bool _mediaReady = false;
  bool _ended = false;
  bool _errored = false;
  PlayerMediaStatus _lastStatus = PlayerMediaStatus.unloaded;
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  String _media = '';
  String _userAgent = '';
  double _volume = 1.0;
  double _playbackRate = 1.0;
  PlayerUpscalerStatus _lastUpscalerStatus = const PlayerUpscalerStatus.off();
  Map<String, dynamic> _lastPresenterStats = const <String, dynamic>{};
  Map<String, dynamic> _lastOutputStatus = const <String, dynamic>{};
  Map<String, dynamic> _lastDecoderStatus = const <String, dynamic>{};
  Map<String, dynamic> _lastAudioOutputStatus = const <String, dynamic>{};
  String? _lastNativeError;
  int _lastPositionMs = 0;
  DateTime _lastPositionUpdate = DateTime.now();
  int? _pendingSeekTargetMs;
  DateTime? _seekFenceUntil;
  bool _disposed = false;

  static const Duration _danmakuConfigCoalesceDelay = Duration(
    milliseconds: 50,
  );
  Timer? _danmakuConfigTimer;
  bool _danmakuConfigInFlight = false;
  _ErikaDanmakuConfigPatch? _pendingDanmakuConfig;
  _ErikaDanmakuConfigPatch? _lastAppliedDanmakuConfig;
  final List<Completer<void>> _pendingDanmakuConfigCompleters =
      <Completer<void>>[];

  // Real Erika track descriptors, kept so the UI's index-based
  // activeAudioTracks/activeSubtitleTracks can be mapped back to native ids.
  List<ErikaTrackInfo> _videoTrackInfos = const <ErikaTrackInfo>[];
  List<ErikaTrackInfo> _audioTrackInfos = const <ErikaTrackInfo>[];
  List<ErikaTrackInfo> _subtitleTrackInfos = const <ErikaTrackInfo>[];
  List<int> _activeAudioTracks = const <int>[];
  List<int> _activeSubtitleTracks = const <int>[];
  final PendingTrackSelection _pendingAudioSelection = PendingTrackSelection();
  final PendingTrackSelection _pendingSubtitleSelection =
      PendingTrackSelection();
  final Set<int> _externalSubtitleTrackIds = <int>{};
  int _externalSubtitleGeneration = 0;
  Future<void> _externalSubtitleOperation = Future<void>.value();

  static const bool _subtitleTraceEnabled = bool.fromEnvironment(
    'NIPAPLAY_ERIKA_SUBTITLE_TRACE',
  );

  static ErikaOutputMode? _resolveNativeOutputMode(
    PlayerErikaAndroidOutputMode mode,
  ) {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.linux &&
        linuxNativeSurfaceEnabled) {
      return ErikaOutputMode.auto;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    return switch (mode) {
      PlayerErikaAndroidOutputMode.sdr => ErikaOutputMode.sdr,
      PlayerErikaAndroidOutputMode.extendedLinearHdr =>
        ErikaOutputMode.extendedLinear,
    };
  }

  static bool get _isHarmonyOS =>
      !kIsWeb && defaultTargetPlatform.name == 'ohos';

  // Enabled by Linux builds that bundle the matching Erika native runtime.
  static const bool linuxBuildEnabled =
      bool.fromEnvironment('NIPAPLAY_LINUX_ERIKA');

  static bool get linuxNativeSurfaceEnabled =>
      linuxBuildEnabled &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux &&
      Platform.environment['ERIKA_LINUX_PRESENTATION'] != 'texture' &&
      Platform.environment['GDK_BACKEND']?.split(',').first.trim() != 'x11' &&
      (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ?? false);

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android ||
          (defaultTargetPlatform == TargetPlatform.linux &&
              linuxBuildEnabled) ||
          _isHarmonyOS);

  bool get prefersPlatformVideoSurface => _isSupported;

  bool get usesWindowOverlayVideoSurface =>
      _isSupported &&
      defaultTargetPlatform != TargetPlatform.android &&
      (defaultTargetPlatform != TargetPlatform.linux ||
          linuxNativeSurfaceEnabled) &&
      !_isHarmonyOS;

  @override
  double get volume => _volume;

  @override
  set volume(double value) {
    _volume = value.clamp(0.0, 1.0).toDouble();
    if (_isSupported) {
      unawaited(_player.setVolume(_volume));
    }
  }

  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    setPlaybackRate(value);
  }

  @override
  PlayerPlaybackState get state => _state;

  @override
  set state(PlayerPlaybackState value) {
    if (value == _state) {
      return;
    }
    final wasPlaying = _state == PlayerPlaybackState.playing;
    _playRequested = value == PlayerPlaybackState.playing;
    _emitState(value);
    switch (value) {
      case PlayerPlaybackState.playing:
        _dispatchStateCommand('play', playDirectly);
        break;
      case PlayerPlaybackState.paused:
        if (wasPlaying) {
          _dispatchStateCommand('pause', pauseDirectly);
        }
        break;
      case PlayerPlaybackState.stopped:
        _lastPositionMs = 0;
        _dispatchStateCommand('stop', _player.stop);
        break;
    }
  }

  void _emitState(PlayerPlaybackState next) {
    if (_state != next) {
      final old = _state;
      _state = next;
      _stateCtrl.add((oldValue: old, newValue: next));
    }
    _notifyStatus();
  }

  void _notifyStatus({bool force = false}) {
    final next = mediaStatus;
    if (!force && next.rawValue == _lastStatus.rawValue) return;
    final old = _lastStatus;
    _lastStatus = next;
    if (!_statusCtrl.isClosed) {
      _statusCtrl.add((oldValue: old, newValue: next));
    }
  }

  bool _isAtEndOfMedia() {
    final fence = _seekFenceUntil;
    return classifyEndOfMedia(
      positionMs: position,
      durationMs: _mediaInfo.duration,
      seekFenceActive: fence != null && DateTime.now().isBefore(fence),
    );
  }

  @visibleForTesting
  static bool classifyEndOfMedia({
    required int positionMs,
    required int durationMs,
    required bool seekFenceActive,
  }) {
    if (durationMs <= 0 || seekFenceActive) return false;
    return positionMs >= durationMs - 1000;
  }

  void _dispatchStateCommand(
    String operation,
    Future<void> Function() command,
  ) {
    unawaited(
      command().catchError((Object error, StackTrace stackTrace) {
        final message = '$operation failed: $error';
        _lastNativeError = message;
        debugPrint('[Erika] $message');
      }),
    );
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _media;

  @override
  set media(String value) {
    setMedia(value, PlayerMediaType.video);
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) {
    _activeSubtitleTracks = List<int>.from(value);
    _subtitleTrace(
      'activeSubtitleTracks set value=$value '
      'known=${_subtitleTrackInfos.map(_subtitleTrackLabel).join(', ')}',
    );
    if (!_isSupported) {
      return;
    }
    // Empty selection means "no subtitle".
    if (value.isEmpty) {
      _pendingSubtitleSelection.clear();
      unawaited(_selectSubtitleTrack(null, reason: 'activeSubtitleTracks=off'));
      return;
    }
    final index = value.first;
    if (index >= 0 && index < _subtitleTrackInfos.length) {
      _pendingSubtitleSelection.clear();
      unawaited(
        _selectSubtitleTrack(
          _subtitleTrackInfos[index].id,
          reason: 'activeSubtitleTracks index=$index',
        ),
      );
    } else {
      // 轨表尚未到达（Erika 打开媒体后异步回传）：暂存请求，待
      // trackList 事件刷新轨表后自动下发。轨表已就绪但不含该下标时同样
      // 保留，等待后续追加的外挂字幕轨。
      _pendingSubtitleSelection.request(value);
      _subtitleTrace(
        'activeSubtitleTracks deferred index=$index '
        'known_count=${_subtitleTrackInfos.length}',
      );
    }
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) {
    _activeAudioTracks = List<int>.from(value);
    if (!_isSupported) {
      return;
    }
    // Empty selection falls back to the first real audio track.
    if (value.isEmpty) {
      _pendingAudioSelection.clear();
      if (_audioTrackInfos.isNotEmpty) {
        unawaited(_player.selectAudioTrack(_audioTrackInfos.first.id));
      }
      return;
    }
    final index = value.first;
    if (index >= 0 && index < _audioTrackInfos.length) {
      _pendingAudioSelection.clear();
      unawaited(_player.selectAudioTrack(_audioTrackInfos[index].id));
    } else {
      // 轨表异步就绪前先暂存（切换内核等场景），trackList 到达后补发。
      _pendingAudioSelection.request(value);
      debugPrint(
        '[Erika] activeAudioTracks deferred index=$index '
        'known_count=${_audioTrackInfos.length}',
      );
    }
  }

  /// 轨表刷新后补发暂存的音轨/字幕选择。
  void _flushPendingTrackSelections() {
    final audioIndex = _pendingAudioSelection.takeReady(
      _audioTrackInfos.length,
    );
    if (audioIndex != null) {
      _activeAudioTracks = <int>[audioIndex];
      final id = _audioTrackInfos[audioIndex].id;
      debugPrint('[Erika] 补发音轨 index=$audioIndex id=$id');
      unawaited(_player.selectAudioTrack(id));
    }

    final subtitleIndex = _pendingSubtitleSelection.takeReady(
      _subtitleTrackInfos.length,
    );
    if (subtitleIndex != null) {
      _activeSubtitleTracks = <int>[subtitleIndex];
      final id = _subtitleTrackInfos[subtitleIndex].id;
      _subtitleTrace('补发字幕 index=$subtitleIndex id=$id');
      unawaited(
        _selectSubtitleTrack(id, reason: 'pending activeSubtitleTracks'),
      );
    }
  }

  @override
  int get position {
    if (_state != PlayerPlaybackState.playing || _buffering.value) {
      return _lastPositionMs;
    }
    final elapsedMs =
        DateTime.now().difference(_lastPositionUpdate).inMilliseconds;
    final estimated = _lastPositionMs + (elapsedMs * _playbackRate).round();
    final duration = _mediaInfo.duration;
    if (duration > 0 && estimated > duration) return duration;
    return estimated;
  }

  @override
  int get bufferedPosition => position;

  @override
  PlayerMediaStatus get mediaStatus => resolveMediaStatus(
        errored: _errored,
        ended: _ended,
        ready: _mediaReady,
        buffering: _buffering.value,
        state: _state,
      );

  @visibleForTesting
  static PlayerMediaStatus resolveMediaStatus({
    required bool errored,
    required bool ended,
    required bool ready,
    required bool buffering,
    required PlayerPlaybackState state,
  }) {
    if (errored && !ended) return PlayerMediaStatus.invalid;
    if (ended) {
      return ready
          ? PlayerMediaStatus.loaded | PlayerMediaStatus.end
          : PlayerMediaStatus.end;
    }
    if (buffering) return PlayerMediaStatus.buffering;
    if (state == PlayerPlaybackState.stopped) {
      return PlayerMediaStatus.unloaded;
    }
    if (ready) return PlayerMediaStatus.loaded;
    return switch (state) {
      PlayerPlaybackState.playing => PlayerMediaStatus.loading,
      PlayerPlaybackState.paused => PlayerMediaStatus.prepared,
      PlayerPlaybackState.stopped => PlayerMediaStatus.unloaded,
    };
  }

  @override
  int get nativeHandle => 0;

  @override
  Future<Size?> get textureSize async => null;

  @override
  void setHttpHeaders(Map<String, String> headers) {
    _httpHeaders = Map<String, String>.from(headers);
  }

  @override
  void setColorSpace(PlayerColorSpace colorSpace) {}

  @override
  set audioBackends(List<String> backends) {}

  @override
  void renderVideo() {}

  @override
  Future<void> setMediaAsync(String path, PlayerMediaType type) async {
    setMedia(path, type);
  }

  @override
  Stream<({PlayerPlaybackState oldValue, PlayerPlaybackState newValue})>
      get onStateChanged => _stateCtrl.stream;

  @override
  Stream<({PlayerMediaStatus oldValue, PlayerMediaStatus newValue})>
      get onMediaStatus => _statusCtrl.stream;

  @override
  Stream<PlayerMediaEvent> get onEvent => _eventCtrl.stream;

  @override
  Future<void> loadDanmakuJsonString(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is List) {
      await loadDanmakuList(
        decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
    }
  }

  @override
  Future<void> setDanmakuConfigHimi({
    double? fontSize,
    double? opacity,
    double? scrollDurationSeconds,
    double? displayArea,
    int? maxLinesPerMode,
    int? maxQuantity,
    bool? blockTop,
    bool? blockBottom,
    bool? blockScroll,
    List<String>? blockWords,
  }) =>
      setDanmakuConfig(
        fontSize: fontSize,
        opacity: opacity,
        scrollDurationSeconds: scrollDurationSeconds,
        displayArea: displayArea,
        maxLinesPerMode: maxLinesPerMode,
        maxQuantity: maxQuantity,
        blockTop: blockTop,
        blockBottom: blockBottom,
        blockScroll: blockScroll,
        blockWords: blockWords,
      );

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {}

  @override
  bool get supportsExternalSubtitles => _isSupported;

  @override
  Future<int?> updateTexture({int? width, int? height, bool? tunnel}) async =>
      null;

  @override
  void setMedia(String path, PlayerMediaType type) {
    if (type == PlayerMediaType.subtitle) {
      _subtitleTrace('setMedia subtitle path=${_describeSubtitlePath(path)}');
      _setExternalSubtitle(path);
      return;
    }
    if (type == PlayerMediaType.video || type == PlayerMediaType.unknown) {
      _subtitleTrace('setMedia video path=$path clears external tracks');
      _media = path;
      _lastPositionMs = 0;
      _lastPositionUpdate = DateTime.now();
      _buffering.value = false;
      _mediaReady = false;
      _ended = false;
      _errored = false;
      _lastStatus = PlayerMediaStatus.unloaded;
      _mediaInfo = PlayerMediaInfo(duration: 0);
      _notifyStatus(force: true);
      _lastPresenterStats = const <String, dynamic>{};
      _lastOutputStatus = const <String, dynamic>{};
      _lastDecoderStatus = const <String, dynamic>{};
      _properties.remove('decoder.video');
      _properties.remove('video.decoder');
      _lastAudioOutputStatus = const <String, dynamic>{};
      _lastNativeError = null;
      _externalSubtitleTrackIds.clear();
      _externalSubtitleGeneration++;
      // 新媒体的轨表由 trackList 事件重建；先清空旧表与待选请求，避免
      // 用上一媒体的轨下标误映射/误触发选轨。
      _videoTrackInfos = const <ErikaTrackInfo>[];
      _audioTrackInfos = const <ErikaTrackInfo>[];
      _subtitleTrackInfos = const <ErikaTrackInfo>[];
      _activeAudioTracks = const <int>[];
      _activeSubtitleTracks = const <int>[];
      _pendingAudioSelection.clear();
      _pendingSubtitleSelection.clear();
    }
  }

  @override
  Future<void> prepare({int startMs = 0}) async {
    _ensureSupported();
    if (_media.isEmpty) {
      return;
    }
    await _player.ensureCreated();
    final headers = <String, String>{
      ..._httpHeaders,
      if (_userAgent.isNotEmpty) 'User-Agent': _userAgent,
    };
    _ended = false;
    _errored = false;
    await _player.open(
      _media,
      httpHeaders: headers.isEmpty ? null : headers,
    );
    _subtitleTrace('prepare open complete media=$_media');
    _playRequested = false;
    _emitState(PlayerPlaybackState.paused);
    if (startMs > 0) {
      await _player.seek(Duration(milliseconds: startMs));
      _lastPositionMs = startMs;
      _lastPositionUpdate = DateTime.now();
    }
  }

  @override
  void seek({required int position}) {
    unawaited(
      seekAndWait(position: position).catchError(
        (Object error, StackTrace stackTrace) {
          _lastNativeError = 'seek failed: $error';
          debugPrint('[Erika] seek failed: $error');
        },
      ),
    );
  }

  @override
  Future<void> seekAndWait({required int position}) async {
    final clamped = position < 0 ? 0 : position;
    _ended = false;
    _errored = false;
    _lastPositionMs = clamped;
    _lastPositionUpdate = DateTime.now();
    _pendingSeekTargetMs = clamped;
    _seekFenceUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    await _player.seek(Duration(milliseconds: clamped));
    _notifyStatus(force: true);
  }

  @override
  void dispose() {
    unawaited(
      disposeAsync().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Erika: asynchronous dispose failed: $error');
      }),
    );
  }

  @override
  Future<void> disposeAsync() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    _pendingAudioSelection.clear();
    _pendingSubtitleSelection.clear();
    _buffering.dispose();
    _danmakuConfigTimer?.cancel();
    _danmakuConfigTimer = null;
    for (final completer in _pendingDanmakuConfigCompleters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _pendingDanmakuConfigCompleters.clear();
    _pendingDanmakuConfig = null;
    final eventSubscription = _eventSubscription;
    _eventSubscription = null;
    _textureIdNotifier.dispose();
    return _disposeFuture = _finishDispose(eventSubscription);
  }

  Future<void> _finishDispose(
    StreamSubscription<ErikaPlayerEvent>? eventSubscription,
  ) async {
    try {
      await eventSubscription?.cancel();
    } finally {
      await _player.dispose();
    }
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    if (!_isSupported) {
      return null;
    }
    try {
      final captureWidth = width > 0 ? width : null;
      final captureHeight = height > 0 ? height : null;
      final Uint8List? bytes = await _player.screenshot(
        width: captureWidth,
        height: captureHeight,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      if (captureWidth != null && captureHeight != null) {
        final expectedRgbaBytes = captureWidth * captureHeight * 4;
        if (bytes.length != expectedRgbaBytes) {
          debugPrint(
            'Erika: screenshot native capture unavailable '
            '(expected $expectedRgbaBytes RGBA bytes, got ${bytes.length})',
          );
          return null;
        }
      }
      final video = _mediaInfo.video;
      final codec =
          video != null && video.isNotEmpty ? video.first.codec : null;
      return PlayerFrame(
        width: width > 0 ? width : (codec?.width ?? 0),
        height: height > 0 ? height : (codec?.height ?? 0),
        bytes: bytes,
      );
    } catch (error) {
      debugPrint('Erika: screenshot failed: $error');
      return null;
    }
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    _decoders[type] = List<String>.from(decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) =>
      List<String>.from(_decoders[type] ?? const <String>[]);

  @override
  String? getProperty(String key) => _properties[key];

  @override
  void setProperty(String key, String value) {
    _properties[key] = value;
    if (!_isSupported || _disposed) {
      return;
    }
    switch (key) {
      case 'sub-scale':
        final scale = double.tryParse(value);
        if (scale != null && scale.isFinite) {
          unawaited(
            _player.setSubtitleScale(scale).catchError((Object error) {
              debugPrint('Erika: set subtitle scale failed: $error');
            }),
          );
        }
    }
  }

  @override
  void setUserAgent(String ua) {
    _userAgent = ua;
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {}

  @override
  Future<void> setChapter(int index) async {
    // Erika 内核不支持 MKV 章节标识。
  }

  @override
  Future<void> playDirectly() async {
    _ensureSupported();
    await _player.ensureCreated();
    _ended = false;
    _errored = false;
    await _player.play();
    _playRequested = false;
    _emitState(PlayerPlaybackState.playing);
    _lastPositionUpdate = DateTime.now();
  }

  @override
  Future<void> pauseDirectly() async {
    _ensureSupported();
    await _player.ensureCreated();
    _lastPositionMs = position;
    try {
      await _player.pause();
    } catch (error) {
      if (_state == PlayerPlaybackState.stopped) {
        debugPrint(
            '[Erika] pause ignored after native playback stopped: $error');
        return;
      }
      rethrow;
    }
    _playRequested = false;
    _emitState(PlayerPlaybackState.paused);
    _lastPositionUpdate = DateTime.now();
  }

  @override
  void setPlaybackRate(double rate) {
    _playbackRate = rate <= 0 ? 1.0 : rate;
    if (_isSupported) {
      unawaited(_player.setPlaybackRate(_playbackRate));
    }
  }

  void _setExternalSubtitle(String path) {
    if (!_isSupported || _disposed) {
      return;
    }
    unawaited(
      setExternalSubtitleAsync(path).catchError(
        (Object error, StackTrace stackTrace) {
          debugPrint('Erika: set external subtitle failed: $error');
        },
      ),
    );
  }

  @override
  Future<void> setExternalSubtitleAsync(String path) {
    if (!_isSupported || _disposed) {
      return Future<void>.value();
    }
    final generation = ++_externalSubtitleGeneration;
    final previousOperation = _externalSubtitleOperation;
    final operation = () async {
      try {
        await previousOperation;
      } catch (_) {
        // A failed replacement must not block a newer subtitle request.
      }
      await _replaceExternalSubtitle(path, generation);
    }();
    _externalSubtitleOperation = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> _replaceExternalSubtitle(String path, int generation) async {
    if (_disposed || generation != _externalSubtitleGeneration) return;
    final oldTrackIds = Set<int>.from(_externalSubtitleTrackIds);
    _subtitleTrace(
      'setExternalSubtitle generation=$generation '
      'path=${_describeSubtitlePath(path)} old_track_ids=$oldTrackIds',
    );

    for (final trackId in oldTrackIds) {
      await _player.removeSubtitleTrack(trackId);
      _externalSubtitleTrackIds.remove(trackId);
      if (_disposed || generation != _externalSubtitleGeneration) return;
    }

    if (path.trim().isEmpty) {
      _activeSubtitleTracks = const <int>[];
      await _player.selectSubtitleTrack(null);
      return;
    }

    final addWatch = Stopwatch()..start();
    _subtitleTrace(
      'addExternalSubtitle begin generation=$generation '
      'path=${_describeSubtitlePath(path)}',
    );
    final trackId = await _player.addExternalSubtitle(path);
    addWatch.stop();
    _subtitleTrace(
      'addExternalSubtitle ok generation=$generation track_id=$trackId '
      'elapsed_ms=${addWatch.elapsedMilliseconds}',
    );
    if (_disposed || generation != _externalSubtitleGeneration) {
      await _player.removeSubtitleTrack(trackId);
      _subtitleTrace(
        'addExternalSubtitle stale generation=$generation '
        'current=$_externalSubtitleGeneration removed track_id=$trackId',
      );
      return;
    }
    _externalSubtitleTrackIds.add(trackId);
    await _player.selectSubtitleTrack(trackId);
    if (_disposed || generation != _externalSubtitleGeneration) {
      await _player.removeSubtitleTrack(trackId);
      _externalSubtitleTrackIds.remove(trackId);
    }
  }

  Future<void> _selectSubtitleTrack(
    int? trackId, {
    required String reason,
  }) async {
    final watch = Stopwatch()..start();
    try {
      _subtitleTrace(
        'selectSubtitleTrack begin track_id=$trackId reason=$reason',
      );
      await _player.selectSubtitleTrack(trackId);
      watch.stop();
      _subtitleTrace(
        'selectSubtitleTrack ok track_id=$trackId '
        'elapsed_ms=${watch.elapsedMilliseconds} reason=$reason',
      );
    } catch (error) {
      watch.stop();
      debugPrint('Erika: select subtitle track failed: $error');
      _subtitleTrace(
        'selectSubtitleTrack failed track_id=$trackId '
        'elapsed_ms=${watch.elapsedMilliseconds} reason=$reason error=$error',
      );
    }
  }

  bool get supportsUpscaler => _isSupported;

  Future<void> setUpscaler(PlayerUpscalerMode mode) async {
    _lastUpscalerStatus = PlayerUpscalerStatus(
      requestedMode: mode,
      activeBackend: mode == PlayerUpscalerMode.off
          ? PlayerUpscalerBackendStatus.off
          : PlayerUpscalerBackendStatus.inactive,
      fallbackCount: _lastUpscalerStatus.fallbackCount,
      upscaledFrames: _lastUpscalerStatus.upscaledFrames,
      lastEncodeDuration: _lastUpscalerStatus.lastEncodeDuration,
      lastGpuDuration: _lastUpscalerStatus.lastGpuDuration,
    );
    if (!_isSupported) return;
    try {
      await _player.setUpscaler(_toNativeUpscalerMode(mode));
      _lastUpscalerStatus = await getUpscalerStatus();
    } catch (error) {
      debugPrint('Erika: set upscaler failed: $error');
    }
  }

  Future<PlayerUpscalerStatus> getUpscalerStatus() async {
    if (!_isSupported) {
      return _lastUpscalerStatus;
    }
    try {
      final status = await _player.getUpscalerStatus();
      _lastUpscalerStatus = _convertUpscalerStatus(status);
    } catch (error) {
      debugPrint('Erika: get upscaler status failed: $error');
    }
    return _lastUpscalerStatus;
  }

  @override
  void stepForward() {
    if (!_isSupported) return;
    const frameDuration = 42; // ~24fps
    final currentPos = position;
    seek(position: currentPos + frameDuration);
  }

  @override
  void stepBackward() {
    if (!_isSupported) return;
    const frameDuration = 42; // ~24fps
    final currentPos = position;
    seek(position: (currentPos - frameDuration).clamp(0, currentPos));
  }

  // ---- Erika native danmaku passthrough ----
  //
  // Erika composites danmaku into the video frame natively, so when the Erika
  // kernel is active NipaPlay feeds its danmaku list + settings here instead of
  // driving its own Flutter danmaku overlay. The list uses NipaPlay's standard
  // danmaku maps ({time, content, type, color, ...}); Erika's JSON parser
  // accepts that shape directly, so it is forwarded as-is.

  bool get supportsNativeDanmaku => _isSupported;

  Future<void> loadDanmakuList(List<Map<String, dynamic>> danmakuList) async {
    if (!_isSupported) {
      return;
    }
    await _player.loadDanmakuJson(jsonEncode(danmakuList));
  }

  Future<void> clearDanmaku() async {
    if (!_isSupported) {
      return;
    }
    await _player.clearDanmaku();
  }

  Future<void> setDanmakuEnabled(bool enabled) async {
    if (!_isSupported) {
      return;
    }
    await _player.setDanmakuEnabled(enabled);
  }

  Future<void> setDanmakuGlobalOffset(Duration offset) async {
    if (!_isSupported) {
      return;
    }
    await _player.setDanmakuGlobalOffset(offset);
  }

  /// Bridges NipaPlay's danmaku display settings onto Erika's DFM+ config.
  /// All arguments are optional; only the supplied ones are pushed down.
  Future<void> setDanmakuConfig({
    bool? enabled,
    double? fontSize,
    double? opacity,
    double? displayArea,
    double? scrollDurationSeconds,
    double? scrollSpeedFactor,
    double? trackGapRatio,
    double? outlineWidth,
    int? shadowStyle,
    String? customFontFamily,
    String? customFontFilePath,
    bool? mergeDuplicates,
    bool? allowStacking,
    int? maxQuantity,
    int? maxLinesPerMode,
    bool? blockTop,
    bool? blockBottom,
    bool? blockScroll,
    List<String>? blockWords,
  }) async {
    if (!_isSupported || _disposed) {
      return;
    }
    final patch = _ErikaDanmakuConfigPatch(
      enabled: enabled,
      fontSize: fontSize,
      opacity: opacity,
      displayArea: displayArea,
      scrollDurationSeconds: scrollDurationSeconds,
      scrollSpeedFactor: scrollSpeedFactor,
      trackGapRatio: trackGapRatio,
      outlineWidth: outlineWidth,
      shadowStyle: shadowStyle,
      customFontFamily: customFontFamily,
      customFontFilePath: customFontFilePath,
      mergeDuplicates: mergeDuplicates,
      allowStacking: allowStacking,
      maxQuantity: maxQuantity,
      maxLinesPerMode: maxLinesPerMode,
      blockTop: blockTop,
      blockBottom: blockBottom,
      blockScroll: blockScroll,
      blockWords: blockWords,
    );
    if (patch.isEmpty) {
      return;
    }

    final completer = Completer<void>();
    _pendingDanmakuConfig = _pendingDanmakuConfig?.merge(patch) ?? patch;
    _pendingDanmakuConfigCompleters.add(completer);
    _scheduleDanmakuConfigFlush();
    return completer.future;
  }

  void _scheduleDanmakuConfigFlush() {
    if (_disposed || _danmakuConfigInFlight || _danmakuConfigTimer != null) {
      return;
    }
    _danmakuConfigTimer = Timer(_danmakuConfigCoalesceDelay, () {
      _danmakuConfigTimer = null;
      unawaited(_flushDanmakuConfig());
    });
  }

  Future<void> _flushDanmakuConfig() async {
    if (_disposed || _danmakuConfigInFlight) {
      return;
    }

    final requestedPatch = _pendingDanmakuConfig;
    if (requestedPatch == null) {
      return;
    }
    final completers = List<Completer<void>>.from(
      _pendingDanmakuConfigCompleters,
    );
    _pendingDanmakuConfigCompleters.clear();
    _pendingDanmakuConfig = null;

    final outgoingPatch = requestedPatch.differenceFrom(
      _lastAppliedDanmakuConfig,
    );
    if (outgoingPatch.isEmpty) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      if (_pendingDanmakuConfig != null) {
        _scheduleDanmakuConfigFlush();
      }
      return;
    }

    _danmakuConfigInFlight = true;
    try {
      await _player.setDanmakuConfig(
        enabled: outgoingPatch.enabled,
        fontSize: outgoingPatch.fontSize,
        opacity: outgoingPatch.opacity,
        displayArea: outgoingPatch.displayArea,
        scrollDurationSeconds: outgoingPatch.scrollDurationSeconds,
        scrollSpeedFactor: outgoingPatch.scrollSpeedFactor,
        trackGapRatio: outgoingPatch.trackGapRatio,
        outlineWidth: outgoingPatch.outlineWidth,
        shadowStyle: outgoingPatch.shadowStyle,
        customFontFamily: outgoingPatch.customFontFamily,
        customFontFilePath: outgoingPatch.customFontFilePath,
        mergeDuplicates: outgoingPatch.mergeDuplicates,
        allowStacking: outgoingPatch.allowStacking,
        maxQuantity: outgoingPatch.maxQuantity,
        maxLinesPerMode: outgoingPatch.maxLinesPerMode,
        blockTop: outgoingPatch.blockTop,
        blockBottom: outgoingPatch.blockBottom,
        blockScroll: outgoingPatch.blockScroll,
        blockWords: outgoingPatch.blockWords,
      );
      _lastAppliedDanmakuConfig =
          _lastAppliedDanmakuConfig?.merge(requestedPatch) ?? requestedPatch;
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    } catch (error, stackTrace) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    } finally {
      _danmakuConfigInFlight = false;
      if (_pendingDanmakuConfig != null) {
        _scheduleDanmakuConfigFlush();
      }
    }
  }

  Map<String, dynamic> getDetailedMediaInfo() {
    return <String, dynamic>{
      'kernel': 'Erika',
      'state': _state.name,
      'position': position,
      'duration': _mediaInfo.duration,
      'upscaler': _lastUpscalerStatus.toMap(),
      'presenterStats': _lastPresenterStats,
      'outputStatus': _lastOutputStatus,
      'decoder': _lastDecoderStatus,
      'audioOutput': _lastAudioOutputStatus,
      if (_lastNativeError != null) 'lastError': _lastNativeError,
      'tracks': <String, dynamic>{
        'video': _videoTrackInfos.map(_erikaTrackToDebugMap).toList(),
        'audio': _audioTrackInfos.map(_erikaTrackToDebugMap).toList(),
        'subtitle': _subtitleTrackInfos.map(_erikaTrackToDebugMap).toList(),
      },
      'videoWidth': _mediaInfo.video?.isNotEmpty == true
          ? _mediaInfo.video!.first.codec.width
          : null,
      'videoHeight': _mediaInfo.video?.isNotEmpty == true
          ? _mediaInfo.video!.first.codec.height
          : null,
    };
  }

  Future<Map<String, dynamic>> getDetailedMediaInfoAsync() async {
    await getUpscalerStatus();
    await _refreshPresenterStats();
    return getDetailedMediaInfo();
  }

  Future<void> _refreshPresenterStats() async {
    if (!_isSupported) {
      return;
    }
    try {
      final stats = await _player.getPresenterStats();
      _lastPresenterStats = Map<String, dynamic>.from(stats.toMap());
    } catch (error) {
      debugPrint('Erika: get presenter stats failed: $error');
    }
    try {
      final output = await _player.getOutputStatus();
      _lastOutputStatus = _outputStatusToMap(output);
    } catch (error) {
      debugPrint('Erika: get output status failed: $error');
    }
  }

  static Map<String, dynamic> _outputStatusToMap(ErikaOutputStatus status) {
    return <String, dynamic>{
      'requestedMode': status.requestedMode.name,
      'activeEncoding': status.activeEncoding.name,
      'surfaceFormat': status.surfaceFormat.name,
      'nativeDataSpace': status.nativeDataSpace,
      'requestedHeadroom': status.requestedHeadroom,
      'activeHeadroom': status.activeHeadroom,
      'activeHeadroomKnown': status.activeHeadroomKnown,
      'extendedLinearActive': status.extendedLinearActive,
      'fallbackReason': status.fallbackReason.label,
      'fallbackCount': status.fallbackCount,
      'dataSpaceFailures': status.dataSpaceFailures,
      'headroomUpdates': status.headroomUpdates,
      'extendedLinearFrames': status.extendedLinearFrames,
    };
  }

  ErikaUpscalerMode _toNativeUpscalerMode(PlayerUpscalerMode mode) {
    switch (mode) {
      case PlayerUpscalerMode.erikaArtCnnC4F16:
        return ErikaUpscalerMode.artCnnC4F16;
      case PlayerUpscalerMode.erikaArtCnnC4F32:
        return ErikaUpscalerMode.artCnnC4F32;
      case PlayerUpscalerMode.erikaArtCnnC4F16Ds:
        return ErikaUpscalerMode.artCnnC4F16Ds;
      case PlayerUpscalerMode.off:
        return ErikaUpscalerMode.off;
    }
  }

  PlayerUpscalerMode _fromNativeUpscalerMode(ErikaUpscalerMode mode) {
    switch (mode) {
      case ErikaUpscalerMode.artCnnC4F16:
        return PlayerUpscalerMode.erikaArtCnnC4F16;
      case ErikaUpscalerMode.artCnnC4F32:
        return PlayerUpscalerMode.erikaArtCnnC4F32;
      case ErikaUpscalerMode.artCnnC4F16Ds:
        return PlayerUpscalerMode.erikaArtCnnC4F16Ds;
      case ErikaUpscalerMode.off:
        return PlayerUpscalerMode.off;
    }
  }

  PlayerUpscalerBackendStatus _fromNativeUpscalerBackend(
    ErikaUpscalerBackendStatus status,
  ) {
    switch (status) {
      case ErikaUpscalerBackendStatus.off:
        return PlayerUpscalerBackendStatus.off;
      case ErikaUpscalerBackendStatus.inactive:
        return PlayerUpscalerBackendStatus.inactive;
      case ErikaUpscalerBackendStatus.building:
        return PlayerUpscalerBackendStatus.building;
      case ErikaUpscalerBackendStatus.scalar:
        return PlayerUpscalerBackendStatus.scalar;
      case ErikaUpscalerBackendStatus.simdgroupMatrix:
        return PlayerUpscalerBackendStatus.simdgroupMatrix;
    }
  }

  PlayerUpscalerStatus _convertUpscalerStatus(ErikaUpscalerStatus status) {
    return PlayerUpscalerStatus(
      requestedMode: _fromNativeUpscalerMode(status.requestedMode),
      activeBackend: _fromNativeUpscalerBackend(status.activeBackend),
      fallbackCount: status.fallbackCount,
      upscaledFrames: status.upscaledFrames,
      lastEncodeDuration: status.lastEncodeDuration,
      lastGpuDuration: status.lastGpuDuration,
    );
  }

  void _handleEvent(ErikaPlayerEvent event) {
    if (_disposed) {
      return;
    }
    if (event.kind == ErikaEventKind.bufferingChanged) {
      // BufferingChanged is a sparse event: its position field defaults to 0.
      // Freeze the current anchor on entry, then reuse the latest real
      // PositionChanged sample on recovery without extrapolating the wait.
      if (event.buffering) {
        _lastPositionMs = position;
      }
      _lastPositionUpdate = DateTime.now();
      _buffering.value = event.buffering;
    }
    if (event.kind == ErikaEventKind.error) {
      final errorMessage = _formatPlaybackError(event);
      _lastNativeError = errorMessage;
      _mediaInfo = _mediaInfo.copyWith(specificErrorMessage: errorMessage);
      debugPrint(
        '[Erika] playback error '
        'player=${event.playerId} state=${event.state.name} '
        'status=${event.status} error=${event.error ?? '-'} '
        'message=${event.message ?? '-'}',
      );
    }

    final decoder = event.decoder;
    if (event.kind == ErikaEventKind.videoDecoderChanged && decoder != null) {
      final decoderName = switch (decoder.activeBackend) {
        'cuda' => 'CUDA / NVDEC',
        'vaapi' => 'VA-API',
        'software' => 'FFmpeg (software)',
        final backend => backend,
      };
      _properties['decoder.video'] = decoderName;
      _properties['video.decoder'] = decoderName;
      _lastDecoderStatus = <String, dynamic>{
        'stage': decoder.stage,
        'requestedBackend': decoder.requestedBackend,
        'previousBackend': decoder.previousBackend,
        'activeBackend': decoder.activeBackend,
        'fallbackCount': decoder.fallbackCount,
        'codec': decoder.codec,
        'pixelFormat': decoder.pixelFormat,
        'lineSizes': decoder.lineSizes,
        'reason': decoder.reason,
      };
      debugPrint(
        '[Erika] video decoder changed '
        'stage=${decoder.stage} requested=${decoder.requestedBackend} '
        'previous=${decoder.previousBackend ?? '-'} '
        'active=${decoder.activeBackend} fallbacks=${decoder.fallbackCount} '
        'codec=${decoder.codec ?? '-'} format=${decoder.pixelFormat ?? '-'} '
        'reason=${decoder.reason ?? '-'}',
      );
    }

    final audio = event.audio;
    if (event.kind == ErikaEventKind.audioOutputChanged && audio != null) {
      _lastAudioOutputStatus = <String, dynamic>{
        'recoveryState': audio.recoveryState,
        'lastErrorCode': audio.lastErrorCode,
        'recoveryAttempts': audio.recoveryAttempts,
        'recoveryCount': audio.recoveryCount,
        'recoveryFailures': audio.recoveryFailures,
        'transitionSequence': audio.transitionSequence,
      };
      debugPrint(
        '[Erika] audio output changed '
        'state=${audio.recoveryState} errorCode=${audio.lastErrorCode} '
        'attempts=${audio.recoveryAttempts} recoveries=${audio.recoveryCount} '
        'failures=${audio.recoveryFailures} '
        'sequence=${audio.transitionSequence}',
      );
    }

    if (event.kind == ErikaEventKind.stateChanged ||
        event.kind == ErikaEventKind.error) {
      final atEnd = _isAtEndOfMedia();
      final isError = event.kind == ErikaEventKind.error;
      if (isError) {
        if (atEnd) {
          _ended = true;
          _errored = false;
        } else {
          _ended = false;
          _errored = true;
        }
      } else if (event.state == ErikaPlaybackState.playing) {
        _ended = false;
        _errored = false;
      } else if (atEnd &&
          (event.state == ErikaPlaybackState.stopped ||
              event.state == ErikaPlaybackState.closed ||
              event.state == ErikaPlaybackState.idle ||
              event.state == ErikaPlaybackState.error)) {
        _ended = true;
        _errored = false;
      }

      final PlayerPlaybackState nextState;
      switch (event.state) {
        case ErikaPlaybackState.playing:
          nextState = PlayerPlaybackState.playing;
          break;
        case ErikaPlaybackState.paused:
        case ErikaPlaybackState.ready:
        case ErikaPlaybackState.opening:
          nextState = PlayerPlaybackState.paused;
          break;
        case ErikaPlaybackState.stopped:
        case ErikaPlaybackState.closed:
        case ErikaPlaybackState.idle:
        case ErikaPlaybackState.error:
          nextState = PlayerPlaybackState.stopped;
          break;
      }
      if (nextState == PlayerPlaybackState.playing) {
        _playRequested = false;
        _emitState(nextState);
      } else if (nextState == PlayerPlaybackState.paused) {
        if (!_playRequested) _emitState(nextState);
      } else {
        _playRequested = false;
        _emitState(nextState);
      }
      if (isError && !_ended) {
        _eventCtrl.add(PlayerMediaEvent(
          event.status,
          'erika.error',
          _formatPlaybackError(event),
        ));
      }
    }

    if (event.kind == ErikaEventKind.positionChanged &&
        event.position >= Duration.zero) {
      final eventPositionMs = event.position.inMilliseconds;
      final now = DateTime.now();
      final seekTarget = _pendingSeekTargetMs;
      final fenceUntil = _seekFenceUntil;
      if (seekTarget != null &&
          fenceUntil != null &&
          now.isBefore(fenceUntil)) {
        final distance = (eventPositionMs - seekTarget).abs();
        if (distance > 1500) {
          return;
        }
        _pendingSeekTargetMs = null;
        _seekFenceUntil = null;
      } else if (fenceUntil != null && !now.isBefore(fenceUntil)) {
        _pendingSeekTargetMs = null;
        _seekFenceUntil = null;
      }
      _lastPositionMs = eventPositionMs;
      _lastPositionUpdate = now;
      if (_ended &&
          (_mediaInfo.duration <= 0 ||
              eventPositionMs < _mediaInfo.duration - 1000)) {
        _ended = false;
        _notifyStatus(force: true);
      }
    }

    var updatedInfo = _mediaInfo;
    var durationChanged = false;
    if (event.duration > Duration.zero) {
      durationChanged = updatedInfo.duration != event.duration.inMilliseconds;
      updatedInfo = updatedInfo.copyWith(
        duration: event.duration.inMilliseconds,
      );
      _mediaReady = true;
    }
    if (event.video.width > 0 && event.video.height > 0) {
      _mediaReady = true;
      updatedInfo = updatedInfo.copyWith(
        video: <PlayerVideoStreamInfo>[
          PlayerVideoStreamInfo(
            codec: PlayerVideoCodecParams(
              width: event.video.width,
              height: event.video.height,
              name: 'Erika Video',
            ),
            codecName: 'unknown',
          ),
        ],
      );
    }
    // Erika emits the full descriptor list (with native ids, titles and the
    // selected flag) on TracksChanged/TrackSelectionChanged. Use it to build
    // mediaInfo so the UI's index-based track selection maps to real ids.
    if (event.trackList.isNotEmpty) {
      _mediaReady = true;
      final videoInfos = event.trackList
          .where((t) => t.kind == ErikaTrackKind.video)
          .toList(growable: false);
      final audioInfos = event.trackList
          .where((t) => t.kind == ErikaTrackKind.audio)
          .toList(growable: false);
      final subtitleInfos = event.trackList
          .where((t) => t.kind == ErikaTrackKind.subtitle)
          .toList(growable: false);
      _subtitleTrace(
        'event trackList kind=${event.kind} '
        'subtitles=${subtitleInfos.map(_subtitleTrackLabel).join(', ')}',
      );
      _audioTrackInfos = audioInfos;
      _videoTrackInfos = videoInfos;
      _subtitleTrackInfos = subtitleInfos;
      updatedInfo = updatedInfo.copyWith(
        video: videoInfos.isEmpty
            ? null
            : <PlayerVideoStreamInfo>[
                for (var i = 0; i < videoInfos.length; i++)
                  PlayerVideoStreamInfo(
                    codec: PlayerVideoCodecParams(
                      width: videoInfos[i].width > 0
                          ? videoInfos[i].width
                          : event.video.width,
                      height: videoInfos[i].height > 0
                          ? videoInfos[i].height
                          : event.video.height,
                      name: _formatErikaVideoCodecParams(videoInfos[i]),
                    ),
                    codecName: videoInfos[i].codec ?? 'unknown',
                  ),
              ],
        audio: <PlayerAudioStreamInfo>[
          for (var i = 0; i < audioInfos.length; i++)
            PlayerAudioStreamInfo(
              codec: PlayerAudioCodecParams(
                name: audioInfos[i].codec ?? 'unknown',
                channels:
                    audioInfos[i].channels > 0 ? audioInfos[i].channels : null,
                sampleRate: audioInfos[i].sampleRate > 0
                    ? audioInfos[i].sampleRate
                    : null,
              ),
              title: audioInfos[i].title ?? 'Audio ${i + 1}',
              language: audioInfos[i].language,
              metadata: <String, String>{
                'id': '${audioInfos[i].id}',
                if (audioInfos[i].sampleFormat != null)
                  'sampleFormat': audioInfos[i].sampleFormat!,
              },
              rawRepresentation: 'Erika Audio ${i + 1}',
            ),
        ],
        subtitle: <PlayerSubtitleStreamInfo>[
          for (var i = 0; i < subtitleInfos.length; i++)
            PlayerSubtitleStreamInfo(
              title: subtitleInfos[i].title ?? 'Subtitle ${i + 1}',
              language: subtitleInfos[i].language,
              metadata: <String, String>{'id': '${subtitleInfos[i].id}'},
              rawRepresentation: 'Erika Subtitle ${i + 1}',
            ),
        ],
      );
      _activeAudioTracks = <int>[
        for (var i = 0; i < audioInfos.length; i++)
          if (audioInfos[i].selected) i,
      ];
      _activeSubtitleTracks = <int>[
        for (var i = 0; i < subtitleInfos.length; i++)
          if (subtitleInfos[i].selected) i,
      ];
      _subtitleTrace(
        'event activeSubtitleTracks=$_activeSubtitleTracks '
        'external_track_ids=$_externalSubtitleTrackIds',
      );
      _flushPendingTrackSelections();
    }
    _mediaInfo = updatedInfo;
    if (durationChanged) {
      _notifyStatus(force: true);
    } else if (_mediaReady) {
      _notifyStatus();
    }
  }

  static String _formatPlaybackError(ErikaPlayerEvent event) {
    final error = event.error?.trim();
    final message = event.message?.trim();
    final details = <String>[
      if (error != null && error.isNotEmpty) error,
      if (message != null && message.isNotEmpty && message != error) message,
      if (event.status != 0) 'status=${event.status}',
    ];
    return details.isEmpty
        ? 'Erika 播放失败（未返回详细原因）'
        : 'Erika 播放失败：${details.join('；')}';
  }

  static String _formatErikaVideoCodecParams(ErikaTrackInfo track) {
    final parts = <String>[
      if (track.codec != null) 'codec: ${track.codec}',
      if (track.profile != null) 'profile: ${track.profile}',
      if (track.level > 0) 'level: ${track.level}',
      if (track.width > 0 && track.height > 0) '${track.width}x${track.height}',
      if (track.pixelFormat != null) 'format: ${track.pixelFormat}',
    ];
    return parts.isEmpty ? 'Erika Video' : parts.join(', ');
  }

  static Map<String, dynamic> _erikaTrackToDebugMap(ErikaTrackInfo track) {
    return <String, dynamic>{
      'id': track.id,
      'kind': track.kind.name,
      'source': track.source.name,
      'selected': track.selected,
      'canRemove': track.canRemove,
      if (track.title != null) 'title': track.title,
      if (track.language != null) 'language': track.language,
      if (track.codec != null) 'codec': track.codec,
      if (track.width > 0) 'width': track.width,
      if (track.height > 0) 'height': track.height,
      if (track.sampleRate > 0) 'sampleRate': track.sampleRate,
      if (track.channels > 0) 'channels': track.channels,
      if (track.pixelFormat != null) 'pixelFormat': track.pixelFormat,
      if (track.sampleFormat != null) 'sampleFormat': track.sampleFormat,
      if (track.profile != null) 'profile': track.profile,
      if (track.level > 0) 'level': track.level,
    };
  }

  static void _subtitleTrace(String message) {
    if (_subtitleTraceEnabled) {
      debugPrint('[nipa-erika-subtitle-trace] $message');
    }
  }

  static String _subtitleTrackLabel(ErikaTrackInfo track) {
    return '{id=${track.id}, source=${track.source.name}, '
        'selected=${track.selected}, canRemove=${track.canRemove}, '
        'title=${track.title}, lang=${track.language}, codec=${track.codec}}';
  }

  static String _describeSubtitlePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '<empty>';
    }
    try {
      final file = File(trimmed);
      final stat = file.statSync();
      return '$trimmed exists=${stat.type != FileSystemEntityType.notFound} '
          'size=${stat.size} modified=${stat.modified.toIso8601String()}';
    } catch (error) {
      return '$trimmed stat_error=$error';
    }
  }

  void _ensureSupported() {
    if (!_isSupported) {
      throw UnsupportedError(
        'Erika requires a supported platform and a matching native plugin.',
      );
    }
  }
}
