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

  test('Android / Windows 默认 MPV；Windows 移除 media_kit（646.1）', () {
    PlayerEngineFactory.debugIsOhosOverride = false;

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
      isTrue,
    );
    // 2026-10 起 Android 默认内核改为 MPV（原 MDK 保留为可选内核）。
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);

    // 646.1：Windows 加回 MPV 并设为默认——原生顶层窗口（WS_POPUP）+
    // vo=gpu-next 实现 HDR 直出；media_kit 移除（Flutter 纹理必崩 0x1551f）。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final winEngines = PlayerEngineFactory.supportedEngines();
    expect(winEngines, contains(PlayerEngine.mpv));
    expect(winEngines, contains(PlayerEngine.mdk));
    expect(winEngines, contains(PlayerEngine.erika));
    expect(winEngines, isNot(contains(PlayerEngine.mediaKit)));
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    // 旧存档选过 media_kit → 已移除，回退到平台默认（MPV）。
    expect(
      PlayerEngineFactory.resolveSelectedEngine('media_kit'),
      PlayerEngine.mpv,
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
