import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/count_retry.dart';

void main() {
  test('按 1s/2s/3s/5s 序列依次触发，共 4 次后停止', () {
    fakeAsync((async) {
      var ticks = 0;
      final scheduler =
          CountRetryScheduler(delaysSec: const [1, 2, 3, 5], onTick: () => ticks++);

      scheduler.restart();
      expect(scheduler.isActive, isTrue);

      async.elapse(const Duration(seconds: 1));
      expect(ticks, 1);
      async.elapse(const Duration(seconds: 2));
      expect(ticks, 2);
      async.elapse(const Duration(seconds: 3));
      expect(ticks, 3);
      async.elapse(const Duration(seconds: 5));
      expect(ticks, 4);

      // 序列走完后不再触发
      async.elapse(const Duration(seconds: 30));
      expect(ticks, 4);
      expect(scheduler.isActive, isFalse);
    });
  });

  test('restart 重排：序列中途新事件重新开始一轮', () {
    fakeAsync((async) {
      var ticks = 0;
      final scheduler =
          CountRetryScheduler(delaysSec: const [1, 2, 3, 5], onTick: () => ticks++);

      scheduler.restart();
      async.elapse(const Duration(seconds: 1));
      expect(ticks, 1);

      // 新成员变化事件 → 重排
      scheduler.restart();
      async.elapse(const Duration(seconds: 1));
      expect(ticks, 2);
      async.elapse(const Duration(seconds: 2));
      expect(ticks, 3);
      async.elapse(const Duration(seconds: 3));
      expect(ticks, 4);
      async.elapse(const Duration(seconds: 5));
      expect(ticks, 5);
    });
  });

  test('cancel 取消待触发的重查', () {
    fakeAsync((async) {
      var ticks = 0;
      final scheduler =
          CountRetryScheduler(delaysSec: const [1, 2, 3, 5], onTick: () => ticks++);

      scheduler.restart();
      scheduler.cancel();
      expect(scheduler.isActive, isFalse);

      async.elapse(const Duration(seconds: 60));
      expect(ticks, 0);
    });
  });
}
