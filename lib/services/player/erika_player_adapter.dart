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
class ErikaPlayerAdapter implements PlayerAdapter, AsyncDisposablePlayer {
  ErikaPlayerAdapter({this.outputMode = ErikaOutputMode.auto}) {
    _erikaPlayer = ErikaPlayer(outputMode: outputMode);
    _subscribe();
  }

  /// 构造期输出模式（内容路由决定；用于重建判断）。
  final ErikaOutputMode outputMode;

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
  bool _errored = false;

  /// 播完标记（EOS）：Erika 在 EOF 会以 `stateChanged→stopped` 或
  /// `error` 事件收尾，且从不产生 `end` 位。位置≈时长时置位，使
  /// [_mapStatus] 上报 [AdapterMediaStatus.end]（上层据此自动下一集），
  /// 而非落回 unloaded/invalid（后者会误弹「播放出错，正在重试」）。
  bool _ended = false;

  /// 字幕样式覆盖位：Erika 需置 `overrideMask` 才会把字段推到带自身样式的字幕上
  /// （ASS）；纯文本(SRT)本即以回退样式生效。位图(PGS)不适用。
  static const int _subtitleOverrideMask = kErikaSubtitleOverrideMargins |
      kErikaSubtitleOverrideFontSizeFields |
      kErikaSubtitleOverrideBorder;

  /// 字幕样式下发合并：拖拽滑杆时避免每 tick 一次 channel 调用。
  double? _pendingSubScale;
  int? _pendingSubMarginY;
  double? _pendingSubFontSize;
  double? _pendingSubOutline;
  Timer? _subStyleTimer;

  /// seek 栅栏：忽略 seek 途中迟到的旧 position 事件（与目标距离 >1.5s）。
  int? _pendingSeekTargetMs;
  DateTime? _seekFenceUntil;

  List<ErikaTrackInfo> _audioTracks = const [];
  List<ErikaTrackInfo> _subtitleTracks = const [];
  List<ErikaTrackInfo> _videoTracks = const [];

  String? _mediaUri;
  Map<String, String> _httpHeaders = const {};
  bool _disposed = false;

  /// 触发即弃的原生命令：吞掉错误（旧引擎释放后命令仍可能迟到送达）。
  void _fire(Future<void> Function() op) {
    if (_disposed) return;
    unawaited(op().catchError((Object e) {
      LogService().log('Erika', '命令失败(已忽略): $e');
    }));
  }

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

    // buffering：仅该事件有效（其余事件默认 false）。
    if (e.kind == ErikaEventKind.bufferingChanged) {
      if (e.buffering != _buffering) {
        LogService().log('Erika', 'buffering=${e.buffering}');
      }
      _buffering = e.buffering;
    }

    // 轨表：仅 tracksChanged/trackSelectionChanged（或首帧轨表仍空）时重建。
    // Android 快照会在每个事件携带 trackList，逐事件重建会造成无谓分配/GC 抖动。
    final needTracks = e.trackList.isNotEmpty &&
        (e.kind == ErikaEventKind.tracksChanged ||
            e.kind == ErikaEventKind.trackSelectionChanged ||
            (_videoTracks.isEmpty &&
                _audioTracks.isEmpty &&
                _subtitleTracks.isEmpty));
    if (needTracks) {
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

    // 状态：**仅** stateChanged/error 事件有效。其余事件 state 缺省为 idle
    // （索引 0）→ 若逐事件套用会被打回 stopped，导致播放/暂停控件与弹幕
    // 播放态反复抖动。
    if (appliesStateKind(e.kind)) {
      final ns = _mapState(e.state);
      final atEnd = _isAtEndOfMedia();
      if (e.kind == ErikaEventKind.error) {
        // Erika 在 EOF 以 error 事件收尾：位置已到结尾 → 判为播完，
        // 不置错误位（否则 invalid → 上层弹「播放出错，正在重试」且不切集）。
        if (atEnd) {
          _ended = true;
          _errored = false;
        } else {
          _errored = true;
        }
      } else {
        _errored = false;
        // stateChanged→stopped 且位置≈时长：同样判为播完（有些平台不报 error）。
        if (atEnd && ns == AdapterPlaybackState.stopped) {
          _ended = true;
        }
      }
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
    }

    final st = _mapStatus();
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
    // 正常推进（远离结尾）→ 清除播完标记（重播/seek 回退后恢复）。
    if (_ended && (_durationMs <= 0 || ms < _durationMs - 1000)) {
      _ended = false;
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

  /// 位置是否到达结尾窗口（EOS 判定用）。
  bool _isAtEndOfMedia() {
    final fence = _seekFenceUntil;
    return classifyEndOfMedia(
      positionMs: position,
      durationMs: _durationMs,
      seekFenceActive: fence != null && DateTime.now().isBefore(fence),
    );
  }

  /// EOS 判定（纯函数，供测试）：位置进入结尾窗口即视为播完。
  ///
  /// duration 未就绪或处于 seek 栅栏期时返回 false（视为普通事件/错误）。
  /// 阈值 1000ms：Erika 最后一个 position 采样通常略早于时长。
  @visibleForTesting
  static bool classifyEndOfMedia({
    required int positionMs,
    required int durationMs,
    required bool seekFenceActive,
  }) {
    if (durationMs <= 0 || seekFenceActive) return false;
    return positionMs >= durationMs - 1000;
  }

  AdapterMediaStatus _mapStatus() => resolveStatus(
        errored: _errored,
        ended: _ended,
        state: _state,
        buffering: _buffering,
        durationMs: _durationMs,
      );

  /// 状态位解析（纯函数，供测试）：`errored` 优先于 `ended`。
  @visibleForTesting
  static AdapterMediaStatus resolveStatus({
    required bool errored,
    required bool ended,
    required AdapterPlaybackState state,
    required bool buffering,
    required int durationMs,
  }) {
    if (errored) return AdapterMediaStatus.invalid;
    if (ended) return AdapterMediaStatus.end;
    if (state == AdapterPlaybackState.stopped) {
      return AdapterMediaStatus.unloaded;
    }
    if (buffering) return AdapterMediaStatus.buffering;
    if (durationMs > 0) return AdapterMediaStatus.loaded;
    return AdapterMediaStatus.loading;
  }

  // ── 播放控制 ──────────────────────────────────────────────

  @override
  AdapterPlaybackState get state => _state;

  @override
  set state(AdapterPlaybackState value) {
    switch (value) {
      case AdapterPlaybackState.playing:
        _ended = false;
        _fire(() => _erikaPlayer.play());
      case AdapterPlaybackState.paused:
        _fire(() => _erikaPlayer.pause());
      case AdapterPlaybackState.stopped:
        _fire(() => _erikaPlayer.stop());
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
    _ended = false;
    _errored = false;
  }

  @override
  Future<void> prepare({int startMs = 0}) async {
    final uri = _mediaUri;
    if (uri == null) return;
    await _erikaPlayer.open(uri, httpHeaders: _httpHeaders);
    // Erika 无原生初始定位：open 后 seek
    if (startMs > 0) {
      await _erikaPlayer.seek(Duration(milliseconds: startMs));
      _lastPositionMs = startMs;
      _lastPositionUpdate = DateTime.now();
    }
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
    return extrapolatePosition(
      anchorMs: _lastPositionMs,
      elapsedMs: elapsed,
      rate: _rate,
      durationMs: _durationMs,
    );
  }

  /// 按速率外推播放位置（纯函数，便于单测）。
  @visibleForTesting
  static int extrapolatePosition({
    required int anchorMs,
    required int elapsedMs,
    required double rate,
    required int durationMs,
  }) {
    var pos = anchorMs + (elapsedMs * rate).round();
    if (pos < 0) pos = 0;
    if (durationMs > 0 && pos > durationMs) pos = durationMs;
    return pos;
  }

  /// 播放状态仅由这些事件更新（其余事件 state 缺省为 idle，逐事件套用会抖动）。
  @visibleForTesting
  static bool appliesStateKind(ErikaEventKind kind) =>
      kind == ErikaEventKind.stateChanged || kind == ErikaEventKind.error;

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
    _fire(() => _erikaPlayer.setVolume(value));
  }

  @override
  double get playbackRate => _rate;

  @override
  set playbackRate(double value) {
    _rate = value;
    _fire(() => _erikaPlayer.setPlaybackRate(value));
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
      _fire(() => _erikaPlayer.selectAudioTrack(null));
      return;
    }
    _fire(() => _selectAudioIndex(tracks.first));
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
      _fire(() => _erikaPlayer.selectSubtitleTrack(null));
      return;
    }
    _fire(() => _selectSubtitleIndex(tracks.first));
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
  void setProperty(String name, String value) {
    // 将 player_screen 使用的少量 mdk 字幕属性映射到 Erika 等价 API；
    // 经 100ms 合并下发，避免拖拽滑杆时每次 tick 都发 channel 调用。
    switch (name) {
      case 'subtitle.scale':
        final v = double.tryParse(value);
        if (v != null) {
          _pendingSubScale = v;
          _scheduleSubtitleStyle();
        }
      case 'subtitle.margin.y':
        final v = int.tryParse(value);
        if (v != null) {
          _pendingSubMarginY = v;
          _scheduleSubtitleStyle();
        }
      case 'subtitle.font.size':
        final v = double.tryParse(value);
        if (v != null) {
          _pendingSubFontSize = v;
          _scheduleSubtitleStyle();
        }
      case 'subtitle.border':
        final v = double.tryParse(value);
        if (v != null) {
          _pendingSubOutline = v;
          _scheduleSubtitleStyle();
        }
      default:
        break;
    }
  }

  void _scheduleSubtitleStyle() {
    _subStyleTimer?.cancel();
    _subStyleTimer = Timer(
      const Duration(milliseconds: 100),
      () => unawaited(_applyPendingSubtitleStyle()),
    );
  }

  Future<void> _applyPendingSubtitleStyle() async {
    if (_disposed) return;
    final scale = _pendingSubScale;
    final margin = _pendingSubMarginY;
    final fontSize = _pendingSubFontSize;
    final outline = _pendingSubOutline;
    _pendingSubScale = null;
    _pendingSubMarginY = null;
    _pendingSubFontSize = null;
    _pendingSubOutline = null;
    try {
      if (scale != null) await _erikaPlayer.setSubtitleScale(scale);
      if (fontSize != null || margin != null || outline != null) {
        await _erikaPlayer.setSubtitleStyle(
          fontSize: fontSize,
          outlineWidth: outline,
          marginVertical: margin,
          overrideMask: _subtitleOverrideMask,
        );
      }
    } catch (e) {
      LogService().log('Erika', '应用字幕样式失败: $e');
    }
  }

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

  // ── 原生弹幕（Erika 引擎内 GPU 合成，替代 Flutter overlay）────────
  //
  // player_screen 在 Erika 档把已解析弹幕编码为 JSON 喂给引擎；引擎按媒体
  // 主时钟在渲染 tick 内合成（天然顺滑）。

  /// 以 JSON 列表替换默认弹幕轨：`[{"time":秒,"content":文本,"type":"scroll|top|bottom","color":"#rrggbb"}]`。
  Future<void> loadDanmakuJson(String json) async {
    if (_disposed) return;
    try {
      await _erikaPlayer.loadDanmakuJson(json);
    } catch (e) {
      LogService().log('Erika', '加载原生弹幕失败: $e');
    }
  }

  Future<void> clearDanmaku() async {
    if (_disposed) return;
    try {
      await _erikaPlayer.clearDanmaku();
    } catch (e) {
      LogService().log('Erika', '清空原生弹幕失败: $e');
    }
  }

  Future<void> setDanmakuEnabled(bool enabled) async {
    if (_disposed) return;
    try {
      await _erikaPlayer.setDanmakuEnabled(enabled);
    } catch (e) {
      LogService().log('Erika', '原生弹幕开关失败: $e');
    }
  }

  /// 映射 AppSettings/显示调节到 Erika 原生弹幕配置（引擎内部 50ms 合并）。
  Future<void> setDanmakuConfig({
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
  }) async {
    if (_disposed) return;
    try {
      await _erikaPlayer.setDanmakuConfig(
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
    } catch (e) {
      LogService().log('Erika', '原生弹幕配置失败: $e');
    }
  }

  // ── 生命周期 ──────────────────────────────────────────────

  Future<void>? _disposeFuture;

  @override
  Future<void> disposeAsync() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    return _disposeFuture = _doDispose();
  }

  Future<void> _doDispose() async {
    _disposed = true;
    _subStyleTimer?.cancel();
    _sub?.cancel();
    _textureId.dispose();
    _stateCtrl.close();
    _statusCtrl.close();
    _eventCtrl.close();
    await _erikaPlayer.dispose();
  }

  @override
  void dispose() {
    unawaited(disposeAsync());
  }
}
