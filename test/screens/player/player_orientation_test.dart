import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_orientation.dart';

/// 横屏方向请求必须是**单方向**列表。
///
/// 引擎 PlatformChannel.decodeOrientations 把 [landscapeLeft,
/// landscapeRight] 双方向解码为 SCREEN_ORIENTATION_USER_LANDSCAPE
/// （尊重系统旋转锁 → 系统关转屏时无法 180° 翻转）；单方向解码为
/// 固定 LANDSCAPE / REVERSE_LANDSCAPE，锁转屏下也强制旋转。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  });

  List<Object?> orientationArgs() => calls
      .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
      .map((c) => c.arguments as List<Object?>)
      .toList();

  test('向左横屏：单方向 DeviceOrientation.landscapeLeft', () async {
    await requestPlayerLandscape(PlayerLandscapeSide.left);
    expect(orientationArgs(), [
      ['DeviceOrientation.landscapeLeft'],
    ]);
  });

  test('向右横屏（180° 翻转目标）：单方向 DeviceOrientation.landscapeRight', () async {
    await requestPlayerLandscape(PlayerLandscapeSide.right);
    expect(orientationArgs(), [
      ['DeviceOrientation.landscapeRight'],
    ]);
  });

  test('连续翻转：每次都是单方向列表，绝不出现双方向（USER_LANDSCAPE）', () async {
    await requestPlayerLandscape(PlayerLandscapeSide.left);
    await requestPlayerLandscape(PlayerLandscapeSide.right);
    await requestPlayerLandscape(PlayerLandscapeSide.left);
    final args = orientationArgs();
    expect(args, hasLength(3));
    for (final a in args) {
      expect(a, hasLength(1), reason: '双方向列表会被引擎解码为 USER_LANDSCAPE，系统关转屏失效');
    }
  });
}
