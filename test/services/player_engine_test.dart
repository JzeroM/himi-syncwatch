import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('PlayerEngineFactory.resolveErikaOutputMode（按内容路由）', () {
    test('非 HDR → SDR（全平台）', () {
      for (final p in TargetPlatform.values) {
        expect(
          PlayerEngineFactory.resolveErikaOutputMode(hdr: false, platform: p),
          ErikaOutputMode.sdr,
          reason: '$p',
        );
      }
    });

    test('HDR：Android → extendedLinear', () {
      expect(
        PlayerEngineFactory.resolveErikaOutputMode(
            hdr: true, platform: TargetPlatform.android),
        ErikaOutputMode.extendedLinear,
      );
    });

    test('HDR：iOS/macOS/其他 → auto（协商 EDR/HDR10）', () {
      for (final p in const [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(
          PlayerEngineFactory.resolveErikaOutputMode(hdr: true, platform: p),
          ErikaOutputMode.auto,
          reason: '$p',
        );
      }
    });
  });

  group('PlayerEngineFactory.supportedEngines（平台感知）', () {
    test('TV 模式仅 MDK', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.supportedEngines(tvMode: true),
          [PlayerEngine.mdk]);
    });

    test('非 TV：Android/iOS/macOS 含 Erika；Linux 不含（首版无预编译）', () {
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        final e = PlayerEngineFactory.supportedEngines(tvMode: false);
        expect(e, contains(PlayerEngine.mdk), reason: '$p');
        expect(e, contains(PlayerEngine.erika), reason: '$p');
        expect(e, isNot(contains(PlayerEngine.mediaKit)), reason: '$p');
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final linux = PlayerEngineFactory.supportedEngines(tvMode: false);
      expect(linux, contains(PlayerEngine.mdk));
      expect(linux, isNot(contains(PlayerEngine.erika)));
      expect(linux, isNot(contains(PlayerEngine.mediaKit)));
    });

    test('Windows 非 TV：MDK + media_kit（无 Erika）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final e = PlayerEngineFactory.supportedEngines(tvMode: false);
      expect(e, [PlayerEngine.mdk, PlayerEngine.mediaKit]);
      expect(e, isNot(contains(PlayerEngine.erika)));
    });
  });

  group('PlayerEngineFactory.isSupported', () {
    test('非 Windows 不支持 media_kit；Windows 支持', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.mediaKit, tvMode: false),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.mediaKit, tvMode: false),
        isTrue,
      );
    });

    test('Windows/Linux 不支持 Erika；Android 支持', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika, tvMode: false),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika, tvMode: false),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika, tvMode: false),
        isTrue,
      );
    });

    test('TV 模式下 Erika 不支持', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika, tvMode: true),
        isFalse,
      );
    });
  });
}
