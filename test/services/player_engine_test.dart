import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('PlayerEngineFactory.supportedEngines（平台感知）', () {
    test('TV 模式仅 MDK', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.supportedEngines(tvMode: true),
          [PlayerEngine.mdk]);
    });

    test('非 TV 非 Windows：MDK + Erika，不含 media_kit', () {
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        final e = PlayerEngineFactory.supportedEngines(tvMode: false);
        expect(e, contains(PlayerEngine.mdk), reason: '$p');
        expect(e, contains(PlayerEngine.erika), reason: '$p');
        expect(e, isNot(contains(PlayerEngine.mediaKit)), reason: '$p');
      }
    });

    test('Windows 非 TV：MDK + Erika + media_kit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final e = PlayerEngineFactory.supportedEngines(tvMode: false);
      expect(
        e,
        containsAll([
          PlayerEngine.mdk,
          PlayerEngine.erika,
          PlayerEngine.mediaKit,
        ]),
      );
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

    test('TV 模式下 Erika 不支持', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika, tvMode: true),
        isFalse,
      );
    });
  });
}
