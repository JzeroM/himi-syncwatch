import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() {
    PlayerEngineFactory.debugIsOhosOverride = null;
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

  test('非 HarmonyOS 不注册 MPV', () {
    PlayerEngineFactory.debugIsOhosOverride = false;

    expect(
      PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
      isFalse,
    );
    expect(PlayerEngineFactory.defaultEngine(), isNot(PlayerEngine.mpv));
  });

  test('MPV 引擎 id 与短名', () {
    expect(PlayerEngine.fromId('mpv'), PlayerEngine.mpv);
    expect(PlayerEngine.mpv.shortLabel, 'MPV');
  });
}
