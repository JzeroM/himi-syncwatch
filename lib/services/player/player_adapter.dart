import 'package:flutter/foundation.dart';
import 'dart:ui' show Size;

/// 播放器引擎标识。
///
/// 平台分布（见 player_engine.dart）：
/// - mdk：全平台默认
/// - media_kit：仅 Windows（libmpv；其他平台 PGS/格式不支持，已收敛）
/// - erika：非 TV 平台（自研 Rust 内核；手机真 HDR10 + 原生位图字幕/PGS）
enum PlayerEngine {
  mdk('mdk', 'MDK'),
  mediaKit('media_kit', 'media_kit'),
  erika('erika', 'Erika');

  const PlayerEngine(this.id, this.label);

  final String id;
  final String label;

  static PlayerEngine fromId(String? id) =>
      PlayerEngine.values.firstWhere((e) => e.id == id,
          orElse: () => PlayerEngine.mdk);
}

/// 播放状态（引擎无关）。
enum AdapterPlaybackState { playing, paused, stopped }

/// 媒体状态标志位（引擎无关，位标志语义与 mdk.MediaStatus 对齐）。
class AdapterMediaStatus {
  const AdapterMediaStatus(this.rawValue);

  static const unloaded = AdapterMediaStatus(0x01);
  static const loading = AdapterMediaStatus(0x02);
  static const loaded = AdapterMediaStatus(0x04);
  static const prepared = AdapterMediaStatus(0x08);
  static const stalled = AdapterMediaStatus(0x10);
  static const buffering = AdapterMediaStatus(0x20);
  static const buffered = AdapterMediaStatus(0x40);
  static const end = AdapterMediaStatus(0x80);
  static const seeking = AdapterMediaStatus(0x100);
  static const invalid = AdapterMediaStatus(0x200);

  final int rawValue;

  bool test(AdapterMediaStatus s) => (rawValue & s.rawValue) != 0;

  AdapterMediaStatus operator |(AdapterMediaStatus other) =>
      AdapterMediaStatus(rawValue | other.rawValue);

  @override
  String toString() => 'AdapterMediaStatus(0x${rawValue.toRadixString(16)})';
}

/// 色彩空间（引擎无关）。
enum AdapterColorSpace { unknown, bt709, bt2100PQ, bt2100hlg }

/// 媒体类型（引擎无关，仅用到 audio / subtitle）。
enum AdapterMediaType { audio, subtitle }

/// 媒体事件（引擎无关）。
class AdapterMediaEvent {
  const AdapterMediaEvent(this.error, this.category, this.detail);

  /// 进度值 [0, 100]（category == 'reader.buffering' 时有效）。
  final int error;
  final String category;
  final String detail;
}

/// 音轨流信息（简化，覆盖 player_screen 使用的字段）。
class AdapterAudioStream {
  const AdapterAudioStream({
    required this.codec,
    this.bitRate = 0,
    this.channels = 0,
    this.sampleRate = 0,
  });

  /// 编码名（小写，如 'aac' / 'truehd'）。
  final String codec;
  final int bitRate;
  final int channels;
  final int sampleRate;
}

/// 视频流信息（简化，覆盖 player_screen 使用的字段）。
class AdapterVideoStream {
  const AdapterVideoStream({
    required this.codec,
    required this.width,
    required this.height,
    this.par = 1.0,
    this.rotation = 0,
    this.colorSpace = AdapterColorSpace.unknown,
    this.doviProfile = 0,
    this.formatName = '',
    this.bitRate = 0,
  });

  /// 编码名（小写，如 'hevc' / 'av1'）。
  final String codec;
  final int width;
  final int height;
  final double par;
  final int rotation;
  final AdapterColorSpace colorSpace;
  final int doviProfile;
  final String formatName;
  final int bitRate;
}

/// 媒体信息（简化，覆盖 player_screen 使用的字段）。
class AdapterMediaInfo {
  const AdapterMediaInfo({
    this.duration = 0,
    this.format,
    this.audio = const [],
    this.video = const [],
    this.subtitleCount = 0,
  });

  /// 时长（ms）。
  final int duration;
  final String? format;
  final List<AdapterAudioStream> audio;
  final List<AdapterVideoStream> video;
  final int subtitleCount;

  static const empty = AdapterMediaInfo();
}

/// 原生 teardown 可等待的引擎能力（用于引擎热切换时**先等旧引擎释放**，
/// 避免新引擎在旧引擎释放窗口内创建 → 音频输出争用/状态回调劣化）。
///
/// fvp(mdk) 的 `dispose()` 是 `void async`（无 Future），不实现本接口。
abstract interface class AsyncDisposablePlayer {
  Future<void> disposeAsync();
}

/// 播放器抽象接口：统一 mdk / media_kit 的播放控制、属性、轨道、渲染、事件面。
///
/// 设计原则：
/// - 刻度统一：position/duration/buffered 用 ms；volume 用 0.0–1.0；
///   playbackRate 用倍率（1.0 = 原速）。
/// - 事件模型：onStateChanged / onMediaStatus 为广播 Stream；
///   position 轮询由调用方负责（fvp 无 position stream，media_kit 有但
///   统一走轮询避免全帧率事件洪水）。
/// - 渲染通道：textureId 驱动 Flutter Texture；nativeHandle 供
///   SurfaceView platform view 挂载（media_kit 档无 SurfaceView）。
abstract class PlayerAdapter {
  // ── 播放控制 ──────────────────────────────────────────────

  AdapterPlaybackState get state;
  set state(AdapterPlaybackState value);

  Future<void> seek({required int positionMs});

  // ── 媒体加载 ──────────────────────────────────────────────

  set media(String uri);
  Future<void> prepare();

  // ── 属性（高频）────────────────────────────────────────────

  /// 当前播放位置（ms）。
  int get position;

  /// 媒体时长（ms）；未加载完成时为 0。
  int get duration;

  /// 媒体流信息（简化）；未加载完成时为 [AdapterMediaInfo.empty]。
  AdapterMediaInfo get mediaInfo;

  /// 音量（0.0–1.0 统一刻度）。
  double get volume;
  set volume(double value);

  /// 播放倍速。
  double get playbackRate;
  set playbackRate(double value);

  AdapterMediaStatus get mediaStatus;

  /// 已缓冲时长（ms，播放头前方）。
  int buffered();

  /// Flutter 纹理 id（texture 档渲染驱动源）。
  ValueListenable<int?> get textureId;

  /// 原生播放器句柄（SurfaceView platform view 挂载用）。
  int get nativeHandle;

  // ── 渲染 ──────────────────────────────────────────────────

  Future<int> updateTexture({int? width, int? height, bool? tunnel});
  Future<Size?> get textureSize;
  void setColorSpace(AdapterColorSpace cs);

  /// 强制渲染一帧（mdk 渲染驱动补偿；media_kit 无此需求，空实现）。
  void renderVideo();

  // ── 轨道 ──────────────────────────────────────────────────

  List<int> get activeAudioTracks;
  set activeAudioTracks(List<int> tracks);

  List<int> get activeSubtitleTracks;
  set activeSubtitleTracks(List<int> tracks);

  // ── 事件 ──────────────────────────────────────────────────

  Stream<({AdapterPlaybackState oldValue, AdapterPlaybackState newValue})>
      get onStateChanged;
  Stream<({AdapterMediaStatus oldValue, AdapterMediaStatus newValue})>
      get onMediaStatus;
  Stream<AdapterMediaEvent> get onEvent;

  // ── 属性通道（设置 / 诊断）────────────────────────────────

  void setProperty(String name, String value);
  String? getProperty(String name);

  /// 设置 HTTP 鉴权头（播放源请求）。
  ///
  /// mdk：写 `avio.headers` 属性；media_kit：`Media(httpHeaders:)`；
  /// Erika：`open(httpHeaders:)`。
  void setHttpHeaders(Map<String, String> headers);

  List<String> get videoDecoders;
  set videoDecoders(List<String> decoders);
  List<String> get audioDecoders;
  set audioDecoders(List<String> decoders);
  set audioBackends(List<String> backends);

  void setBufferRange({int min = -1, int max = -1, bool drop = false});

  // ── 字幕 / 截图 ───────────────────────────────────────────

  Future<void> setMedia(String uri, {required AdapterMediaType type});
  Future<Uint8List?> snapshot({int? width, int? height});

  // ── 生命周期 ──────────────────────────────────────────────

  void dispose();
}
