import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() {
    PlayerEngineFactory.debugIsOhosOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('HarmonyOS 仅支持并默认 MPV', () {
    PlayerEngineFactory.debugIsOhosOverride = true;

    expect(PlayerEngineFactory.supportedEngines(), [PlayerEngine.mpv]);
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isTrue);
    expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isFalse);
    expect(
      PlayerEngineFactory.resolveSelectedEngine('mdk'),
      PlayerEngine.mpv,
    );
  });

  test('Android 与 Windows 默认 MPV；iOS 不注册', () {
    PlayerEngineFactory.debugIsOhosOverride = false;

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
      isTrue,
    );
    // 2026-10 起 Android 默认内核改为 MPV（原 MDK 保留为可选内核）。
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
      isTrue,
    );
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mediaKit),
      isFalse,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
      isFalse,
    );
  });

  test('MPV 引擎 id 与短名', () {
    expect(PlayerEngine.fromId('mpv'), PlayerEngine.mpv);
    expect(PlayerEngine.mpv.shortLabel, 'MPV');
  });
}
