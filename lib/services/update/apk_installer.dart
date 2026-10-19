import 'dart:io';

import 'package:flutter/services.dart';

/// Android 安装能力封装（原生通道 `himi/apk_installer`）。
///
/// - [canInstall]：是否已允许「安装未知应用」（Android 8.0+ 的应用内安装前提）；
/// - [openInstallSettings]：跳系统「安装未知应用」授权页；
/// - [install]：对已下载的 APK 调起系统安装器（FileProvider 授权）。
class ApkInstaller {
  ApkInstaller._();

  static const channel = MethodChannel('himi/apk_installer');

  /// 通道仅注册在 Android。
  static bool get isSupported => Platform.isAndroid;

  /// 是否已允许安装未知来源应用（非 Android / 通道异常一律 false）。
  static Future<bool> canInstall() async {
    if (!isSupported) return false;
    try {
      return await channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开「安装未知应用」授权页；返回是否成功打开。
  static Future<bool> openInstallSettings() async {
    if (!isSupported) return false;
    try {
      return await channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 调起系统安装器；返回是否已拉起（用户仍可取消安装）。
  static Future<bool> install(String apkPath) async {
    if (!isSupported) return false;
    try {
      return await channel
              .invokeMethod<bool>('install', {'path': apkPath}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
