import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/erika_player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

/// Erika 播完（EOS）分类（v1.2.7 修「播完弹播放出错」）。
///
/// Erika 在 EOF 以 error 或 stateChanged→stopped 收尾，从不产生 end 位。
/// 位置≈时长时判为播完 → 状态位上报 end（上层自动下一集），而非 invalid
/// （弹「播放出错，正在重试」）。
void main() {
  group('ErikaPlayerAdapter.classifyEndOfMedia', () {
    test('位置进入结尾窗口（时长 47:05，位置 47:04）→ 播完', () {
      expect(
        ErikaPlayerAdapter.classifyEndOfMedia(
          positionMs: 2824000,
          durationMs: 2825000,
          seekFenceActive: false,
        ),
        isTrue,
      );
    });

    test('位置精确等于时长 → 播完', () {
      expect(
        ErikaPlayerAdapter.classifyEndOfMedia(
          positionMs: 2825000,
          durationMs: 2825000,
          seekFenceActive: false,
        ),
        isTrue,
      );
    });

    test('中段位置（远离子结尾）→ 非播完', () {
      expect(
        ErikaPlayerAdapter.classifyEndOfMedia(
          positionMs: 600000,
          durationMs: 2825000,
          seekFenceActive: false,
        ),
        isFalse,
      );
    });

    test('时长未就绪（0）→ 非播完', () {
      expect(
        ErikaPlayerAdapter.classifyEndOfMedia(
          positionMs: 1000,
          durationMs: 0,
          seekFenceActive: false,
        ),
        isFalse,
      );
    });

    test('seek 栅栏期内 → 非播完（避免 seek 到结尾误判）', () {
      expect(
        ErikaPlayerAdapter.classifyEndOfMedia(
          positionMs: 2825000,
          durationMs: 2825000,
          seekFenceActive: true,
        ),
        isFalse,
      );
    });
  });

  group('ErikaPlayerAdapter.resolveStatus', () {
    test('EOF error 判为播完 → end（不是 invalid）', () {
      final st = ErikaPlayerAdapter.resolveStatus(
        errored: false,
        ended: true,
        state: AdapterPlaybackState.stopped,
        buffering: false,
        durationMs: 2825000,
      );
      expect(st.test(AdapterMediaStatus.end), isTrue);
      expect(st.test(AdapterMediaStatus.invalid), isFalse);
    });

    test('真实中段错误 → invalid', () {
      final st = ErikaPlayerAdapter.resolveStatus(
        errored: true,
        ended: false,
        state: AdapterPlaybackState.playing,
        buffering: false,
        durationMs: 2825000,
      );
      expect(st.test(AdapterMediaStatus.invalid), isTrue);
      expect(st.test(AdapterMediaStatus.end), isFalse);
    });

    test('errored 优先于 ended', () {
      final st = ErikaPlayerAdapter.resolveStatus(
        errored: true,
        ended: true,
        state: AdapterPlaybackState.stopped,
        buffering: false,
        durationMs: 2825000,
      );
      expect(st.test(AdapterMediaStatus.invalid), isTrue);
      expect(st.test(AdapterMediaStatus.end), isFalse);
    });

    test('ended 优先于 stopped（否则回退 unloaded 不切集）', () {
      final st = ErikaPlayerAdapter.resolveStatus(
        errored: false,
        ended: true,
        state: AdapterPlaybackState.stopped,
        buffering: false,
        durationMs: 2825000,
      );
      expect(st.test(AdapterMediaStatus.unloaded), isFalse);
      expect(st.test(AdapterMediaStatus.end), isTrue);
    });

    test('正常播放中 → loaded', () {
      final st = ErikaPlayerAdapter.resolveStatus(
        errored: false,
        ended: false,
        state: AdapterPlaybackState.playing,
        buffering: false,
        durationMs: 2825000,
      );
      expect(st.test(AdapterMediaStatus.loaded), isTrue);
    });
  });
}
