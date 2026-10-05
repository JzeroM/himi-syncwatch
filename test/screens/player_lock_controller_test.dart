import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_lock_controller.dart';

void main() {
  group('PlayerLockController（屏幕锁定状态机）', () {
    test('初始未锁、解锁钮不可见', () {
      final c = PlayerLockController();
      expect(c.locked, isFalse);
      expect(c.unlockButtonVisible, isFalse);
      c.dispose();
    });

    test('lock：上锁并收起解锁钮，通知监听者', () {
      final c = PlayerLockController();
      var notified = 0;
      c.addListener(() => notified++);
      c.lock();
      expect(c.locked, isTrue);
      expect(c.unlockButtonVisible, isFalse);
      expect(notified, 1);
      c.lock(); // 重复上锁不重复通知
      expect(notified, 1);
      c.dispose();
    });

    test('锁定中点屏：浮现解锁钮并返回 true', () {
      final c = PlayerLockController();
      c.lock();
      expect(c.onVideoTap(), isTrue, reason: '锁定中点击 → 解锁钮分支');
      expect(c.unlockButtonVisible, isTrue);
      expect(c.onVideoTap(), isTrue, reason: '重复点击保持可见');
      c.dispose();
    });

    test('未锁定点屏：返回 false（交由调用方切换控制栏）', () {
      final c = PlayerLockController();
      expect(c.onVideoTap(), isFalse);
      expect(c.unlockButtonVisible, isFalse);
      c.dispose();
    });

    test('hideUnlockButton：超时收起但保持锁定', () {
      final c = PlayerLockController();
      c.lock();
      c.onVideoTap();
      c.hideUnlockButton();
      expect(c.unlockButtonVisible, isFalse);
      expect(c.locked, isTrue, reason: '收起解锁钮不解锁');
      c.dispose();
    });

    test('unlock：解锁并复位解锁钮', () {
      final c = PlayerLockController();
      c.lock();
      c.onVideoTap();
      c.unlock();
      expect(c.locked, isFalse);
      expect(c.unlockButtonVisible, isFalse);
      c.unlock(); // 重复解锁不通知
      c.dispose();
    });
  });
}
