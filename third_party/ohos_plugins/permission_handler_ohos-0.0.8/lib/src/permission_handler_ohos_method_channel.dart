import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler_ohos/src/permission_status.dart';

import 'permission_handler_ohos_platform_interface.dart';

/// An implementation of [PermissionHandlerOhosPlatform] that uses method channels.
class MethodChannelPermissionHandlerOhos extends PermissionHandlerOhosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel =
      const MethodChannel('com.harmonycandies.permission_handler_ohos');

  /// Checks the current status of the given [OhosPermissions].
  @override
  Future<PermissionStatusOhos> checkPermissionStatus(String permission) async {
    final int? status = await methodChannel.invokeMethod<int>(
      'checkPermissionStatus',
      permission,
    );

    return PermissionStatusOhos.values.firstWhere(
      (element) => element.value == status,
      orElse: () => PermissionStatusOhos.invalid,
    );
  }

  /// Opens the app settings page.
  ///
  /// Returns [true] if the app settings page could be opened, otherwise
  /// [false].
  @override
  Future<bool> openAppSettings() async {
    return (await methodChannel.invokeMethod<bool>(
          'openAppSettings',
        )) ??
        false;
  }

  /// Requests the user for access to the supplied list of [PermissionOhos]s, if
  /// they have not already been granted before.
  ///
  /// Returns a [Map] containing the status per requested [PermissionOhos].
  @override
  Future<Map<String, PermissionStatusOhos>> requestPermissions(
      List<String> permissions) async {
    return ((await methodChannel.invokeMethod<Map<Object?, Object?>>(
              'requestPermissions',
              permissions,
            )) ??
            <String, int>{})
        .map((key, value) => MapEntry<String, PermissionStatusOhos>(
              key.toString(),
              PermissionStatusOhos.values.firstWhere(
                (element) =>
                    element.value ==
                    int.parse(
                      value.toString(),
                    ),
                orElse: () => PermissionStatusOhos.invalid,
              ),
            ));
  }
}
