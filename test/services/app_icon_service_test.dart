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

  group('idFromPlatformName（平台返回 → id）', () {
    test('Android：id / 全限定别名 → id，DEFAULT/未知 → null', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
          AppIconService.idFromPlatformName('com.himi.syncwatch.icon_artistic'),
          'artistic');
      expect(AppIconService.idFromPlatformName('com.himi.syncwatch.icon_mint'),
          'mint');
      expect(AppIconService.idFromPlatformName('glass'), 'glass');
      expect(AppIconService.idFromPlatformName('default'), isNull);
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

  group('apply Android：自有通道归一化 + 启动自愈', () {
    late List<MethodCall> calls;
    late String current;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      calls = <MethodCall>[];
      current = 'default';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconService.androidChannel,
              (call) async {
        calls.add(call);
        switch (call.method) {
          case 'setIcon':
            current = (call.arguments as Map)['id'] as String;
            return true;
          case 'getIcon':
            return current;
          case 'supports':
            return true;
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AppIconService.androidChannel, null);
      });
    });

    test('切换备用图标：只传 id，不在 recreate 后回查', () async {
      await AppIconService.apply('mint');

      expect(calls.map((c) => c.method), ['setIcon']);
      expect(calls.first.arguments, {'id': 'mint'});
    });

    test('还原默认：传 default', () async {
      current = 'glass';
      await AppIconService.apply(null);

      expect(calls.map((c) => c.method), ['setIcon']);
      expect(calls.first.arguments, {'id': 'default'});
    });

    test('原生未确认成功 → 抛出', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppIconService.androidChannel,
              (call) async {
        if (call.method == 'setIcon') return false;
        return null;
      });

      await expectLater(
        AppIconService.apply('mint'),
        throwsA(isA<StateError>()),
      );
    });

    test('启动自愈：invalid 状态强制归一化', () async {
      current = 'invalid';
      await AppIconService.syncOnStart('glass');

      expect(calls.map((c) => c.method), ['getIcon', 'setIcon']);
      expect(calls.last.arguments, {'id': 'glass'});
    });

    test('启动自愈：默认态不触发切换', () async {
      current = 'default';
      await AppIconService.syncOnStart(null);

      expect(calls.map((c) => c.method), ['getIcon']);
    });

    test('未知 id → 参数错误，不触碰原生', () async {
      await expectLater(
        AppIconService.apply('unknown'),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls, isEmpty);
    });
  });

  group('apply iOS：只走公开 API 单次调用（isSilent:false）', () {
    late List<MethodCall> calls;
    late MethodChannel channel;
    String? current;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      calls = <MethodCall>[];
      current = null;
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
          current = (call.arguments as Map)['iconName'] as String?;
          return null;
        }
        if (call.method == 'getAlternateIconName') return current;
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
