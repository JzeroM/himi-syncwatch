# device_info_plus_ohos

[![pub package](https://img.shields.io/pub/v/device_info_plus_ohos.svg)](https://pub.dartlang.org/packages/device_info_plus_ohos) [![GitHub stars](https://img.shields.io/github/stars/harmonycandies/device_info_plus_ohos)](https://github.com/harmonycandies/device_info_plus_ohos/stargazers) [![GitHub forks](https://img.shields.io/github/forks/harmonycandies/device_info_plus_ohos)](https://github.com/harmonycandies/device_info_plus_ohos/network) [![GitHub license](https://img.shields.io/github/license/harmonycandies/device_info_plus_ohos)](https://github.com/harmonycandies/device_info_plus_ohos/blob/main/LICENSE) [![GitHub issues](https://img.shields.io/github/issues/harmonycandies/device_info_plus_ohos)](https://github.com/harmonycandies/device_info_plus_ohos/issues) <a target="_blank" href="https://qm.qq.com/q/ajfsyk2RcA"><img border="0" src="https://pub.idqqimg.com/wpa/images/group.png" alt="flutter-candies" title="flutter-candies"></a>

Get current device information from within the Flutter application.

The OpenHarmony implementation of [`device_info_plus`][1].

这个 Flutter 插件提供了一个用于查询应用设备信息的 API。

[`device_info_plus`][1] 在 OpenHarmony 平台的实现。

## Usage

```yaml
dependencies:
  device_info_plus: any
  device_info_plus_ohos: any
```

Example:

```dart
import 'package:device_info_plus_ohos/device_info_plus_ohos.dart';
 
final DeviceInfoOhosPlugin deviceInfoOhosPlugin = DeviceInfoOhosPlugin();

OhosDeviceInfo deviceInfo = await deviceInfoOhosPlugin.ohosDeviceInfo;

// Requires permission: ohos.permission.sec.ACCESS_UDID (System permission, only open to system apps).
OhosAccessUDIDInfo accessUDIDInfo = await deviceInfoOhosPlugin.ohosAccessUDIDInfo;
```

[1]: https://pub.dev/packages/device_info_plus
