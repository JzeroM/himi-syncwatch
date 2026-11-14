import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_clock.dart';

/// 弹幕时钟（P1）：四端同构的锚点 + 单调投影 + 死区/收敛。
///
/// 这一层是「弹幕跳跃抖动」的根因修复点，必须锁死语义：
///
/// - 两次权威位置之间**严格线性外推**（乘播放速率）；
/// - 中等误差**只改速率、不改锚点**（不产生位移跳变）；
/// - 只有 seek/暂停恢复这类大误差才允许瞬移；
/// - 位移永远单调，不能出现回退（回退 = 肉眼看到的"弹一下"）。
void main() {
  const ms = 1000; // 1ms = 1000us
  int us(int milliseconds) => milliseconds * ms;

  group('1. 基础投影', () {
    test('1.1 1x 播放：位置随时间线性推进', () {
      final c = DanmakuClock(
        position: const Duration(milliseconds: 1000),
        monoUs: 0,
        paused: false,
      );
      expect(c.positionAt(us(0)), const Duration(milliseconds: 1000));
      expect(c.positionAt(us(500)), const Duration(milliseconds: 1500));
      expect(c.positionAt(us(2000)), const Duration(milliseconds: 3000));
    });

    test('1.2 1.25x 播放：投影乘速率', () {
      final c = DanmakuClock(
        position: Duration.zero,
        monoUs: 0,
        paused: false,
        baseRate: 1.25,
      );
      expect(c.positionAt(us(1000)), const Duration(milliseconds: 1250));
      expect(c.positionAt(us(2000)), const Duration(milliseconds: 2500));
    });

    test('1.3 暂停冻结：位置不推进', () {
      final c = DanmakuClock(
        position: const Duration(milliseconds: 5000),
        monoUs: 0,
        paused: true,
      );
      expect(c.positionAt(us(10000)), const Duration(milliseconds: 5000));
    });

    test('1.4 时长上限：投影不超过时长', () {
      final c = DanmakuClock(
        position: Duration.zero,
        monoUs: 0,
        paused: false,
      );
      c.onAuthoritative(
        position: Duration.zero,
        monoUs: 0,
        paused: false,
        duration: const Duration(seconds: 10),
      );
      expect(c.positionAt(us(60000)), const Duration(seconds: 10));
    });

    test('1.5 时间倒退不产生负位移', () {
      final c = DanmakuClock(
        position: const Duration(milliseconds: 100),
        monoUs: us(1000),
        paused: false,
      );
      expect(c.positionAt(us(500)), const Duration(milliseconds: 100));
    });
  });

  group('2. 抖动抑制（核心）', () {
    /// 模拟真机：每 500ms 来一次权威位置，带 ±jitterMs 的抖动。
    /// 返回逐帧采样的位置序列。
    List<Duration> simulate({
      required int jitterMs,
      int totalMs = 10000,
      int stepMs = 500,
      int frameMs = 16,
      double rate = 1.0,
      int seed = 12345,
    }) {
      var s = seed;
      int nextJitter() {
        // 简单 LCG，避免依赖 Random 的可重复性问题
        s = (s * 1103515245 + 12345) & 0x7fffffff;
        return (s % (jitterMs * 2 + 1)) - jitterMs;
      }

      final c = DanmakuClock(
        position: Duration.zero,
        monoUs: 0,
        paused: false,
        baseRate: rate,
      );
      final samples = <Duration>[];
      var nextAuthAt = stepMs;
      for (var t = 0; t <= totalMs; t += frameMs) {
        if (t >= nextAuthAt) {
          final truePos = (t * rate).round();
          c.onAuthoritative(
            position: Duration(milliseconds: truePos + nextJitter()),
            monoUs: us(t),
            paused: false,
            baseRate: rate,
          );
          nextAuthAt += stepMs;
        }
        samples.add(c.positionAt(us(t)));
      }
      return samples;
    }

    test('2.1 ±60ms 抖动下位移单调（不回退）', () {
      final samples = simulate(jitterMs: 60);
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i] >= samples[i - 1],
          isTrue,
          reason: '第 $i 帧位置回退：${samples[i - 1]} -> ${samples[i]}',
        );
      }
    });

    test('2.2 逐帧增量不超过「速率 + 收敛上限」', () {
      // 1x + 5% 修正 → 16ms 帧最多推进 ~16.8ms，留 2ms 余量
      final samples = simulate(jitterMs: 60);
      for (var i = 1; i < samples.length; i++) {
        final delta = (samples[i] - samples[i - 1]).inMicroseconds;
        expect(delta, lessThan(us(19)),
            reason: '第 $i 帧跳了 ${delta ~/ 1000}ms');
        expect(delta, greaterThan(0));
      }
    });

    test('2.3 1.25x + 抖动：位移仍单调', () {
      final samples = simulate(jitterMs: 60, rate: 1.25);
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i] >= samples[i - 1], isTrue,
            reason: '第 $i 帧位置回退');
      }
    });

    test('2.4 稳态误差收敛到死区内', () {
      final c = DanmakuClock(position: Duration.zero, monoUs: 0, paused: false);
      // 连续喂「真实位置 + 120ms」偏置，观察收敛
      for (var t = 500; t <= 6000; t += 500) {
        c.onAuthoritative(
          position: Duration(milliseconds: t + 120),
          monoUs: us(t),
          paused: false,
        );
      }
      final err =
          (const Duration(milliseconds: 6500 + 120) - c.positionAt(us(6500)))
              .inMilliseconds;
      expect(err.abs(), lessThanOrEqualTo(DanmakuClock.deadbandMs + 10));
      expect(c.hardResyncCount, 0, reason: '120ms 偏置应走速率收敛，不应硬重锚');
    });
  });

  group('3. 大误差 = seek/卡顿恢复', () {
    test('3.1 30s 跳变立即硬对齐', () {
      final c = DanmakuClock(
        position: const Duration(seconds: 10),
        monoUs: 0,
        paused: false,
      );
      final before = c.hardResyncCount;
      c.onAuthoritative(
        position: const Duration(seconds: 40),
        monoUs: us(1000),
        paused: false,
      );
      expect(c.positionAt(us(1000)), const Duration(seconds: 40));
      expect(c.hardResyncCount, before + 1);
    });

    test('3.2 暂停 -> 恢复：按新位置重锚', () {
      final c = DanmakuClock(
        position: const Duration(seconds: 5),
        monoUs: 0,
        paused: true,
      );
      c.onAuthoritative(
        position: const Duration(seconds: 5),
        monoUs: us(1000),
        paused: false,
      );
      expect(c.paused, isFalse);
      expect(c.positionAt(us(2000)), const Duration(milliseconds: 6000));
    });

    test('3.3 暂停期间重复上报不累加硬对齐次数', () {
      final c = DanmakuClock(
        position: const Duration(seconds: 5),
        monoUs: 0,
        paused: true,
      );
      final base = c.hardResyncCount;
      for (var i = 0; i < 10; i++) {
        c.onAuthoritative(
          position: const Duration(seconds: 5),
          monoUs: us(i * 500),
          paused: true,
        );
      }
      expect(c.hardResyncCount, base);
    });

    test('3.4 播放速率变化：重锚且位置连续', () {
      final c = DanmakuClock(
        position: Duration.zero,
        monoUs: 0,
        paused: false,
      );
      c.onAuthoritative(
        position: const Duration(milliseconds: 2000),
        monoUs: us(2000),
        paused: false,
        baseRate: 2.0,
      );
      expect(c.positionAt(us(3000)), const Duration(milliseconds: 4000));
    });
  });

  group('4. 统计字段', () {
    test('4.1 误差与硬对齐次数可读', () {
      final c = DanmakuClock(position: Duration.zero, monoUs: 0, paused: false);
      c.onAuthoritative(
        position: const Duration(milliseconds: 100),
        monoUs: 0,
        paused: false,
      );
      expect(c.lastErrorMs, 100);
      // 100ms 在死区与硬对齐阈值之间 → 走速率收敛，不算硬重锚
      expect(c.hardResyncCount, 0);
    });
  });
}
