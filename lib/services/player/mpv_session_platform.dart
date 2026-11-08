import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:himi_mpv_android/himi_mpv_android.dart';
import 'package:himi_mpv_ohos/himi_mpv_ohos.dart';
import 'package:himi_mpv_windows/himi_mpv_windows.dart';

import 'native/android_native_player.dart';

/// 三端 MPV 会话工厂。
///
/// Surface 模式：鸿蒙 XComponent、Android SurfaceView、Windows 子 HWND；
/// Texture 模式由各平台会话创建 Flutter 纹理。具体路径由 MPV 设置决定。
class MpvSessionPlatform {
  const MpvSessionPlatform._();

  static bool get isOhos => defaultTargetPlatform.name == 'ohos';

  static Future<MpvSession> create({
    required int width,
    required int height,
    required String hwdecMode,
    required bool nativeSurface,
    required bool hdr,
    required bool hlg,
    bool nativeUi = false,
  }) {
    if (isOhos) {
      return HimiMpvPlayer.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
        nativeUi: nativeUi,
        hdr: hdr,
        hlg: hlg,
      );
    }
    if (Platform.isAndroid) {
      return HimiMpvAndroidSession.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
        nativeUi: nativeUi,
        hdr: hdr,
        hlg: hlg,
      );
    }
    if (Platform.isWindows) {
      // 646：Windows 也支持原生播放器 UI——走**顶层窗口**（WS_POPUP）+
      // MPV `vo=gpu-next` 直出，实现真 HDR。
      //
      // 旧注释「Windows 不支持原生播放器 UI」已过时：限制在于
      // **子 HWND 会被 Flutter 的 DirectComposition 不透明层遮挡**
      // （surface 灰屏根因），而非不能做原生 UI。改用顶层窗口后可行。
      return HimiMpvWindowsSession.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
        nativeUi: nativeUi,
        hdr: hdr,
        hlg: hlg,
      );
    }
    throw UnsupportedError(
        'MPV native surface is not implemented on this platform');
  }

  static Future<MpvHdrCapabilities> queryHdrCapabilities() {
    if (isOhos) return HimiMpvPlayer.queryHdrCapabilities();
    if (Platform.isAndroid) return HimiMpvAndroidSession.queryHdrCapabilities();
    if (Platform.isWindows) return HimiMpvWindowsSession.queryHdrCapabilities();
    return Future<MpvHdrCapabilities>.value(MpvHdrCapabilities.unknown);
  }

  // ── 原生播放器 UI 宿主（鸿蒙子窗口 / Android Dialog）──────────

  /// 原生 UI 宿主平台名（'ohos' / 'android'）；不支持为 null（Windows 恒
  /// null，门控已在上游排除）。
  static String? get nativeUiPlatformName {
    if (isOhos) return 'ohos';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  /// 打开原生播放器 UI 宿主（幂等）。
  static Future<void> openNativeUi() {
    if (isOhos) return HimiMpvPlayer.openNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.open();
    return Future<void>.value();
  }

  /// 关闭原生播放器 UI 宿主（幂等）。
  static Future<void> closeNativeUi() {
    if (isOhos) return HimiMpvPlayer.closeNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.close();
    return Future<void>.value();
  }

  /// 临时隐藏原生播放器 UI 宿主（**不销毁** session / surface 绑定，603）。
  ///
  /// 用于需要在 Flutter 层显示界面的场景（资源搜索页 / 离房确认框）：
  /// 原生窗口 z-order 在 Flutter 页面之上，不隐藏会盖住它们。
  static Future<void> suspendNativeUi() {
    if (isOhos) return HimiMpvPlayer.suspendNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.suspend();
    return Future<void>.value();
  }

  /// 恢复被 [suspendNativeUi] 隐藏的原生播放器 UI 宿主（幂等）。
  static Future<void> resumeNativeUi() {
    if (isOhos) return HimiMpvPlayer.resumeNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.resume();
    return Future<void>.value();
  }

  /// Dart → 原生：推送权威状态 JSON 快照。
  static Future<void> pushNativeState(String stateJson) {
    if (isOhos) return HimiMpvPlayer.pushNativeState(stateJson);
    if (Platform.isAndroid)
      return AndroidNativePlayer.pushNativeState(stateJson);
    return Future<void>.value();
  }

  /// 原生 UI 命令流（原生 → Dart）。
  static Stream<Map<Object?, Object?>> nativeUiCommandStream() {
    if (isOhos) return HimiMpvPlayer.nativeUiCommandStream;
    if (Platform.isAndroid) return AndroidNativePlayer.commandStream;
    return const Stream<Map<Object?, Object?>>.empty();
  }
}
