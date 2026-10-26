import 'package:permission_handler_ohos/src/permission_status.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'permission_handler_ohos_method_channel.dart';

abstract class PermissionHandlerOhosPlatform extends PlatformInterface {
  /// Constructs a PermissionHandlerOhosPlatform.
  PermissionHandlerOhosPlatform() : super(token: _token);

  static final Object _token = Object();

  static PermissionHandlerOhosPlatform _instance =
      MethodChannelPermissionHandlerOhos();

  /// The default instance of [PermissionHandlerOhosPlatform] to use.
  ///
  /// Defaults to [MethodChannelPermissionHandlerOhos].
  static PermissionHandlerOhosPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PermissionHandlerOhosPlatform] when
  /// they register themselves.
  static set instance(PermissionHandlerOhosPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Checks the current status of the given [PermissionOhos].
  Future<PermissionStatusOhos> checkPermissionStatus(String permission) {
    throw UnimplementedError(
        'checkPermissionStatus() has not been implemented.');
  }

  /// Opens the app settings page.
  ///
  /// Returns [true] if the app settings page could be opened, otherwise
  /// [false].
  Future<bool> openAppSettings() {
    throw UnimplementedError('openAppSettings() has not been implemented.');
  }

  /// Requests the user for access to the supplied list of [PermissionOhos]s, if
  /// they have not already been granted before.
  ///
  /// Returns a [Map] containing the status per requested [PermissionOhos].
  Future<Map<String, PermissionStatusOhos>> requestPermissions(
      List<String> permissions) {
    throw UnimplementedError('requestPermissions() has not been implemented.');
  }
}
