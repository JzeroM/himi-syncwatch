import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/clock_offset_estimator.dart';

void main() {
  group('ClockOffsetEstimator', () {
    test('未校准：offsetMs/bestRttMs 为 null，toHostClockMs 恒等', () {
      final e = ClockOffsetEstimator();
      expect(e.isCalibrated, isFalse);
      expect(e.offsetMs, isNull);
      expect(e.bestRttMs, isNull);
      expect(e.toHostClockMs(12345), 12345);
    });

    test('对称网络：还原两机时钟差（host - viewer = 5000ms）', () {
      final e = ClockOffsetEstimator();
      const skew = 5000; // host clock = viewer clock + skew
      const oneWay = 50;
      const t1 = 1000;
      final t2 = t1 + oneWay + skew; // 房主收到并立即发送
      final t4 = t1 + oneWay * 2; // 回到观众

      final accepted = e.addSample(t1: t1, t2: t2, t4: t4);
      expect(accepted, isTrue);
      expect(e.offsetMs, closeTo(skew, 0.001));
      expect(e.bestRttMs, oneWay * 2);
      // 本机时刻 + offset = 房主时刻
      expect(e.toHostClockMs(t1), t1 + skew);
    });

    test('多样本抖动：EMA 收敛到真实偏移，bestRtt 取最小', () {
      final e = ClockOffsetEstimator(smoothing: 0.5);
      const skew = -3200; // 本机快于房主
      // 同一真实偏移下不同网络延迟（对称单程）
      for (final oneWay in [200, 120, 60, 80, 40]) {
        const t1 = 10_000;
        final t2 = t1 + oneWay + skew;
        final t4 = t1 + oneWay * 2;
        e.addSample(t1: t1, t2: t2, t4: t4);
      }
      expect(e.offsetMs, closeTo(skew, 1.0));
      expect(e.bestRttMs, 80); // 40*2
      expect(e.sampleCount, 5);
    });

    test('异常样本（t4 < t1）被丢弃', () {
      final e = ClockOffsetEstimator();
      expect(e.addSample(t1: 5000, t2: 6000, t4: 4000), isFalse);
      expect(e.isCalibrated, isFalse);
      expect(e.sampleCount, 0);
    });

    test('reset 清空校准状态', () {
      final e = ClockOffsetEstimator();
      e.addSample(t1: 0, t2: 1000, t4: 100);
      expect(e.isCalibrated, isTrue);
      e.reset();
      expect(e.isCalibrated, isFalse);
      expect(e.offsetMs, isNull);
      expect(e.bestRttMs, isNull);
      expect(e.sampleCount, 0);
    });
  });
}
