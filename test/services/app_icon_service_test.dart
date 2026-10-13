import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/app_icon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppIconService.options', () {
    test('默认在首位 + 3 个备用，id 唯一', () {
      expect(AppIconService.options, hasLength(4));
      expect(AppIconService.options.first.id, isNull);
      expect(
        AppIconService.options.map((o) => o.id).toList(),
        [null, 'artistic', 'glass', 'neon'],
      );
      for (final o in AppIconService.options) {
        expect(o.asset, startsWith('assets/icons/'));
      }
    });
  });

  group('AppIconService.isSupported', () {
    test('Android / iOS 支持；其余不支持', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final p in const [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = p;
        expect(AppIconService.isSupported, isTrue, reason: '$p 支持');
      }
      for (final p in const [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(AppIconService.isSupported, isFalse, reason: '$p 不支持');
      }
    });
  });

  group('platformIconName（id → 平台参数）', () {
    test('Android：默认=applicationId.DEFAULT，备用=applicationId.icon_<id>', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
          AppIconService.platformIconName(null), 'com.himi.syncwatch.DEFAULT');
      expect(AppIconService.platformIconName('artistic'),
          'com.himi.syncwatch.icon_artistic');
      expect(AppIconService.platformIconName('neon'),
          'com.himi.syncwatch.icon_neon');
    });

    test('iOS：默认=null，备用=CFBundleAlternateIcons 键', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(AppIconService.platformIconName(null), isNull);
      expect(AppIconService.platformIconName('glass'), 'glass');
    });
  });

  group('idFromPlatformName（平台返回 → id）', () {
    test('Android：别名全限定名 → id，DEFAULT/未知 → null', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
          AppIconService.idFromPlatformName('com.himi.syncwatch.icon_artistic'),
          'artistic');
      expect(AppIconService.idFromPlatformName('com.himi.syncwatch.icon_neon'),
          'neon');
      expect(AppIconService.idFromPlatformName('com.himi.syncwatch.DEFAULT'),
          isNull);
      expect(AppIconService.idFromPlatformName('com.himi.syncwatch.icon_zzz'),
          isNull);
    });

    test('iOS：键 → id，null/未知 → null', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(AppIconService.idFromPlatformName('glass'), 'glass');
      expect(AppIconService.idFromPlatformName(null), isNull);
      expect(AppIconService.idFromPlatformName(''), isNull);
      expect(AppIconService.idFromPlatformName('zzz'), isNull);
    });
  });

  group('blacklistArgs（Android 立即分支：设备自身命中）', () {
    test('有设备标识 → 用自身值（品牌/厂商/型号）', () {
      final a = AppIconService.blacklistArgs(
        brand: 'Redmi',
        manufacturer: 'Xiaomi',
        model: '23127PN0CC',
      );
      expect(a.brands, ['Redmi']);
      expect(a.manufactures, ['Xiaomi']);
      expect(a.models, ['23127PN0CC']);
    });

    test('空标识被忽略；全空兜底小米/红米', () {
      final partial =
          AppIconService.blacklistArgs(manufacturer: 'Xiaomi', brand: ' ');
      expect(partial.manufactures, ['Xiaomi']);
      expect(partial.brands, isEmpty);
      expect(partial.models, isEmpty);

      final empty = AppIconService.blacklistArgs();
      expect(empty.manufactures, ['Xiaomi']);
      expect(empty.brands, ['Redmi']);
      expect(empty.models, isEmpty);
    });
  });

  group('apply iOS：静默不回传 → 读系统验证 → 不一致回退公开 API', () {
    late List<MethodCall> calls;
    late MethodChannel channel;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      AppIconService.iosSilentSettle = const Duration(milliseconds: 5);
      AppIconService.iosVerifyTimeout = const Duration(milliseconds: 50);
      calls = <MethodCall>[];
      channel = const MethodChannel('flutter_dynamic_icon_plus');
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        AppIconService.iosSilentSettle = const Duration(milliseconds: 500);
        AppIconService.iosVerifyTimeout = const Duration(seconds: 3);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
    });

    /// silent: true 的 set 永不完成；silent: false / 读回按 [onPublicSet] /
    /// [currentIcon] 应答。
    void mockPlugin({
      required String? currentIcon,
    }) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'setAlternateIconName') {
          final silent = (call.arguments as Map)['isSilent'] as bool?;
          if (silent == true) {
            // 复现插件 bug：静默分支不回传 result → Future 永不完成。
            return Completer<Object?>().future;
          }
          return null; // 公开 API：正常回传成功
        }
        if (call.method == 'getAlternateIconName') {
          return currentIcon;
        }
        return null;
      });
    }

    test('系统读回与期望一致 → 成功，不触发公开 API 回退', () async {
      mockPlugin(currentIcon: 'artistic');

      await AppIconService.apply('artistic');

      final sets = calls
          .where((c) => c.method == 'setAlternateIconName')
          .toList(growable: false);
      expect(sets, hasLength(1), reason: '读回一致时不应再调公开 API');
      expect(sets.single.arguments['isSilent'], isTrue);
      expect(sets.single.arguments['iconName'], 'artistic');
    });

    test('系统读回不一致（假成功/静默失败）→ 回退公开 API isSilent:false',
        () async {
      mockPlugin(currentIcon: null); // 系统仍是默认图标

      await AppIconService.apply('neon');

      final sets = calls
          .where((c) => c.method == 'setAlternateIconName')
          .toList(growable: false);
      expect(sets, hasLength(2), reason: '静默 + 回退两次');
      expect(sets.first.arguments['isSilent'], isTrue);
      expect(sets.last.arguments['isSilent'], isFalse);
      expect(sets.last.arguments['iconName'], 'neon');
    });

    test('公开 API 回退失败 → 抛出（UI 据此 toast）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'setAlternateIconName') {
          final silent = (call.arguments as Map)['isSilent'] as bool?;
          if (silent == true) {
            return Completer<Object?>().future;
          }
          throw PlatformException(code: 'Unavailable', message: 'no icon');
        }
        if (call.method == 'getAlternateIconName') return null;
        return null;
      });

      await expectLater(
        AppIconService.apply('glass'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('还原默认（name=null）：读回 null 即一致，不回退', () async {
      mockPlugin(currentIcon: null);

      await AppIconService.apply(null);

      final sets = calls
          .where((c) => c.method == 'setAlternateIconName')
          .toList(growable: false);
      expect(sets, hasLength(1));
      expect(sets.single.arguments['iconName'], isNull);
      expect(sets.single.arguments['isSilent'], isTrue);
    });
  });
}
