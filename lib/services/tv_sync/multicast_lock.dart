import 'dart:io';

import 'package:flutter/services.dart';

/// Android 组播锁（WifiManager.MulticastLock）封装。
///
/// 用途：WiFi 省电时系统会丢弃广播/组播包，导致局域网发现（UDP 广播）
/// 收不到对端。持有组播锁可让 WiFi 射频保持接收（需 manifest 声明
/// `CHANGE_WIFI_MULTICAST_STATE`，属普通权限、无运行时弹窗）。
///
/// 非 Android 平台为 no-op；通道缺失/异常一律静默（发现失败不应崩溃，
/// 退化为未持锁行为）。
class MulticastLockService {
  const MulticastLockService({this.channel = _defaultChannel});

  static const MethodChannel _defaultChannel =
      MethodChannel('himi/network_discovery');

  /// 测试可注入的通道。
  final MethodChannel channel;

  Future<void> acquire() async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<void>('acquireMulticastLock');
    } on MissingPluginException {
      // 通道未注册（如未走 Android 构建）→ 忽略
    } on PlatformException {
      // 平台侧异常 → 忽略，退化为未持锁
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await channel.invokeMethod<void>('releaseMulticastLock');
    } on MissingPluginException {
      // 忽略
    } on PlatformException {
      // 忽略
    }
  }
}
