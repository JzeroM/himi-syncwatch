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

  test('Android 默认 MPV；641 起 Windows 默认 media_kit 且移除 MPV', () {
    PlayerEngineFactory.debugIsOhosOverride = false;

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
      isTrue,
    );
    // 2026-10 起 Android 默认内核改为 MPV（原 MDK 保留为可选内核）。
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);

    // 641：Windows 改用 media_kit（MPV 在 Windows 上 texture 返回崩溃、
    // surface 灰屏），MPV 从可选列表移除，MDK 保留。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final winEngines = PlayerEngineFactory.supportedEngines();
    expect(winEngines, contains(PlayerEngine.mediaKit));
    expect(winEngines, contains(PlayerEngine.mdk));
    expect(winEngines, contains(PlayerEngine.erika));
    expect(winEngines, isNot(contains(PlayerEngine.mpv)));
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mediaKit);
    // 旧存档选过 mpv → 自动回退到新默认（media_kit）。
    expect(
      PlayerEngineFactory.resolveSelectedEngine('mpv'),
      PlayerEngine.mediaKit,
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
