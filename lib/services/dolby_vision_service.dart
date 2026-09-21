import 'dart:io';
import 'package:flutter/services.dart';

class DolbyVisionService {
  static const _channel = MethodChannel('com.himi/dolby_vision');

  static Future<bool> _cachedResult = Future.value(false);
  static bool _initialized = false;

  /// 查询设备是否支持 Dolby Vision 硬解（任意 Profile）
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    if (_initialized) return _cachedResult;
    try {
      _cachedResult = _channel.invokeMethod<bool>('isDolbyVisionSupported')
          .then((v) => v ?? false);
      _initialized = true;
      return await _cachedResult;
    } catch (_) {
      return false;
    }
  }
}
