import 'package:permission_handler_ohos/src/permission_status.dart';

import 'src/permission_handler_ohos_platform_interface.dart';

export 'src/permission_status.dart';
export 'src/permissions.dart';

class PermissionHandlerOhos {
  /// Checks the current status of the given [OhosPermission].
  static Future<PermissionStatusOhos> checkPermissionStatus(String permission) {
    return PermissionHandlerOhosPlatform.instance.checkPermissionStatus(
      permission,
    );
  }

  /// Opens the app settings page.
  ///
  /// Returns [true] if the app settings page could be opened, otherwise
  /// [false].
  static Future<bool> openAppSettings() {
    return PermissionHandlerOhosPlatform.instance.openAppSettings();
  }

  /// Requests the user for access to the supplied list of [OhosPermission]s, if
  /// they have not already been granted before.
  ///
  /// Returns a [Map] containing the status per requested [OhosPermission].
  static Future<Map<String, PermissionStatusOhos>> requestPermissions(
      List<String> permissions) {
    return PermissionHandlerOhosPlatform.instance
        .requestPermissions(permissions);
  }

  /// Request the user for access to the [OhosPermission], if
  /// it has not already been granted before.
  ///
  /// Returns a [PermissionStatusOhos] containing the status requested [OhosPermission].
  static Future<PermissionStatusOhos> requestPermission(
      String permission) async {
    final Map<String, PermissionStatusOhos> statusMap =
        await requestPermissions(<String>[permission]);
    return statusMap[permission] ?? PermissionStatusOhos.invalid;
  }
}
