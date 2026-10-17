import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/device_profile.dart';
import 'package:himi_syncwatch/services/dolby_vision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const probeChannel = MethodChannel('himi/device_capability');

  tearDown(() {
    DeviceProfileService.isAndroidOverride = null;
    DeviceProfileService.abiOverride = null;
    DolbyVisionService.isAndroidOverride = null;
    DolbyVisionService.resetCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(probeChannel, null);
  });

  group('DisplayCapabilities（显示 HDR 能力解析）', () {
    test('解析 hdrTypes/hdr/亮度并生成展示串', () {
      final d = DisplayCapabilities.fromMap(const {
        'hdrTypes': ['hdr10', 'hlg'],
        'hdr': false,
        'maxLuminance': 420.0,
      });
      expect(d.hdrCapable, isTrue);
      expect(d.supportsHdr10, isTrue);
      expect(d.supportsHlg, isTrue);
      expect(d.supportsDolbyVision, isFalse);
      expect(d.display, contains('hdr10/hlg'));
      expect(d.display, contains('420nits'));
    });

    test('SDR 显示 → 不支持；探测失败 → 展示错误', () {
      expect(DisplayCapabilities.fromMap(const {}).hdrCapable, isFalse);
      expect(DisplayCapabilities.fromMap(const {}).display, '不支持（SDR 显示）');
      final err = DisplayCapabilities.fromMap(const {'displayError': 'binder'});
      expect(err.display, contains('binder'));
    });

    test('当前 HDR 模式（hdr=true 但类型为空）→ 具备能力', () {
      final d = DisplayCapabilities.fromMap(const {'hdr': true});
      expect(d.hdrCapable, isTrue);
      expect(d.display, contains('当前 HDR 模式'));
    });
  });

  group('GlCapabilities（EGL/GL 探针结果）', () {
    test('fromMap 标记 tested 并解析纹理结果', () {
      final g = GlCapabilities.fromMap(const {
        'eglOk': true,
        'chooseConfigOk': true,
        'gles3Ok': true,
        'renderer': 'Mali-G610',
        'glVersion': 'OpenGL ES 3.2',
        'textureR16Ok': true,
        'textureRgba16fOk': false,
        'textureRgb10a2Ok': true,
      });
      expect(g.tested, isTrue);
      expect(g.eglOk, isTrue);
      expect(g.gles3Ok, isTrue);
      expect(g.tenBitTextureOk, isTrue);
      expect(g.display, contains('Mali-G610'));
      expect(g.display, contains('GL ES3 可用'));
      expect(g.display, contains('10-bit 纹理可用'));
    });

    test('仅 ES2（gles3Ok=false）→ 展示不可用且纹理默认 false', () {
      final g = GlCapabilities.fromMap(const {
        'eglOk': true,
        'chooseConfigOk': true,
        'gles3Ok': false,
        'renderer': 'Mali-450 MP',
        'glVersion': 'OpenGL ES 2.0',
        'textureR16Ok': false,
        'textureRgba16fOk': false,
        'textureRgb10a2Ok': false,
      });
      expect(g.gles3Ok, isFalse);
      expect(g.tenBitTextureOk, isFalse);
      expect(g.display, contains('仅 GL ES2（Erika 不可用）'));
    });

    test('EGL 失败 → 展示错误；未探测 → 未探测', () {
      final g = GlCapabilities.fromMap(const {
        'eglOk': false,
        'error': 'eglChooseConfig 0x3004',
      });
      expect(g.tested, isTrue);
      expect(g.tenBitTextureOk, isFalse);
      expect(g.display, contains('0x3004'));
      expect(GlCapabilities.unknown.tested, isFalse);
      expect(GlCapabilities.unknown.display, '未探测');
    });

    test('10-bit 纹理全失败 → tenBitTextureOk=false', () {
      final g = GlCapabilities.fromMap(const {
        'eglOk': true,
        'textureR16Ok': false,
        'textureRgba16fOk': false,
        'textureRgb10a2Ok': false,
      });
      expect(g.tenBitTextureOk, isFalse);
      expect(g.display, contains('10-bit 纹理不可用'));
    });
  });

  group('DeviceProfile（能力派生判定）', () {
    const hdr10Display = DisplayCapabilities(hdrTypes: ['hdr10']);

    test('erikaHdrCapable：未探测 Android 保历史默认 true', () {
      const p = DeviceProfile(android: true);
      expect(p.erikaHdrCapable(TargetPlatform.android), isTrue);
      expect(p.erikaHdrCapable(TargetPlatform.iOS), isTrue);
      expect(p.erikaHdrCapable(TargetPlatform.windows), isFalse);
    });

    test('erikaHdrCapable：已探测 Android 需 Vulkan + HDR 显示', () {
      final ok = DeviceProfile(
        android: true,
        probed: true,
        vulkanVersion: (1 << 22) | (1 << 12),
        display: hdr10Display,
      );
      expect(ok.erikaHdrCapable(TargetPlatform.android), isTrue);
      expect(ok.vulkanDisplay, '1.1.0');

      final noVulkan = DeviceProfile(
        android: true,
        probed: true,
        display: hdr10Display,
      );
      expect(noVulkan.erikaHdrCapable(TargetPlatform.android), isFalse);

      final noHdr = DeviceProfile(
        android: true,
        probed: true,
        vulkanVersion: 1 << 22,
        display: DisplayCapabilities.unknown,
      );
      expect(noHdr.erikaHdrCapable(TargetPlatform.android), isFalse);
    });

    test('erikaRenderable：Vulkan 或 GLES3 任一即可渲染', () {
      const gles3 = GlCapabilities(tested: true, eglOk: true, gles3Ok: true);

      // Vulkan 有（无论渲染上下文如何）→ 可渲染
      final vulkanOnly = DeviceProfile(
        android: true,
        probed: true,
        vulkanVersion: 1 << 22,
        gl: const GlCapabilities(tested: true, eglOk: true),
      );
      expect(vulkanOnly.erikaRenderable(TargetPlatform.android), isTrue);

      // 无 Vulkan 但 GLES3 → 可渲染（SDR 回退场景）
      final gles3Only = DeviceProfile(
        android: true,
        probed: true,
        gl: gles3,
      );
      expect(gles3Only.erikaRenderable(TargetPlatform.android), isTrue);

      // 双无（ES2-only 盒子）→ 不可渲染
      final box = DeviceProfile(
        android: true,
        probed: true,
        gl: const GlCapabilities(tested: true, eglOk: true),
      );
      expect(box.erikaRenderable(TargetPlatform.android), isFalse);

      // 未探测 / 探测整体失败 → 保历史 true（不误降级手机）
      expect(
        const DeviceProfile(android: true)
            .erikaRenderable(TargetPlatform.android),
        isTrue,
      );
      expect(
        const DeviceProfile(android: true, probed: true, error: 'timeout')
            .erikaRenderable(TargetPlatform.android),
        isTrue,
      );
      expect(DeviceProfile.unknown.erikaRenderable(TargetPlatform.iOS), isTrue);
      expect(
        DeviceProfile.unknown.erikaRenderable(TargetPlatform.windows),
        isFalse,
      );
    });

    test('mdkHdrPassthroughCapable：声明 HDR10/HLG/DV 任一即可', () {
      expect(
        const DeviceProfile(display: hdr10Display).mdkHdrPassthroughCapable,
        isTrue,
      );
      expect(
        const DeviceProfile(
          display: DisplayCapabilities(hdrTypes: ['dolbyVision']),
        ).mdkHdrPassthroughCapable,
        isTrue,
      );
      expect(
        const DeviceProfile(display: DisplayCapabilities(hdrTypes: ['hlg']))
            .mdkHdrPassthroughCapable,
        isTrue,
      );
      expect(DeviceProfile.unknown.mdkHdrPassthroughCapable, isFalse);
    });

    test('eglBroken：持久标记 / 探针明确失败 / 未实测不误判', () {
      expect(DeviceProfile.unknown.eglBroken(eglFaultSeen: true), isTrue);
      expect(DeviceProfile.unknown.eglBroken(eglFaultSeen: false), isFalse);

      const broken = DeviceProfile(
        android: true,
        probed: true,
        gl: GlCapabilities(tested: true, eglOk: false, error: '0x3004'),
      );
      expect(broken.eglBroken(eglFaultSeen: false), isTrue);

      const ok = DeviceProfile(
        android: true,
        probed: true,
        gl: GlCapabilities(tested: true, eglOk: true),
      );
      expect(ok.eglBroken(eglFaultSeen: false), isFalse);

      // 探针未取得结果（超时）→ 不判定故障（避免误置位直写标记）
      const timeout = DeviceProfile(android: true, probed: true);
      expect(timeout.eglBroken(eglFaultSeen: false), isFalse);
    });

    test('tenBitGlBroken：仅「EGL 正常但 10-bit 纹理全失败」为 true', () {
      const broken = DeviceProfile(
        android: true,
        probed: true,
        gl: GlCapabilities(tested: true, eglOk: true),
      );
      expect(broken.tenBitGlBroken, isTrue);
      expect(broken.gl10BitOk, isFalse);

      const ok = DeviceProfile(
        android: true,
        probed: true,
        gl: GlCapabilities(tested: true, eglOk: true, textureR16Ok: true),
      );
      expect(ok.tenBitGlBroken, isFalse);
      expect(ok.gl10BitOk, isTrue);

      // EGL 已坏 → 由 eglFault 路径接管，不在此重复介入
      const eglDown = DeviceProfile(
        android: true,
        probed: true,
        gl: GlCapabilities(tested: true, eglOk: false),
      );
      expect(eglDown.tenBitGlBroken, isFalse);

      // 未实测不介入
      expect(DeviceProfile.unknown.tenBitGlBroken, isFalse);
    });
  });

  group('DeviceProfileService.probe（启动评估）', () {
    test('非 Android：返回未探测画像 + ABI', () async {
      DeviceProfileService.isAndroidOverride = false;
      DeviceProfileService.abiOverride = 'androidArm64';
      final p = await DeviceProfileService.instance.probe();
      expect(p.probed, isFalse);
      expect(p.abi, 'androidArm64');
      expect(p.is64Bit, isTrue);
      expect(p.erikaHdrCapable(TargetPlatform.android), isTrue);
    });

    test('Android：解析原生探针 map（EGL 坏 + 无 Vulkan 盒子画像）', () async {
      DeviceProfileService.isAndroidOverride = true;
      DeviceProfileService.abiOverride = 'androidArm';
      DolbyVisionService.isAndroidOverride = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(probeChannel, (call) async {
        expect(call.method, 'probe');
        return <Object?, Object?>{
          'sdkInt': 30,
          'soc': 'rk3528',
          'hdrTypes': ['hdr10', 'hlg'],
          'hdr': false,
          'maxLuminance': 400.0,
          'hevcHdr10': true,
          'gl': {
            'eglOk': false,
            'chooseConfigOk': false,
            'error': 'eglChooseConfig 0x3004',
          },
        };
      });

      final p = await DeviceProfileService.instance.probe();
      expect(p.probed, isTrue);
      expect(p.android, isTrue);
      expect(p.is64Bit, isFalse);
      expect(p.soc, 'rk3528');
      expect(p.sdkInt, 30);
      expect(p.hevcHdr10, isTrue);
      expect(p.display.supportsHdr10, isTrue);
      expect(p.vulkanOk, isFalse);
      expect(p.gl.tested, isTrue);
      expect(p.eglBroken(eglFaultSeen: false), isTrue);
      expect(p.tenBitGlBroken, isFalse);
      // 有 HDR 显示声明 → mdk 直写可透传；无 Vulkan 且无 GLES3 → Erika 不可用
      expect(p.mdkHdrPassthroughCapable, isTrue);
      expect(p.erikaHdrCapable(TargetPlatform.android), isFalse);
      expect(p.erikaRenderable(TargetPlatform.android), isFalse);
      expect(p.summary, contains('SoC=rk3528'));
    });

    test('Android：通道超时 → probed+error，不误判 EGL 故障', () async {
      DeviceProfileService.isAndroidOverride = true;
      DeviceProfileService.abiOverride = 'androidArm64';
      DolbyVisionService.isAndroidOverride = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              probeChannel, (call) => Completer<Object?>().future);

      final p = await DeviceProfileService.instance
          .probe(timeout: const Duration(milliseconds: 50));
      expect(p.probed, isTrue);
      expect(p.error, isNotNull);
      expect(p.gl.tested, isFalse);
      expect(p.eglBroken(eglFaultSeen: false), isFalse);
      expect(p.tenBitGlBroken, isFalse);
      // 探针失败不阻塞历史行为：Android 未实测 → Erika 默认可用
      expect(p.erikaHdrCapable(TargetPlatform.android), isTrue);
      expect(p.erikaRenderable(TargetPlatform.android), isTrue);
    });
  });
}
