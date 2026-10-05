import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_lock_controller.dart';

void main() {
  group('PlayerLockController（屏幕锁定状态机）', () {
    test('初始未锁', () {
      final c = PlayerLockController();
      expect(c.locked, isFalse);
      c.dispose();
    });

    test('lock：上锁，通知监听者，幂等不重复通知', () {
      final c = PlayerLockController();
      var notified = 0;
      c.addListener(() => notified++);
      c.lock();
      expect(c.locked, isTrue);
      expect(notified, 1);
      c.lock();
      expect(notified, 1);
      c.dispose();
    });

    test('unlock：解锁并通知；未锁定时幂等', () {
      final c = PlayerLockController();
      var notified = 0;
      c.addListener(() => notified++);
      c.lock();
      notified = 0;
      c.unlock();
      expect(c.locked, isFalse);
      expect(notified, 1);
      c.unlock();
      expect(notified, 1);
      c.dispose();
    });
  });
}
