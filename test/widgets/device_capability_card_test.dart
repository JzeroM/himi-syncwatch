import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/device_profile_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/device_profile.dart';
import 'package:himi_syncwatch/services/dolby_vision_service.dart';
import 'package:himi_syncwatch/widgets/settings/device_capability_card.dart';

import '../helpers/test_fakes.dart';

const _probeChannel = MethodChannel('himi/device_capability');

/// 盒子画像：32 位 APK + EGL 坏（3004）+ 声明 HDR10 + 无 Vulkan。
DeviceProfile _boxProfile() => DeviceProfile.fromProbe(
      raw: const <Object?, Object?>{
        'sdkInt': 30,
        'soc': 'rk3528',
        'hdrTypes': ['hdr10', 'hlg'],
        'hdr': false,
        'hevcHdr10': true,
        'gl': {
          'eglOk': false,
          'chooseConfigOk': false,
          'error': 'eglChooseConfig 0x3004',
        },
      },
      abi: 'androidArm',
    );

Widget _wrap({
  required DeviceProfile profile,
  AppSettings settings = const AppSettings(),
  FakeSettingsNotifier? notifier,
}) {
  final n = notifier ?? FakeSettingsNotifier(settings);
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => n),
      deviceProfileProvider.overrideWith((ref) => profile),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DeviceCapabilityCard()),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DeviceProfileService.isAndroidOverride = null;
    DeviceProfileService.abiOverride = null;
    DolbyVisionService.isAndroidOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_probeChannel, null);
  });

  group('DeviceCapabilityCard（能力评估卡片）', () {
    testWidgets('已评估设备：展示运行环境/显示/GL/Vulkan/策略预览', (tester) async {
      await tester.pumpWidget(_wrap(profile: _boxProfile()));
      await tester.pumpAndSettle();

      expect(find.text('设备能力评估'), findsOneWidget);
      expect(find.text('已评估'), findsOneWidget);
      expect(find.textContaining('32 位'), findsOneWidget);
      expect(find.textContaining('rk3528'), findsOneWidget);
      expect(find.textContaining('hdr10/hlg'), findsOneWidget);
      expect(find.textContaining('EGL 不可用'), findsOneWidget);
      expect(
        find.text('无（Erika HDR 不可用，HDR 走 MDK）'),
        findsOneWidget,
      );
      // 策略预览：无 Vulkan → HDR 走 MDK 直写；EGL 坏但未持久标记
      expect(find.textContaining('HDR→MDK'), findsOneWidget);
      expect(find.textContaining('10-bit SDR→GL'), findsOneWidget);
    });

    testWidgets('未评估设备：展示未评估兜底说明', (tester) async {
      await tester.pumpWidget(_wrap(profile: DeviceProfile.unknown));
      await tester.pumpAndSettle();

      expect(find.text('未评估'), findsOneWidget);
      expect(find.textContaining('未执行原生评估'), findsOneWidget);
    });

    testWidgets('持久兼容标记置位：GL 正常时仍提示已置位', (tester) async {
      await tester.pumpWidget(_wrap(
        profile: const DeviceProfile(
          android: true,
          probed: true,
          gl: GlCapabilities(tested: true, eglOk: true, textureR16Ok: true),
        ),
        settings: const AppSettings(eglFaultSeen: true),
      ));
      await tester.pumpAndSettle();

      // GL 行与策略预览各出现一次
      expect(find.textContaining('兼容标记已置位'), findsNWidgets(2));
    });

    testWidgets('重新评估：重跑探针并更新卡片与提示', (tester) async {
      DeviceProfileService.isAndroidOverride = true;
      DeviceProfileService.abiOverride = 'androidArm64';
      DolbyVisionService.isAndroidOverride = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_probeChannel, (call) async {
        return <Object?, Object?>{
          'sdkInt': 30,
          'soc': 'rk3528',
          'hdrTypes': ['hdr10'],
          'hdr': false,
          'hevcHdr10': true,
          'gl': {'eglOk': false, 'error': 'eglChooseConfig 0x3004'},
        };
      });

      await tester.pumpWidget(_wrap(profile: DeviceProfile.unknown));
      await tester.pumpAndSettle();
      expect(find.text('未评估'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('deviceCapabilityReprobe')));
      await tester.pumpAndSettle();

      expect(find.text('已评估'), findsOneWidget);
      expect(find.textContaining('64 位'), findsOneWidget);
      // SnackBar 摘要（含 SoC）
      expect(find.textContaining('SoC=rk3528'), findsOneWidget);
    });

    testWidgets('清除兼容标记：复位 eglFaultSeen 并重评', (tester) async {
      DeviceProfileService.isAndroidOverride = false;
      final notifier = FakeSettingsNotifier(
        const AppSettings(eglFaultSeen: true),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
          deviceProfileProvider.overrideWith((ref) => _boxProfile()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DeviceCapabilityCard()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(notifier.state.eglFaultSeen, isTrue);

      await tester.tap(find.byKey(const ValueKey('deviceCapabilityClearMark')));
      await tester.pumpAndSettle();

      expect(notifier.state.eglFaultSeen, isFalse);
      // 非 Android 重评（测试环境）→ EGL 结论不复现，提示已清除
      expect(find.textContaining('兼容标记已清除'), findsOneWidget);
    });
  });
}
