import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_ohos/himi_mpv_surface_view.dart';

/// 678：鸿蒙 hybrid 平台视图（`HimiMpvSurfaceView`）通道协议测试。
///
/// ## 为什么重写这个文件
///
/// 旧测试调用 `PlatformViewsService.initExpensiveOhosView(...)` ——
/// 该 API **只存在于 Flutter-OH（鸿蒙分支 SDK）**，官方 Flutter 的
/// `platform_views.dart` 里连 `Ohos` 字样都没有（grep = 0），因此在
/// 官方 Flutter 下必然编译失败（`Member not found`），全量测试长期
/// 挂着一个 failed。
///
/// 更关键的是：**实现早就主动弃用了那个 API**。见
/// `plugins/himi_mpv_ohos/lib/himi_mpv_surface_view.dart` 的类注释：
///
/// > 直接通过标准 `flutter/platform_views` 通道创建 hybrid 平台视图，
/// > 不依赖 Flutter-OH 专属的 `OhosViewController` 类型。这样同一份
/// > Dart 代码也能在标准 Flutter（Windows）上编译。
///
/// 所以本文件改为测**现有实现**：真实构造 controller，走
/// `flutter/platform_views` 通道，验证 create / resize / offset /
/// dispose 四处调用与 `hybrid: true` 参数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter/platform_views');

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'resize') {
        return <Object?, Object?>{'width': 100, 'height': 50};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // ═══════════════════════════════════════════════════════════════
  // A. create：hybrid 通道协议
  // ═══════════════════════════════════════════════════════════════

  group('A create 通道协议', () {
    test('A1 create 带 hybrid:true / viewType / direction / id', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();

      expect(calls, hasLength(1));
      final create = calls.single;
      expect(create.method, 'create');
      final args = create.arguments as Map;
      expect(args['id'], 7);
      expect(args['viewType'], HimiMpvSurfaceView.viewType);
      expect(args['viewType'], 'himi_mpv_surface');
      // hybrid = true 是「原生层真正显示」的关键（Surface 模式白屏回归）
      expect(args['hybrid'], isTrue);
      expect(args['direction'], 0);  // TextDirection.ltr
    });

    test('A2 RTL 布局方向映射为 1', () async {
      final controller = createHimiMpvOhosControllerForTest(
        viewId: 8,
        layoutDirection: TextDirection.rtl,
      );
      await controller.create();
      expect((calls.single.arguments as Map)['direction'], 1);
    });

    test('A3 onCreated 回调带回 viewId（PlatformViewLink 依赖它）', () async {
      int? created;
      final controller = createHimiMpvOhosControllerForTest(
        viewId: 9,
        onCreated: (id) => created = id,
      );
      await controller.create();
      expect(created, 9);
    });

    test('A4 create 幂等（重复调用不重复发通道）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 10);
      await controller.create();
      await controller.create();
      expect(calls.where((c) => c.method == 'create'), hasLength(1));
    });

    test('A5 awaitingCreation 语义（创建前 true，创建后 false）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 11);
      expect(controller.awaitingCreation, isTrue);
      await controller.create();
      expect(controller.awaitingCreation, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. resize / offset：尺寸位置同步且去重
  // ═══════════════════════════════════════════════════════════════

  group('B resize / offset 同步', () {
    test('B1 首次同步发 resize + offset，参数正确', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      calls.clear();

      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );

      expect(calls.map((c) => c.method), ['resize', 'offset']);
      final resize = calls[0].arguments as Map;
      expect(resize['id'], 7);
      expect(resize['width'], 100);
      expect(resize['height'], 50);
      final offset = calls[1].arguments as Map;
      expect(offset['id'], 7);
      expect(offset['top'], 20);
      expect(offset['left'], 10);
    });

    test('B2 相同尺寸与位置**不重复发**（每帧刷通道会拖慢渲染）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );
      calls.clear();

      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );

      expect(calls, isEmpty, reason: '相同尺寸/位置必须去重');
    });

    test('B3 只换尺寸 → 只发 resize', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );
      calls.clear();

      await controller.updateLayout(
        size: const Size(200, 100),
        offset: const Offset(10, 20),
      );

      expect(calls.map((c) => c.method), ['resize']);
      expect((calls.single.arguments as Map)['width'], 200);
    });

    test('B4 只换位置 → 只发 offset', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );
      calls.clear();

      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(30, 40),
      );

      expect(calls.map((c) => c.method), ['offset']);
      final args = calls.single.arguments as Map;
      expect(args['top'], 40);
      expect(args['left'], 30);
    });

    test('B5 未 create 前不发通道（守卫）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );
      expect(calls, isEmpty);
    });

    test('B6 空尺寸忽略（布局未就绪时不发 resize）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      calls.clear();

      await controller.updateLayout(size: Size.zero, offset: Offset.zero);
      expect(calls, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. dispose：释放
  // ═══════════════════════════════════════════════════════════════

  group('C dispose 释放', () {
    test('C1 dispose 带 hybrid:true', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      calls.clear();

      await controller.dispose();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'dispose');
      final args = calls.single.arguments as Map;
      expect(args['id'], 7);
      expect(args['hybrid'], isTrue);
    });

    test('C2 dispose 幂等（重复调用不重复发）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      await controller.dispose();
      calls.clear();

      await controller.dispose();
      expect(calls, isEmpty);
    });

    test('C3 未 create 就 dispose → 不发通道（无 id 可释放）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.dispose();
      expect(calls, isEmpty);
    });

    test('C4 dispose 后 updateLayout 静默（不碰已释放视图）', () async {
      final controller = createHimiMpvOhosControllerForTest(viewId: 7);
      await controller.create();
      await controller.dispose();
      calls.clear();

      await controller.updateLayout(
        size: const Size(100, 50),
        offset: const Offset(10, 20),
      );
      expect(calls, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 跨平台约束锁死（不得回退到 Flutter-OH 专属 API）
  // ═══════════════════════════════════════════════════════════════

  group('D 跨平台可编译约束', () {
    const src = 'plugins/himi_mpv_ohos/lib/himi_mpv_surface_view.dart';
    late String code;

    setUpAll(() {
      code = File(src).readAsStringSync();
    });

    test('D1 不得使用 Flutter-OH 专属 API（否则官方 Flutter 编译失败）', () {
      // 去掉注释再检查——注释里提到旧 API 名字是「说明为什么弃用」，
      // 不算使用（真正要防的是代码里调它）。
      final codeOnly = code
          .split('\n')
          .where((line) {
            final t = line.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      // 旧实现的 API，只存在于鸿蒙分支 SDK
      expect(codeOnly, isNot(contains('initExpensiveOhosView')));
      expect(codeOnly, isNot(contains('OhosViewController')));
    });

    test('D2 走标准 flutter/platform_views 通道', () {
      expect(code, contains("SystemChannels.platform_views"));
      expect(code, contains("'create'"));
      expect(code, contains("'resize'"));
      expect(code, contains("'offset'"));
      expect(code, contains("'dispose'"));
    });

    test('D3 用 PlatformViewLink + PlatformViewSurface（不是占位 Widget）', () {
      // Surface 模式白屏回归：普通 Widget 只画占位，必须 PlatformViewSurface
      expect(code, contains('PlatformViewLink'));
      expect(code, contains('PlatformViewSurface'));
      expect(code, contains('PlatformViewHitTestBehavior.transparent'));
    });

    test('D4 viewType 常量为 himi_mpv_surface', () {
      expect(HimiMpvSurfaceView.viewType, 'himi_mpv_surface');
    });

    test('D5 布局控制接口公开（测试入口，生产走 PlatformViewLink）', () {
      expect(code, contains('abstract interface class HimiMpvOhosLayoutController'));
      expect(code, contains('createHimiMpvOhosControllerForTest'));
      expect(code, contains('@visibleForTesting'));
    });
  });
}
