import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:himi_mpv_android/himi_mpv_android.dart';
import 'package:himi_mpv_ohos/himi_mpv_ohos.dart';
import 'package:himi_mpv_windows/himi_mpv_windows.dart';

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
  }) {
    if (isOhos) {
      return HimiMpvPlayer.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
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
        hdr: hdr,
        hlg: hlg,
      );
    }
    if (Platform.isWindows) {
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
}
