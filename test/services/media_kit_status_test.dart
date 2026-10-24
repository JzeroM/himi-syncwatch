import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/player_core/adapters/nipa_media_kit_adapter.dart';
import 'package:himi_syncwatch/player_core/player_data_models.dart';
import 'package:himi_syncwatch/player_core/player_enums.dart';

void main() {
  test('MPV completed 同时带 loaded + end', () {
    final status = NipaMediaKitAdapter.resolveMediaKitStatus(
      completed: true,
      ready: true,
      buffering: false,
      state: PlayerPlaybackState.playing,
    );
    expect(status.test(PlayerMediaStatus.loaded), isTrue);
    expect(status.test(PlayerMediaStatus.end), isTrue);
  });

  test('MPV duration 就绪但暂停为 loaded', () {
    final status = NipaMediaKitAdapter.resolveMediaKitStatus(
      completed: false,
      ready: true,
      buffering: false,
      state: PlayerPlaybackState.paused,
    );
    expect(status.test(PlayerMediaStatus.loaded), isTrue);
    expect(status.test(PlayerMediaStatus.end), isFalse);
  });

  test('MPV buffering 优先于 loaded', () {
    final status = NipaMediaKitAdapter.resolveMediaKitStatus(
      completed: false,
      ready: true,
      buffering: true,
      state: PlayerPlaybackState.playing,
    );
    expect(status.test(PlayerMediaStatus.buffering), isTrue);
  });
}
