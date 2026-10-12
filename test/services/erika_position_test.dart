import 'package:erika_flutter/erika_flutter.dart' show ErikaEventKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/erika_player_adapter.dart';

void main() {
  group('ErikaPlayerAdapter.extrapolatePosition（位置外推）', () {
    test('按速率外推', () {
      expect(
        ErikaPlayerAdapter.extrapolatePosition(
            anchorMs: 1000, elapsedMs: 500, rate: 1.0, durationMs: 0),
        1500,
      );
      expect(
        ErikaPlayerAdapter.extrapolatePosition(
            anchorMs: 1000, elapsedMs: 500, rate: 2.0, durationMs: 0),
        2000,
      );
    });

    test('钳到 [0, duration]', () {
      expect(
        ErikaPlayerAdapter.extrapolatePosition(
            anchorMs: 0, elapsedMs: -9999, rate: 1.0, durationMs: 0),
        0,
      );
      expect(
        ErikaPlayerAdapter.extrapolatePosition(
            anchorMs: 9000, elapsedMs: 5000, rate: 1.0, durationMs: 10000),
        10000,
        reason: '不超过时长',
      );
    });
  });

  group('ErikaPlayerAdapter.appliesStateKind（状态事件过滤）', () {
    test('仅 stateChanged/error 更新状态；其余事件不更新（防抖动）', () {
      expect(
          ErikaPlayerAdapter.appliesStateKind(ErikaEventKind.stateChanged),
          isTrue);
      expect(ErikaPlayerAdapter.appliesStateKind(ErikaEventKind.error), isTrue);
      for (final k in const [
        ErikaEventKind.positionChanged,
        ErikaEventKind.durationChanged,
        ErikaEventKind.bufferingChanged,
        ErikaEventKind.tracksChanged,
        ErikaEventKind.trackSelectionChanged,
        ErikaEventKind.videoParamsChanged,
      ]) {
        expect(ErikaPlayerAdapter.appliesStateKind(k), isFalse, reason: '$k');
      }
    });
  });
}
