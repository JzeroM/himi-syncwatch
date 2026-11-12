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

  test('681：Android 手机/Windows 均只 MPV', () {
    PlayerEngineFactory.debugIsOhosOverride = false;

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // 681：安卓手机收敛为仅 MPV（TV 才保留三引擎）
    expect(
      PlayerEngineFactory.supportedEngines(),
      <PlayerEngine>[PlayerEngine.mpv],
    );
    expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
    // TV 保留三引擎
    expect(
      PlayerEngineFactory.supportedEngines(tvMode: true),
      containsAll(<PlayerEngine>[
        PlayerEngine.mdk,
        PlayerEngine.erika,
        PlayerEngine.mpv,
      ]),
    );

    // 681：Windows 收敛为仅 MPV（Qt 独立窗口 + HDR 直出）
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final winEngines = PlayerEngineFactory.supportedEngines();
    expect(winEngines, <PlayerEngine>[PlayerEngine.mpv]);
    expect(winEngines, isNot(contains(PlayerEngine.mediaKit)));
    expect(winEngines, isNot(contains(PlayerEngine.mdk)));
    expect(winEngines, isNot(contains(PlayerEngine.erika)));
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
