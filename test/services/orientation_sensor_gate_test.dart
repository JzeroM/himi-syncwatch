import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/orientation_sensor_gate.dart';

void main() {
  group('OrientationSensorGate.shouldSubscribeOrientationSensor', () {
    test('Android 订阅（sensors_plus 有原生实现）', () {
      expect(
        OrientationSensorGate.shouldSubscribeOrientationSensor(
          isAndroid: true,
          isIOS: false,
        ),
        isTrue,
      );
    });

    test('iOS 订阅', () {
      expect(
        OrientationSensorGate.shouldSubscribeOrientationSensor(
          isAndroid: false,
          isIOS: true,
        ),
        isTrue,
      );
    });

    test('桌面三端不订阅——订阅会因未处理的 MissingPluginException 落 FATAL', () {
      expect(
        OrientationSensorGate.shouldSubscribeOrientationSensor(
          isAndroid: false,
          isIOS: false,
        ),
        isFalse,
      );
    });

    test('双真值仍订阅（异常组合兜底）', () {
      expect(
        OrientationSensorGate.shouldSubscribeOrientationSensor(
          isAndroid: true,
          isIOS: true,
        ),
        isTrue,
      );
    });
  });
}
