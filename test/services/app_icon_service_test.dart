import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/app_icon_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppIconService.options', () {
    test('默认在首位 + 3 个备用，id 唯一', () {
      expect(AppIconService.options, hasLength(4));
      expect(AppIconService.options.first.id, isNull);
      expect(
        AppIconService.options.map((o) => o.id).toList(),
        [null, 'artistic', 'mint', 'glass'],
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
      expect(AppIconService.platformIconName('mint'),
          'com.himi.syncwatch.icon_mint');
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
      expect(AppIconService.idFromPlatformName('com.himi.syncwatch.icon_mint'),
          'mint');
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

  group('apply iOS：只走公开 API 单次调用（isSilent:false）', () {
    late List<MethodCall> calls;
    late MethodChannel channel;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      calls = <MethodCall>[];
      channel = const MethodChannel('flutter_dynamic_icon_plus');
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
    });

    /// 公开 API 按 [error] 应答（null = 成功）。
    void mockPlugin({PlatformException? error}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'setAlternateIconName') {
          final silent = (call.arguments as Map)['isSilent'] as bool?;
          expect(silent, isFalse, reason: '禁止静默分支：插件 1.4.1 静默调用从不回传 result');
          if (error != null) throw error;
          return null;
        }
        return null;
      });
    }

    test('切换备用图标：单次公开调用、isSilent=false、name 正确', () async {
      mockPlugin();

      await AppIconService.apply('artistic');

      final sets = calls
          .where((c) => c.method == 'setAlternateIconName')
          .toList(growable: false);
      expect(sets, hasLength(1), reason: '只调一次，无静默+回退双打');
      expect(sets.single.arguments['isSilent'], isFalse);
      expect(sets.single.arguments['iconName'], 'artistic');
    });

    test('还原默认：iconName=null 同样走公开 API', () async {
      mockPlugin();

      await AppIconService.apply(null);

      final sets = calls
          .where((c) => c.method == 'setAlternateIconName')
          .toList(growable: false);
      expect(sets, hasLength(1));
      expect(sets.single.arguments['iconName'], isNull);
      expect(sets.single.arguments['isSilent'], isFalse);
    });

    test('插件回传错误 → 抛出（UI 据此 toast 带详情）', () async {
      mockPlugin(
        error: PlatformException(code: 'Failed', message: 'no icon'),
      );

      await expectLater(
        AppIconService.apply('glass'),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('iOS 备用图标资源', () {
    const alternateIds = ['artistic', 'mint', 'glass'];

    test('每个 appiconset 含完整尺寸 + 1024 营销图标（iOS 26 图标堆栈）', () {
      for (final id in alternateIds) {
        final dir = Directory('ios/Runner/Assets.xcassets/$id.appiconset');
        expect(dir.existsSync(), isTrue, reason: '${dir.path} 缺失');
        final contents = jsonDecode(
          File('${dir.path}/Contents.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final images =
            (contents['images'] as List).cast<Map<String, dynamic>>();
        expect(images.length, greaterThanOrEqualTo(18), reason: id);

        final slots = images
            .map((i) => '${i['idiom']}/${i['size']}@${i['scale']}')
            .toSet();
        for (final slot in const [
          'iphone/60x60@2x',
          'iphone/60x60@3x',
          'ipad/76x76@1x',
          'ipad/76x76@2x',
          'ipad/83.5x83.5@2x',
          'ios-marketing/1024x1024@1x',
        ]) {
          expect(slots, contains(slot), reason: '$id 缺少 $slot');
        }

        for (final item in images) {
          final file = File('${dir.path}/${item['filename']}');
          expect(file.existsSync(), isTrue, reason: file.path);
          final decoded = img.decodePng(file.readAsBytesSync());
          expect(decoded, isNotNull, reason: file.path);
          final side =
              (double.parse((item['size'] as String).split('x').first) *
                      int.parse((item['scale'] as String)[0]))
                  .round();
          expect(decoded!.width, side, reason: file.path);
          expect(decoded.height, side, reason: file.path);
        }
      }
    });
  });
}
