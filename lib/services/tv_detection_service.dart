import 'dart:io';
import 'package:flutter/services.dart';

/// TV 设备自动识别（策略 A）。
///
/// 只负责平台侧探测；是否真正开启 TV 模式的决策在
/// `SettingsNotifier.applyTvAutoDetection`（用户手动设置过则不覆盖）。
/// 非 Android 平台直接返回 false；通道缺失/异常按「非 TV」处理，
/// 绝不因检测失败而误开 TV 模式。
class TvDetectionService {
  const TvDetectionService();

  /// 测试可注入的通道（默认 `himi/platform`）。
  final MethodChannel channel = const MethodChannel('himi/platform');

  Future<bool> isTelevision() async {
    if (!Platform.isAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('isTelevision') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
