import 'dart:async' show unawaited;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

import 'player_adapter.dart';

/// mdk（fvp）播放器适配器：包装 mdk.Player，实现 [PlayerAdapter] 接口。
///
/// 纯委托层，不引入任何业务逻辑。所有 mdk 特有类型（PlaybackState /
/// MediaStatus / ColorSpace / SeekFlag / MediaType / MediaEvent）在
/// 此层完成与 Adapter 抽象类型的双向映射。
class MdkPlayerAdapter implements PlayerAdapter, AsyncDisposablePlayer {
  MdkPlayerAdapter() : _player = mdk.Player();

  final mdk.Player _player;
  bool _disposed = false;

  /// seek flags（v1.1.222）：keyFrame（快速关键帧定位）+ inCache（命中
  /// demux 缓存区间免重下，对齐 fvp 默认缓存行为）。仅 keyFrame 时
  /// TV 盒子 surfaceView 关键帧 seek 窗口长，期间原生 position 可能
  /// 报 0/负值 → 上层进度条跳回开头（配合 player_screen 的
  /// `_isSeekingPlayback` 守卫双保险）。
  static final mdk.SeekFlag seekFlags =
      mdk.SeekFlag(mdk.SeekFlag.keyFrame | mdk.SeekFlag.inCache);

  /// lowLatency=1 等效 avformat 属性（v1.1.222 起播加速，纯常量可单测）。
  ///
  /// 对齐 fvp `registerWith('lowLatency': 1)` 在
  /// `MdkVideoPlayerPlatform.create()` 内的应用：
  /// - `avformat.fflags +nobuffer`：低延迟 demux（fvp 注释：1st
  ///   key-frame packet is dropped）；himi 保留 `+fastseek`（seek 加速）
  /// - `avformat.analyzeduration 100000`（100ms，原 500ms）
  /// - `avformat.fpsprobesize 0`（跳过 fps 探测）
  ///
  /// 注意：himi 绕过 video_player 插件层直用 mdk.Player FFI，故
  /// registerWith 的 lowLatency 选项无效，须在此层显式写入。
  /// 配套 `lowLatencyBufferMinMs`：起播最小缓冲 0（原 2000ms），
  /// 最小数据即起播；`demux.buffer.ranges=8` 段缓存保留（后退 seek）。
  static const lowLatencyProperties = <String, String>{
    'avformat.fflags': '+fastseek+nobuffer',
    'avformat.analyzeduration': '100000',
    'avformat.fpsprobesize': '0',
  };

  /// lowLatency 配套：setBufferRange 最小缓冲（ms）。
  static const lowLatencyBufferMinMs = 0;

  /// 诊断面板 / SurfaceView 直接访问底层 mdk.Player（仅 mdk 档）。
  mdk.Player get raw => _player;

  // ── 播放控制 ──────────────────────────────────────────────

  @override
  AdapterPlaybackState get state => _mapState(_player.state);

  @override
  set state(AdapterPlaybackState value) {
    _player.state = _unmapState(value);
  }

  @override
  Future<void> seek({required int positionMs}) async {
    await _player.seek(position: positionMs, flags: seekFlags);
  }

  // ── 媒体加载 ──────────────────────────────────────────────

  @override
  set media(String uri) {
    _player.media = uri;
  }

  @override
  Future<void> prepare({int startMs = 0}) => _player.prepare(position: startMs);

  // ── 属性 ──────────────────────────────────────────────────

  @override
  int get position => _player.position;

  @override
  int get duration => _player.mediaInfo.duration;

  @override
  AdapterMediaInfo get mediaInfo {
    final mi = _player.mediaInfo;
    return AdapterMediaInfo(
      duration: mi.duration,
      format: mi.format,
      audio: (mi.audio ?? const [])
          .map((a) => AdapterAudioStream(
                codec: a.codec.codec,
                bitRate: a.codec.bitRate,
                channels: a.codec.channels,
                sampleRate: a.codec.sampleRate,
              ))
          .toList(),
      video: (mi.video ?? const [])
          .map((v) => AdapterVideoStream(
                codec: v.codec.codec,
                width: v.codec.width,
                height: v.codec.height,
                par: v.codec.par,
                rotation: v.rotation,
                colorSpace: _mapColorSpace(v.codec.colorSpace),
                doviProfile: v.codec.doviProfile,
                formatName: v.codec.formatName ?? '',
                bitRate: v.codec.bitRate,
              ))
          .toList(),
      subtitleCount: mi.subtitle?.length ?? 0,
    );
  }

  @override
  double get volume => _player.volume;

  @override
  set volume(double value) => _player.volume = value;

  @override
  double get playbackRate => _player.playbackRate;

  @override
  set playbackRate(double value) => _player.playbackRate = value;

  @override
  AdapterMediaStatus get mediaStatus =>
      AdapterMediaStatus(_player.mediaStatus.rawValue);

  @override
  int buffered() => _player.buffered();

  @override
  ValueListenable<int?> get textureId => _player.textureId;

  @override
  int get nativeHandle => _player.nativeHandle;

  // ── 渲染 ──────────────────────────────────────────────────

  @override
  Future<int> updateTexture({int? width, int? height, bool? tunnel}) =>
      _player.updateTexture(width: width, height: height, tunnel: tunnel);

  @override
  Future<Size?> get textureSize => _player.textureSize;

  @override
  void setColorSpace(AdapterColorSpace cs) =>
      _player.setColorSpace(_unmapColorSpace(cs));

  @override
  void renderVideo() => _player.renderVideo();

  // ── 轨道 ──────────────────────────────────────────────────

  @override
  List<int> get activeAudioTracks => _player.activeAudioTracks;

  @override
  set activeAudioTracks(List<int> tracks) =>
      _player.activeAudioTracks = tracks;

  @override
  List<int> get activeSubtitleTracks => _player.activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> tracks) =>
      _player.activeSubtitleTracks = tracks;

  // ── 事件 ──────────────────────────────────────────────────

  @override
  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged => _player.onStateChanged.map((e) =>
          (oldValue: _mapState(e.oldValue), newValue: _mapState(e.newValue)));

  @override
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus => _player.onMediaStatus.map((e) => (
            oldValue: AdapterMediaStatus(e.oldValue.rawValue),
            newValue: AdapterMediaStatus(e.newValue.rawValue),
          ));

  @override
  Stream<AdapterMediaEvent> get onEvent => _player.onEvent.map(
      (e) => AdapterMediaEvent(e.error, e.category, e.detail));

  // ── 属性通道 ──────────────────────────────────────────────

  @override
  void setProperty(String name, String value) =>
      _player.setProperty(name, value);

  @override
  String? getProperty(String name) => _player.getProperty(name);

  @override
  void setHttpHeaders(Map<String, String> headers) {
    if (headers.isEmpty) return;
    _player.setProperty(
      'avio.headers',
      headers.entries.map((e) => '${e.key}: ${e.value}').join(','),
    );
  }

  @override
  List<String> get videoDecoders => _player.videoDecoders;

  @override
  set videoDecoders(List<String> decoders) => _player.videoDecoders = decoders;

  @override
  List<String> get audioDecoders => _player.audioDecoders;

  @override
  set audioDecoders(List<String> decoders) => _player.audioDecoders = decoders;

  @override
  set audioBackends(List<String> backends) => _player.audioBackends = backends;

  @override
  void setBufferRange({int min = -1, int max = -1, bool drop = false}) =>
      _player.setBufferRange(min: min, max: max, drop: drop);

  // ── 字幕 / 截图 ───────────────────────────────────────────

  @override
  Future<void> setMedia(String uri, {required AdapterMediaType type}) async {
    _player.setMedia(uri, _unmapMediaType(type));
  }

  @override
  Future<Uint8List?> snapshot({int? width, int? height}) =>
      _player.snapshot(width: width, height: height);

  // ── 生命周期 ──────────────────────────────────────────────

  @override
  void dispose() => unawaited(disposeAsync());

  /// 确定性释放（v1.1.222）：fvp 的 `dispose()` 是 `void async`
  /// （fire-and-forget：releaseTexture → unregister → mdkPlayerAPI_delete），
  /// 外部无法 await 其原生 teardown 落定。引擎重建（MDK→Erika/media_kit）
  /// 时若旧 MDK 的原生释放（D3D/GL/AudioTrack）与新引擎初始化重叠 →
  /// 原生竞争闪退。
  ///
  /// 顺序：先确定性 await 释放 Flutter 纹理（幂等，fvp dispose 内部同
  /// 一步骤提前做掉）→ 触发原生 delete → settle 等待其完成。
  @override
  Future<void> disposeAsync() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _player
          .updateTexture(width: -1)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      _player.dispose();
    } catch (_) {}
    // mdkPlayerAPI_delete 无 Future 可等：settle 等待原生资源
    // （纹理/AudioTrack/渲染线程）落定后再允许新引擎创建。
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  // ── 映射 ──────────────────────────────────────────────────

  static AdapterColorSpace _mapColorSpace(mdk.ColorSpace cs) {
    switch (cs) {
      case mdk.ColorSpace.bt709:
        return AdapterColorSpace.bt709;
      case mdk.ColorSpace.bt2100PQ:
        return AdapterColorSpace.bt2100PQ;
      case mdk.ColorSpace.bt2100hlg:
        return AdapterColorSpace.bt2100hlg;
      default:
        return AdapterColorSpace.unknown;
    }
  }

  static AdapterPlaybackState _mapState(mdk.PlaybackState s) {
    switch (s) {
      case mdk.PlaybackState.playing:
        return AdapterPlaybackState.playing;
      case mdk.PlaybackState.paused:
        return AdapterPlaybackState.paused;
      default:
        return AdapterPlaybackState.stopped;
    }
  }

  static mdk.PlaybackState _unmapState(AdapterPlaybackState s) {
    switch (s) {
      case AdapterPlaybackState.playing:
        return mdk.PlaybackState.playing;
      case AdapterPlaybackState.paused:
        return mdk.PlaybackState.paused;
      case AdapterPlaybackState.stopped:
        return mdk.PlaybackState.stopped;
    }
  }

  static mdk.ColorSpace _unmapColorSpace(AdapterColorSpace cs) {
    switch (cs) {
      case AdapterColorSpace.bt709:
        return mdk.ColorSpace.bt709;
      case AdapterColorSpace.bt2100PQ:
        return mdk.ColorSpace.bt2100PQ;
      case AdapterColorSpace.bt2100hlg:
        return mdk.ColorSpace.bt2100hlg;
      case AdapterColorSpace.unknown:
        return mdk.ColorSpace.unknown;
    }
  }

  static mdk.MediaType _unmapMediaType(AdapterMediaType t) {
    switch (t) {
      case AdapterMediaType.audio:
        return mdk.MediaType.audio;
      case AdapterMediaType.subtitle:
        return mdk.MediaType.subtitle;
    }
  }
}
