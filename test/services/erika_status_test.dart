import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/player_core/adapters/nipa_erika_adapter.dart';
import 'package:himi_syncwatch/player_core/player_data_models.dart';
import 'package:himi_syncwatch/player_core/player_enums.dart';

void main() {
  test('Erika duration 就绪后即使暂停也是 loaded', () {
    final status = NipaErikaAdapter.resolveMediaStatus(
      errored: false,
      ended: false,
      ready: true,
      buffering: false,
      state: PlayerPlaybackState.paused,
    );
    expect(status.test(PlayerMediaStatus.loaded), isTrue);
  });

  test('Erika 播放中但 duration 未就绪返回 loading', () {
    final status = NipaErikaAdapter.resolveMediaStatus(
      errored: false,
      ended: false,
      ready: false,
      buffering: false,
      state: PlayerPlaybackState.playing,
    );
    expect(status.test(PlayerMediaStatus.loading), isTrue);
  });

  test('Erika EOS 同时带 loaded + end', () {
    final status = NipaErikaAdapter.resolveMediaStatus(
      errored: false,
      ended: true,
      ready: true,
      buffering: false,
      state: PlayerPlaybackState.stopped,
    );
    expect(status.test(PlayerMediaStatus.loaded), isTrue);
    expect(status.test(PlayerMediaStatus.end), isTrue);
  });

  test('Erika 非 EOS 错误为 invalid', () {
    final status = NipaErikaAdapter.resolveMediaStatus(
      errored: true,
      ended: false,
      ready: true,
      buffering: false,
      state: PlayerPlaybackState.stopped,
    );
    expect(status.test(PlayerMediaStatus.invalid), isTrue);
  });

  test('Erika EOS 判定阈值 1 秒，seek 栅栏内不判 EOS', () {
    expect(
      NipaErikaAdapter.classifyEndOfMedia(
        positionMs: 299000,
        durationMs: 300000,
        seekFenceActive: false,
      ),
      isTrue,
    );
    expect(
      NipaErikaAdapter.classifyEndOfMedia(
        positionMs: 299000,
        durationMs: 300000,
        seekFenceActive: true,
      ),
      isFalse,
    );
  });
}
