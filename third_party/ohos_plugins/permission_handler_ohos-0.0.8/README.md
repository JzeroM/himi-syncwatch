# permission_handler_ohos

[![pub package](https://img.shields.io/pub/v/permission_handler_ohos.svg)](https://pub.dartlang.org/packages/permission_handler_ohos) [![GitHub stars](https://img.shields.io/github/stars/harmonycandies/permission_handler_ohos)](https://github.com/harmonycandies/permission_handler_ohos/stargazers) [![GitHub forks](https://img.shields.io/github/forks/harmonycandies/permission_handler_ohos)](https://github.com/harmonycandies/permission_handler_ohos/network) [![GitHub license](https://img.shields.io/github/license/harmonycandies/permission_handler_ohos)](https://github.com/harmonycandies/permission_handler_ohos/blob/master/LICENSE) [![GitHub issues](https://img.shields.io/github/issues/harmonycandies/permission_handler_ohos)](https://github.com/harmonycandies/permission_handler_ohos/issues) ![HarmonyCandies QQ 群](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2Fharmonycandies%2F.github%2Frefs%2Fheads%2Fmain%2Fdata.yml&query=%24.qq_group_number&label=QQ%E7%BE%A4&logo=qq&color=1DACE8)

The plugin to request and check permissions on OpenHarmony.

权限列表来自: https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Release/zh-cn/application-dev/security/AccessToken/permissions-for-all.md

- [permission\_handler\_ohos](#permission_handler_ohos)
- [注意](#注意)
- [使用](#使用)
- [例子](#例子)
  - [检查权限状态](#检查权限状态)
  - [请求单个权限](#请求单个权限)
  - [请求多个权限](#请求多个权限)
  - [打开设置页面](#打开设置页面)

# 注意

由于 `OpenHarmony` 和 `HarmonyOS` 的权限差异以及鸿蒙版本的高速迭代，检查请求权限的 `api` 是传递的权限的字符串全称，如果你发现 `PermissionOhos` 枚举中没有某个权限，你可以直接传递权限的字符串全称。等鸿蒙版本稳定下来了，会再同步权限列表到枚举中。

# 使用

```yaml
dependencies:
  permission_handler_ohos: any
```

请认真阅读官方关于权限的文档 https://gitee.com/openharmony/docs/blob/OpenHarmony-4.1-Beta1/zh-cn/application-dev/security/AccessToken/app-permission-mgmt-overview.md#%E5%BA%94%E7%94%A8%E6%9D%83%E9%99%90%E7%AE%A1%E6%8E%A7%E6%A6%82%E8%BF%B0

在你的项目的 `module.json5` 文件中增加对应需要权限设置。

```json
    requestPermissions: [
      { name: "ohos.permission.READ_CALENDAR" },
      { name: "ohos.permission.WRITE_CALENDAR" },
    ],
```


# 例子

## 检查权限状态

```dart
import 'package:device_info_plus_ohos/device_info_plus_ohos.dart';
 
    final PermissionStatusOhos status =
        await PermissionHandlerOhos.checkPermissionStatus(
            PermissionOhos.read_calendar.name);      
```

## 请求单个权限

```dart
    final PermissionStatusOhos status =
        await PermissionHandlerOhos.requestPermission(
      PermissionOhos.read_calendar.name,
    );
```


## 请求多个权限

```dart
    final Map<String, PermissionStatusOhos> statusMap =
        await PermissionHandlerOhos.requestPermissions([
      PermissionOhos.read_calendar.name,
      PermissionOhos.write_calendar.name,
    ]);
```


## 打开设置页面

```dart
   PermissionHandlerOhos.openAppSettings();
```

