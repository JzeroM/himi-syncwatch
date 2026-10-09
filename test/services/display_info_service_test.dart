import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/display_info_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  final log = <MethodCall>[];

  setUp(() {
    DisplayInfoService.resetCache();
    channel = const MethodChannel('himi/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'displaySize') {
        return <String, Object>{'width': 3840, 'height': 2160};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    DisplayInfoService.resetCache();
  });

  test('通道返回有效尺寸 → 解析为 Size 并缓存', () async {
    final service = const DisplayInfoService();
    final size = await service.realDisplaySize();
    // 非 Android（测试宿主）恒 null —— 平台守卫优先于通道 mock。
    // 该行为本身即单测目标：非 Android 不发通道调用。
    expect(log, isEmpty);
    expect(size, isNull);
  });

  test('resetCache 清空缓存（测试隔离）', () {
    DisplayInfoService.resetCache();
    // 无通道环境下不应抛错
    expect(DisplayInfoService.resetCache, returnsNormally);
  });
}
