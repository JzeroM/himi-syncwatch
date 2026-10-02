/// 传感器订阅平台守卫（纯 Dart，便于单元测试）。
///
/// sensors_plus 7.x 仅注册 android/ios/web 三端；桌面端（Windows/macOS/
/// Linux）不仅事件流走 `onError`（可吞），`accelerometerEventStream()`
/// 内部未 await 的 `invokeMethod('setAccelerationSamplingPeriod')` 还会
/// 抛 MissingPluginException 且无人处理，被 `PlatformDispatcher.onError`
/// 记成 FATAL 落盘——把摇一摇翻转误判为崩溃。故订阅前先过本守卫。
library;

class OrientationSensorGate {
  const OrientationSensorGate._();

  /// 是否应订阅加速度计（摇一摇翻转）。
  ///
  /// 仅 Android/iOS 有 sensors_plus 原生实现；web/桌面一律不订阅。
  static bool shouldSubscribeOrientationSensor({
    required bool isAndroid,
    required bool isIOS,
  }) =>
      isAndroid || isIOS;
}
