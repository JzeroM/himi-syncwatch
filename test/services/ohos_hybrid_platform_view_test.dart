import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OHOS hybrid 平台视图通过 platform_views 同步尺寸/位置并释放', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      calls.add(call);
      if (call.method == 'resize') {
        return <Object?, Object?>{
          'width': 100,
          'height': 50,
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });

    final controller = PlatformViewsService.initExpensiveOhosView(
      id: 7,
      viewType: 'himi_mpv_surface',
      layoutDirection: TextDirection.ltr,
    );
    await controller.create();
    final size = await controller.setSize(const Size(100, 50));
    await controller.setOffset(const Offset(10, 20), transform: null);
    await controller.dispose();

    expect(size, const Size(100, 50));
    expect(
        calls.map((c) => c.method),
        containsAll(<String>[
          'create',
          'resize',
          'offset',
          'dispose',
        ]));
    final create = calls.firstWhere((c) => c.method == 'create');
    expect((create.arguments as Map)['hybrid'], isTrue);
    final dispose = calls.firstWhere((c) => c.method == 'dispose');
    expect((dispose.arguments as Map)['hybrid'], isTrue);
  });
}
