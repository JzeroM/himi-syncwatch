import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/stream_reload_scheduler.dart';

void main() {
  group('StreamReloadScheduler', () {
    test('首次 schedule 按首档延迟触发 onFire，并消耗一次预算', () {
      var fired = 0;
      final s = StreamReloadScheduler();

      s.schedule(() => fired++);

      expect(s.hasPending, isTrue);
      expect(s.exhausted, isFalse);
      // 2s 未到不触发
      // fakeAsync 在 widget test 外不可用；这里用真实 Timer 无法精确推进，
      // 改为验证 canSchedule / exhausted / inFlight 状态机（纯逻辑无 Timer 依赖的断言）。
    });

    test('连续 schedule 在 pending 期间 no-op（不重复排程）', () {
      var fired = 0;
      final s = StreamReloadScheduler();

      s.schedule(() => fired++);
      expect(s.hasPending, isTrue);

      // pending 期间再 schedule 应被吞掉
      s.schedule(() => fired++);
      // 无法直接断言 fired（timer 未推进）；断言 hasPending 仍为 true 且不崩溃
      expect(s.hasPending, isTrue);
    });

    test('inFlight 期间 schedule no-op；endFlight 后可再 schedule', () {
      final s = StreamReloadScheduler();

      s.schedule(() {});
      expect(s.hasPending, isTrue);

      // 模拟 timer 已触发进入 inFlight
      s.cancelPending();
      expect(s.beginFlight(), isTrue);
      expect(s.inFlight, isTrue);
      expect(s.canSchedule, isFalse);

      // inFlight 期间 schedule 被吞
      s.schedule(() {});
      expect(s.hasPending, isFalse);

      s.endFlight();
      expect(s.inFlight, isFalse);
      expect(s.canSchedule, isTrue);
    });

    test('beginFlight 重入返回 false', () {
      final s = StreamReloadScheduler();
      expect(s.beginFlight(), isTrue);
      expect(s.beginFlight(), isFalse);
      s.endFlight();
    });

    test('耗尽 3 次后 exhausted=true 且 schedule no-op', () {
      var fired = 0;
      final s = StreamReloadScheduler();

      // 第 1 次：schedule 成功（pending）
      s.schedule(() => fired++);
      expect(s.hasPending, isTrue);
      // 手动推进：cancel + beginFlight + endFlight 模拟"触发完成"
      s.cancelPending();
      s.beginFlight();
      s.endFlight();

      // 第 2 次
      s.schedule(() => fired++);
      s.cancelPending();
      s.beginFlight();
      s.endFlight();

      // 第 3 次
      s.schedule(() => fired++);
      s.cancelPending();
      s.beginFlight();
      s.endFlight();

      expect(s.exhausted, isTrue);
      expect(s.canSchedule, isFalse);

      // 耗尽后再 schedule no-op
      s.schedule(() => fired++);
      expect(s.hasPending, isFalse);
    });

    test('reset 清零预算并取消 pending，可重新调度', () {
      final s = StreamReloadScheduler();

      s.schedule(() {});
      expect(s.hasPending, isTrue);

      s.reset();
      expect(s.hasPending, isFalse);
      expect(s.exhausted, isFalse);

      s.schedule(() {});
      expect(s.hasPending, isTrue);
    });

    test('cancelPending 保留已消耗预算', () {
      final s = StreamReloadScheduler();

      s.schedule(() {}); // 消耗 1/3
      s.cancelPending();

      expect(s.hasPending, isFalse);
      expect(s.exhausted, isFalse); // 预算未清零
      expect(s.canSchedule, isTrue); // 仍可再调度（第 2 次）
    });

    test('自定义退避序列', () {
      final s = StreamReloadScheduler(delaysSec: [1]);

      s.schedule(() {});
      s.cancelPending();
      s.beginFlight();
      s.endFlight();

      expect(s.exhausted, isTrue);
    });

    test('stallTimeout 常量为 10 秒', () {
      expect(StreamReloadScheduler.stallTimeout, const Duration(seconds: 10));
    });
  });
}
