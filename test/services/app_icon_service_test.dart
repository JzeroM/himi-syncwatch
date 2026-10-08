import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/app_icon_service.dart';

void main() {
  group('AppIconService.options', () {
    test('默认在首位 + 3 个备用，id 唯一', () {
      expect(AppIconService.options, hasLength(4));
      expect(AppIconService.options.first.id, isNull);
      expect(
        AppIconService.options.map((o) => o.id).toList(),
        [null, 'aurora', 'metal', 'neon'],
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
      expect(AppIconService.platformIconName('aurora'),
          'com.himi.syncwatch.icon_aurora');
      expect(AppIconService.platformIconName('neon'),
          'com.himi.syncwatch.icon_neon');
    });

    test('iOS：默认=null，备用=CFBundleAlternateIcons 键', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(AppIconService.platformIconName(null), isNull);
      expect(AppIconService.platformIconName('metal'), 'metal');
    });
  });

  group('idFromPlatformName（平台返回 → id）', () {
    test('Android：别名全限定名 → id，DEFAULT/未知 → null', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
          AppIconService.idFromPlatformName('com.himi.syncwatch.icon_aurora'),
          'aurora');
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
      expect(AppIconService.idFromPlatformName('metal'), 'metal');
      expect(AppIconService.idFromPlatformName(null), isNull);
      expect(AppIconService.idFromPlatformName(''), isNull);
      expect(AppIconService.idFromPlatformName('zzz'), isNull);
    });
  });
}
