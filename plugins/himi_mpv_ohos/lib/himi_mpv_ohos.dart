import 'dart:async';

import 'package:flutter/services.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';

export 'package:himi_mpv_core/himi_mpv_core.dart'
    show
        MpvEvent,
        MpvHdrCapabilities,
        MpvPollResult,
        MpvPropertyEvent,
        MpvSession;
export 'himi_mpv_surface_view.dart';

/// HIMI HarmonyOS MPV 播放器的 Dart 侧接口。
///
/// 与 ohos 侧 `HimiMpvOhosPlugin` 一一对应：MethodChannel `himi_mpv` 下发
/// 命令，EventChannel `himi_mpv/events` 回传 mpv 属性/事件/日志。
///
/// 线程模型：所有方法都是异步的，且不阻塞 UI 线程；原生侧 mpv 自带事件
/// 线程，属性观察由 mpv 主动推送。
class HimiMpvPlayer implements MpvSession {
  HimiMpvPlayer._(this._textureId);

  static const MethodChannel _methods = MethodChannel('himi_mpv');
  static const EventChannel _events = EventChannel('himi_mpv/events');

  /// Flutter 纹理 id（用于 `Texture(textureId: ...)` 渲染视频）。
  /// 0 = 原生 Surface（平台视图）模式。
  final int _textureId;
  @override
  int get textureId => _textureId;

  @override
  bool get usesNativeSurface => _textureId == 0;

  @override
  Stream<Map<Object?, Object?>> get events => HimiMpvPlayer.eventStream;

  /// 原生属性/事件流（全局单例广播流）。
  static Stream<Map<Object?, Object?>>? _eventStream;

  /// 创建播放器。
  ///
  /// 返回值：>0 = Flutter 纹理 id；0 = 原生 Surface 平台视图模式
  /// （`nativeSurface: true` 或纹理注册失败）。
  ///
  /// [hwdecMode] 硬解渲染档位：'standard'（完整画质：插值补帧+大缓冲）/
  /// 'performance'（高性能，默认）/ 'extreme'（极速）。
  /// [width]/[height] 仅作为初始尺寸提示，实际以纹理/布局为准。
  static Future<HimiMpvPlayer> create({
    int width = 1920,
    int height = 1080,
    String hwdecMode = 'performance',
    bool nativeSurface = false,
    bool hdr = false,
    bool hlg = false,
  }) async {
    final id = await _methods.invokeMethod<int>('create', {
      'width': width,
      'height': height,
      'hwdecMode': hwdecMode,
      'nativeSurface': nativeSurface,
      'hdr': hdr,
      'hlg': hlg,
    });
    if (id == null) {
      throw StateError('mpv create failed');
    }
    return HimiMpvPlayer._(id);
  }

  /// 查询当前显示 HDR 能力（鸿蒙 display.hdrFormats）。
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

  /// 实时切换渲染档位（播放中生效；无会话时静默忽略，下次 create 生效）。
  static Future<void> setHwdecMode(String mode) =>
      _methods.invokeMethod<void>('setHwdecMode', {'mode': mode});

  /// 订阅原生事件流（全局单例，首个订阅者触发 onListen）。
  ///
  /// 用 `asBroadcastStream` 而非 `receiveBroadcastStream` 的返回值直接广播：
  /// 后者每次 listen 都会向原生发一次 listen 请求，多播放器场景会互相顶掉。
  static Stream<Map<Object?, Object?>> get eventStream {
    final existing = _eventStream;
    if (existing != null) return existing;
    final stream = _events
        .receiveBroadcastStream()
        .map((e) => (e as Map<Object?, Object?>))
        .asBroadcastStream();
    _eventStream = stream;
    return stream;
  }

  /// 打开媒体。
  ///
  /// [headers] 用于 Emby 鉴权（mpv `http-header-fields`）。
  /// [startMs] 起播位置，走 loadfile 的 `start` 选项（原生定位，避免
  /// 事后 seek 在可 seek 性未就绪时被丢弃）。
  ///
  /// 注意：鸿蒙上 surface 可能尚未就绪，此时原生侧会**缓存** URL，
  /// 等 XComponent 的 surface 就绪后自动加载。调用方不需要重试。
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    int startMs = 0,
    bool pause = false,
  }) {
    return _methods.invokeMethod<void>('open', {
      'url': url,
      'headers': headers,
      'startMs': startMs,
      'pause': pause,
    });
  }

  /// 查询原生侧是否已完成 mpv 初始化且 surface 已就绪。
  ///
  /// 用于上层判断「现在能不能读属性」，避免在初始化完成前读到空值。
  Future<bool> isReady() async {
    final v = await _methods.invokeMethod<bool>('isReady');
    return v ?? false;
  }

  /// 踢一脚开始播放（playlist-pos=0）。
  ///
  /// `stop` 之后 loadFile 追加的条目不会自动开播，必须显式指派
  /// playlist-pos 才开始加载（参考 Player.ets 的 open() 序列）。
  Future<void> kickStart() => _methods.invokeMethod<void>('kick');

  Future<void> play() => _methods.invokeMethod<void>('play');

  Future<void> pause() => _methods.invokeMethod<void>('pause');

  Future<void> stop() => _methods.invokeMethod<void>('stop');

  Future<void> seek(int positionMs) =>
      _methods.invokeMethod<void>('seek', {'positionMs': positionMs});

  /// 音量 0.0–1.0（原生侧换算为 mpv 的 0–100）。
  Future<void> setVolume(double volume) =>
      _methods.invokeMethod<void>('setVolume', {'volume': volume});

  Future<void> setSpeed(double speed) =>
      _methods.invokeMethod<void>('setSpeed', {'speed': speed});

  /// 选音轨（mpv `aid`；0 = 关闭）。
  Future<void> setAudioTrack(int id) =>
      _methods.invokeMethod<void>('setAudioTrack', {'id': id});

  /// 选字幕轨（mpv `sid`；0 = 关闭）。
  Future<void> setSubtitleTrack(int id) =>
      _methods.invokeMethod<void>('setSubtitleTrack', {'id': id});

  /// 外挂字幕。
  Future<void> addSubtitle(String url,
          {String title = 'external', String lang = 'auto'}) =>
      _methods.invokeMethod<void>('addSubtitle', {
        'url': url,
        'title': title,
        'lang': lang,
      });

  Future<void> setProperty(String name, Object value) => _methods
      .invokeMethod<void>('setProperty', {'name': name, 'value': value});

  Future<String?> getProperty(String name) =>
      _methods.invokeMethod<String>('getProperty', {'name': name});

  /// 按真实视频分辨率重建纹理缓冲（拿到 video-params 后调用）。
  Future<void> resizeTexture(int width, int height) =>
      _methods.invokeMethod<void>('resizeTexture', {
        'width': width,
        'height': height,
      });

  /// 截图（BGRA 原始字节，需上层自行组装像素格式）。
  Future<Uint8List?> screenshot() =>
      _methods.invokeMethod<Uint8List>('screenshot');

  /// 轨道列表（mpv `track-list` 的 JSON 字符串）。
  Future<String?> getTracks() => _methods.invokeMethod<String>('getTracks');

  /// 视频参数（mpv `video-params` 的 JSON 字符串）。
  Future<String?> getVideoParams() =>
      _methods.invokeMethod<String>('getVideoParams');

  /// 音频参数（mpv `audio-params` 的 JSON 字符串）。
  Future<String?> getAudioParams() =>
      _methods.invokeMethod<String>('getAudioParams');

  /// 主动轮询播放状态（不依赖 EventChannel）。
  ///
  /// 原生事件流经 mpv 的 JSBind 回调派发，在某些设备/时机可能不生效；
  /// 该接口直接同步读取 mpv 属性并返回，作为 UI 的兜底数据源。
  /// 未创建/未初始化时返回 null。
  Future<MpvPollResult?> pollState() async {
    final raw = await _methods.invokeMethod<Map<Object?, Object?>>('pollState');
    return raw == null ? null : MpvPollResult.fromMap(raw);
  }

  /// 销毁播放器并释放纹理。
  Future<void> dispose() => _methods.invokeMethod<void>('dispose');
}
