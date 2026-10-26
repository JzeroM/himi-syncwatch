import 'package:device_info_plus_ohos/src/ohos_device_info.dart';
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:device_info_plus_platform_interface/method_channel/method_channel_device_info.dart';

export 'src/ohos_device_info.dart';

class DeviceInfoOhosPlugin {
  DeviceInfoOhosPlugin();
  static MethodChannelDeviceInfo get _platform {
    return DeviceInfoPlatform.instance as MethodChannelDeviceInfo;
  }

  /// This information does not change from call to call. Cache it.
  OhosDeviceInfo? _cachedOhosDeviceInfo;

  /// Information derived from `@ohos.deviceInfo`.
  ///
  /// https://developer.harmonyos.com/cn/docs/documentation/doc-references-V3/js-apis-device-info-0000001428061996-V3
  Future<OhosDeviceInfo> get ohosDeviceInfo async => _cachedOhosDeviceInfo ??=
      OhosDeviceInfo.fromMap((await _platform.deviceInfo()).data);

  /// Requires permission: ohos.permission.sec.ACCESS_UDID (System permission, only open to system apps).
  /// Device serial number.
  /// Device Udid.
  Future<OhosAccessUDIDInfo> get ohosAccessUDIDInfo async =>
      OhosAccessUDIDInfo.fromMap(
          // ignore: invalid_use_of_visible_for_testing_member
          (await _platform.channel.invokeMethod('getAccessUDIDInfo'))
              .cast<String, dynamic>());
}
