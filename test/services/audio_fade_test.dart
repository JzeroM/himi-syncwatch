import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/audio_fade.dart';

void main() {
  group('AudioFader.fadeTo', () {
    test('线性 N 步渐变且末值精确等于目标', () async {
      final delays = <Duration>[];
      final fader = AudioFader(steps: 5, delay: (d) async => delays.add(d));
      final values = <double>[];

      await fader.fadeTo(values.add, 1.0, 0.0);

      expect(values, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(values[i], closeTo(1.0 - (i + 1) / 5, 1e-9),
            reason: '第 ${i + 1} 步线性插值');
      }
      expect(values.last, 0.0, reason: '末值精确等于目标');
      // 最后一步直接落目标，不再等待
      expect(delays, hasLength(4));
      expect(delays.first, const Duration(milliseconds: 20));
      expect(fader.active, isFalse);
    });

    test('反向渐入收敛到目标值', () async {
      final fader = AudioFader(steps: 4, delay: (_) async {});
      final values = <double>[];

      await fader.fadeTo(values.add, 0.0, 1.0);

      expect(values, hasLength(4));
      expect(values.first, closeTo(0.25, 1e-9));
      expect(values.last, 1.0);
      expect(fader.active, isFalse);
    });

    test('from == to 仍施加一次目标值（幂等收敛）', () async {
      final fader = AudioFader(steps: 5, delay: (_) async {});
      final values = <double>[];

      await fader.fadeTo(values.add, 0.5, 0.5);

      expect(values, hasLength(5));
      expect(values.last, 0.5);
    });

    test('渐变进行中 active 为 true，完成后复位', () async {
      final gate = Completer<void>();
      final fader = AudioFader(steps: 5, delay: (_) => gate.future);
      var vol = 1.0;

      final done = fader.fadeTo((v) => vol = v, 1.0, 0.0);
      await Future<void>.delayed(Duration.zero);

      expect(fader.active, isTrue);
      expect(vol, closeTo(0.8, 1e-9));

      gate.complete();
      await done;

      expect(fader.active, isFalse);
      expect(vol, 0.0);
    });

    test('cancel 作废进行中的渐变并复位 active（不残留）', () async {
      final gate = Completer<void>();
      final fader = AudioFader(steps: 5, delay: (_) => gate.future);
      var vol = 1.0;

      final done = fader.fadeTo((v) => vol = v, 1.0, 0.0);
      await Future<void>.delayed(Duration.zero);
      expect(vol, closeTo(0.8, 1e-9));

      fader.cancel();
      expect(fader.active, isFalse,
          reason: 'cancel 后无新渐变接管时 active 必须复位，否则音量回写被永久阻断');

      gate.complete();
      await done;
      expect(vol, closeTo(0.8, 1e-9), reason: '作废后不再继续渐变');
    });

    test('新渐变作废旧渐变并收敛到新目标', () async {
      final gate = Completer<void>();
      final fader = AudioFader(steps: 5, delay: (_) => gate.future);
      var vol = 1.0;

      final first = fader.fadeTo((v) => vol = v, 1.0, 0.0);
      await Future<void>.delayed(Duration.zero);
      expect(vol, closeTo(0.8, 1e-9));

      // 旧渐变被抢占：从当前音量渐入回目标
      final second = fader.fadeTo((v) => vol = v, vol, 1.0);
      gate.complete();
      await Future.wait([first, second]);

      expect(vol, 1.0);
      expect(fader.active, isFalse);
    });

    test('cancel 后再发起新渐变，active 由新渐变接管', () async {
      final gate = Completer<void>();
      final fader = AudioFader(steps: 3, delay: (_) => gate.future);
      var vol = 1.0;

      final aborted = fader.fadeTo((v) => vol = v, 1.0, 0.0);
      await Future<void>.delayed(Duration.zero);
      fader.cancel();
      gate.complete();
      await aborted;

      final done = fader.fadeTo((v) => vol = v, vol, 1.0);
      await done;

      expect(vol, 1.0);
      expect(fader.active, isFalse);
    });
  });
}
