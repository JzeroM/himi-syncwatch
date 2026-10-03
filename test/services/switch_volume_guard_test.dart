import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/switch_volume_guard.dart';

void main() {
  group('SwitchVolumeGuard.canWriteBack（换源窗口拒绝回写）', () {
    test('空闲态允许回写', () {
      final g = SwitchVolumeGuard();
      expect(g.canWriteBack(fading: false, switching: false), isTrue);
    });

    test('渐变进行中拒绝回写（渐出把 volume 压 0，回写会归零音量条）', () {
      final g = SwitchVolumeGuard();
      expect(g.canWriteBack(fading: true, switching: false), isFalse);
    });

    test('换源窗口内拒绝回写（渐出完成→渐入开始的污染窗口，静音根因）', () {
      final g = SwitchVolumeGuard();
      expect(g.canWriteBack(fading: false, switching: true), isFalse);
      // 回归场景：渐出完成（fading=false）但 switching 仍 true 时，
      // onStateChanged 读到 player.volume=0，必须被拦下
      expect(g.canWriteBack(fading: false, switching: true), isFalse);
    });

    test('渐变与换源同时进行拒绝回写', () {
      final g = SwitchVolumeGuard();
      expect(g.canWriteBack(fading: true, switching: true), isFalse);
    });

    test('endSwitch 后换源窗口关闭、允许回写', () {
      final g = SwitchVolumeGuard();
      expect(g.canWriteBack(fading: false, switching: true), isFalse);
      g.endSwitch();
      expect(g.canWriteBack(fading: false, switching: false), isTrue);
    });
  });

  group('SwitchVolumeGuard 目标音量记录（污染收敛）', () {
    test('无记录时渐入目标回退 UI 音量', () {
      final g = SwitchVolumeGuard();
      expect(g.hasPendingTarget, isFalse);
      expect(g.fadeInTarget(0.8), closeTo(0.8, 1e-9));
    });

    test('渐出前记录目标，污染的 UI 音量 0 不影响渐入目标', () {
      final g = SwitchVolumeGuard();
      g.markFadeOutStart(0.8);
      expect(g.hasPendingTarget, isTrue);
      // _volume 被污染为 0（player.volume 回写），渐入仍收敛到 0.8
      expect(g.fadeInTarget(0.0), closeTo(0.8, 1e-9));
    });

    test('记录值按 0-1 截断', () {
      final g = SwitchVolumeGuard();
      g.markFadeOutStart(1.5);
      expect(g.fadeInTarget(0), closeTo(1.0, 1e-9));
      g.markFadeOutStart(-0.2);
      expect(g.fadeInTarget(0), closeTo(0.0, 1e-9));
    });

    test('endSwitch 清除记录，后续渐入回退 UI 音量', () {
      final g = SwitchVolumeGuard();
      g.markFadeOutStart(0.6);
      g.endSwitch();
      expect(g.hasPendingTarget, isFalse);
      expect(g.fadeInTarget(0.3), closeTo(0.3, 1e-9));
    });

    test('连续换源：下一次渐出覆盖上一次残留记录', () {
      final g = SwitchVolumeGuard();
      g.markFadeOutStart(0.9);
      g.endSwitch();
      g.markFadeOutStart(0.5);
      expect(g.fadeInTarget(0.0), closeTo(0.5, 1e-9));
    });
  });
}
