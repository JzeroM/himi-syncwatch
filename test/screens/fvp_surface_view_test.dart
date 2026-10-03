import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/fvp_surface_view.dart';

/// fvp/video-view platform view 的创建契约：
/// - hybrid composition（initExpensiveAndroidView）——默认 TLHC 下
///   SurfaceView 位置/z 序错误（fvp 源码注释同款约束）；
/// - creationParams 携带 mdk.Player 句柄与视频分辨率——nativeSetSurface
///   由 fvp 插件自包含处理，无需纹理 CreateRT；
/// - 分辨率键触发换集重建。
void main() {
  late List<MethodCall> log;

  testWidgets('创建 fvp/video-view platform view 并携带 player/尺寸参数',
      (tester) async {
    log = [];
    final channel = const MethodChannel('flutter/platform_views');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        log.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FvpSurfaceView(
          nativeHandle: 4242,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(PlatformViewLink), findsOneWidget);

    final creates = log.where((c) => c.method == 'create');
    expect(creates, isNotEmpty,
        reason: '必须经 hybrid composition 创建（initExpensiveAndroidView）');
    final args = creates.first.arguments as Map;
    expect(args['viewType'], 'fvp/video-view');
    expect(args['hybrid'], isTrue,
        reason: 'hybrid composition（initExpensiveAndroidView）');
    final params = const StandardMessageCodec()
            .decodeMessage(ByteData.sublistView(args['params'] as Uint8List))
        as Map;
    expect(params['player'], 4242);
    expect(params['width'], 1920);
    expect(params['height'], 1080);
    expect(params['tunnel'], isFalse);

    // 换集分辨率变化 → 键变化触发重建
    final key1 = tester.widget<PlatformViewLink>(find.byType(PlatformViewLink));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FvpSurfaceView(
          nativeHandle: 4242,
          videoWidth: 1280,
          videoHeight: 720,
        ),
      ),
    ));
    await tester.pump();
    final key2 = tester.widget<PlatformViewLink>(find.byType(PlatformViewLink));
    expect(key1.key, isNot(equals(key2.key)),
        reason: '分辨率变化须换 key 重建 platform view');
    final lastCreate = log.lastWhere((c) => c.method == 'create');
    final lastParams = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(
            (lastCreate.arguments as Map)['params'] as Uint8List)) as Map;
    expect(lastParams['width'], 1280);
    expect(lastParams['height'], 720);
  });

  testWidgets('tunnel=true 进 creationParams 且 key 随之变化（EGL 自愈重建）',
      (tester) async {
    final log = <MethodCall>[];
    final channel = const MethodChannel('flutter/platform_views');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        log.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    Widget build(bool tunnel) => MaterialApp(
          home: Scaffold(
            body: FvpSurfaceView(
              nativeHandle: 777,
              videoWidth: 3840,
              videoHeight: 1598,
              tunnel: tunnel,
            ),
          ),
        );

    await tester.pumpWidget(build(false));
    await tester.pump();
    await tester.pump();
    final keyGl =
        tester.widget<PlatformViewLink>(find.byType(PlatformViewLink));
    final paramsGl = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView((log
            .lastWhere((c) => c.method == 'create')
            .arguments as Map)['params'] as Uint8List)) as Map;
    expect(paramsGl['tunnel'], isFalse);

    // EGL 故障自愈：tunnel 翻转 → key 变化 → platform view 重建，
    // surfaceDestroyed → surfaceCreated 按直写参数重新 nativeSetSurface
    await tester.pumpWidget(build(true));
    await tester.pump();
    final keyTunnel =
        tester.widget<PlatformViewLink>(find.byType(PlatformViewLink));
    expect(keyTunnel.key, isNot(equals(keyGl.key)),
        reason: 'tunnel 变化须换 key 重建 platform view');
    final paramsTunnel = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView((log
            .lastWhere((c) => c.method == 'create')
            .arguments as Map)['params'] as Uint8List)) as Map;
    expect(paramsTunnel['tunnel'], isTrue,
        reason: '直写参数必须进 creationParams（directSurface 分支）');
    expect(paramsTunnel['player'], 777);
  });
}
