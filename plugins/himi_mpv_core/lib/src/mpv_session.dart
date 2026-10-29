import 'dart:typed_data';

import 'mpv_output_policy.dart';
import 'mpv_poll_result.dart';

/// 平台无关的 MPV 会话接口。
///
/// 鸿蒙、Android、Windows 各自实现，播放器适配器只依赖本接口。
abstract class MpvSession {
  /// >0 = Flutter 纹理 id；0 = 原生 Surface（平台视图）模式。
  int get textureId;

  bool get usesNativeSurface => textureId == 0;

  /// 原生确认的 HDR 直出状态。
  ///
  /// null = 平台未上报（由适配器按输出策略推断）；非 null = 原生实际
  /// 创建的输出路径是否带 HDR 直出。鸿蒙由 create 返回，避免 Dart 侧
  /// 继续用 textureId 猜路径。
  bool? get hdrOutputActive => null;

  /// 原生事件流（属性、mpv 事件、日志）。
  Stream<Map<Object?, Object?>> get events;

  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    int startMs = 0,
    bool pause = false,
  });

  Future<bool> isReady();
  Future<void> kickStart();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(int positionMs);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setAudioTrack(int id);
  Future<void> setSubtitleTrack(int id);
  Future<void> addSubtitle(
    String url, {
    String title = 'external',
    String lang = 'auto',
  });
  Future<void> setProperty(String name, Object value);
  Future<String?> getProperty(String name);
  Future<void> resizeTexture(int width, int height);
  Future<Uint8List?> screenshot();
  Future<String?> getTracks();
  Future<String?> getVideoParams();
  Future<String?> getAudioParams();
  Future<MpvPollResult?> pollState();
  Future<void> dispose();

  /// 原生播放器 UI 接管状态变化（Android：用于 surface 事件来源过滤）。
  ///
  /// 默认空实现：只有存在双 SurfaceView 的平台需要。
  void setNativeUiActive(bool active) {}

  /// 主动向原生重同步当前 surface（默认空实现）。
  ///
  /// 事件通道可能丢事件（宿主销毁不回调 / 事件早于监听），打开原生 UI
  /// 后调用它按 `getCurrentSurface` 轮询兜底，避免永久绑在死 surface 上。
  Future<void> refreshSurface() async {}
}

/// 平台 MPV 会话工厂。
abstract class MpvSessionFactory {
  Future<MpvSession> create({
    int width = 1920,
    int height = 1080,
    String hwdecMode = 'performance',
    bool nativeSurface = false,

    /// 是否启用全屏原生播放器 UI（鸿蒙子窗口 / Android Dialog）。
    /// 仅 Surface 模式有意义；Texture 模式忽略。
    bool nativeUi = false,
  });

  Future<MpvHdrCapabilities> queryHdrCapabilities();
}

/// 原生 Surface 句柄（Android/Windows 的 HWND/Surface；鸿蒙由 XComponent 自行绑定）。
class MpvSurfaceHandle {
  const MpvSurfaceHandle({required this.id, this.kind = 'native'});

  final int id;
  final String kind;

  @override
  String toString() => 'MpvSurfaceHandle($kind:$id)';
}
