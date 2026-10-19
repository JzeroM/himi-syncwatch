import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'package:himi_syncwatch/services/update/apk_installer.dart';

/// 安装动作结果。
enum InstallOutcome {
  /// 已拉起系统安装器 / 安装程序（用户仍可取消）。
  launched,

  /// Android 需要先授权「安装未知应用」。
  needsPermission,

  /// 当前平台不支持应用内安装（iOS）。
  unsupported,

  /// 拉起失败。
  failed,
}

/// 把下载好的更新包交给系统（按平台分派）。
///
/// - Android：`ApkInstaller` 原生通道调起安装器；
/// - Windows：拉起 Inno 安装程序（交互式），由上层随后退出应用；
/// - iOS：不支持应用内安装（只能打开下载页，见 [openExternal]）。
class UpdateInstaller {
  UpdateInstaller._();

  /// 是否支持应用内下载安装（iOS 仅能提示 + 打开链接）。
  static bool get supportsInAppInstall =>
      Platform.isAndroid || Platform.isWindows;

  /// 安装已下载的更新包。
  static Future<InstallOutcome> installFile(File file) async {
    if (Platform.isAndroid) {
      if (!await ApkInstaller.canInstall()) {
        return InstallOutcome.needsPermission;
      }
      return await ApkInstaller.install(file.path)
          ? InstallOutcome.launched
          : InstallOutcome.failed;
    }
    if (Platform.isWindows) {
      try {
        await Process.start(
          file.path,
          const [],
          mode: ProcessStartMode.detached,
        );
        return InstallOutcome.launched;
      } catch (_) {
        return InstallOutcome.failed;
      }
    }
    return InstallOutcome.unsupported;
  }

  /// 用系统浏览器/下载器打开外部链接（iOS 下载 IPA、兜底下载页）。
  static Future<bool> openExternal(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
