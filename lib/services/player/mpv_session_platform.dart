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
      // Windows 不支持原生播放器 UI，参数透传但忽略。
      return HimiMpvWindowsSession.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
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
