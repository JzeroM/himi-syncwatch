import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// 本机展示名（UDP 广播/配对框用）：Android 取设备型号（如 "Xiaomi 13"、
/// 盒子型号），其他平台取主机名；失败回退 "HIMI"。
Future<String> resolveLocalDeviceName() async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      final model = android.model.trim();
      if (model.isNotEmpty) return model;
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      final name = ios.name.trim();
      if (name.isNotEmpty) return name;
      final machine = ios.utsname.machine.trim();
      if (machine.isNotEmpty) return machine;
    } else if (Platform.isWindows) {
      final windows = await info.windowsInfo;
      final name = windows.computerName.trim();
      if (name.isNotEmpty) return name;
    } else if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      final name = linux.prettyName.trim();
      if (name.isNotEmpty) return name;
    } else if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      final name = mac.computerName.trim();
      if (name.isNotEmpty) return name;
    }
  } catch (_) {}
  return 'HIMI';
}
