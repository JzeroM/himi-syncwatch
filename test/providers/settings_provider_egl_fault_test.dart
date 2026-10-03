import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

import '../helpers/test_fakes.dart';

/// EGL 故障跨重启持久化（H96_Max_RK3528 黑屏自愈）：
/// _onEglFault 检测到 3004 时 update(eglFaultSeen: true) 落盘，
/// _bootstrap 启动读取后置位检测器，故障设备后续启动直接直写。
void main() {
  group('update(eglFaultSeen)（故障标记落盘）', () {
    test('默认未标记', () {
      final notifier = FakeSettingsNotifier();
      expect(notifier.state.eglFaultSeen, isFalse);
    });

    test('update(eglFaultSeen: true) 置位并落盘', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(eglFaultSeen: true);

      expect(notifier.state.eglFaultSeen, isTrue);
      expect(notifier.persistCount, 1);
    });

    test('update 其他字段不误置位 eglFaultSeen', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(videoOutput: 'surfaceView');

      expect(notifier.state.videoOutput, 'surfaceView');
      expect(notifier.state.eglFaultSeen, isFalse);
    });

    test('状态链：标记后 copyWith 其他字段仍保留标记', () {
      final notifier = FakeSettingsNotifier(
        const AppSettings(eglFaultSeen: true),
      );
      notifier.state = notifier.state.copyWith(showSyncDebug: true);

      expect(notifier.state.eglFaultSeen, isTrue);
      expect(notifier.state.showSyncDebug, isTrue);
    });
  });

  group('update(videoOutput)（手动输出标记置位）', () {
    test('默认未标记', () {
      final notifier = FakeSettingsNotifier();
      expect(notifier.state.videoOutputUserSet, isFalse);
    });

    test('update(videoOutput:) 置位 videoOutputUserSet 并落盘', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(videoOutput: 'texture');

      expect(notifier.state.videoOutput, 'texture');
      expect(notifier.state.videoOutputUserSet, isTrue);
      expect(notifier.persistCount, 1);
    });

    test('update 其他字段不误置位 videoOutputUserSet', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(eglFaultSeen: true);

      expect(notifier.state.videoOutputUserSet, isFalse);
      expect(notifier.state.eglFaultSeen, isTrue);
    });
  });
}
