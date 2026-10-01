import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/tv_detection_service.dart';

import '../helpers/test_fakes.dart';

/// TV 自动识别（策略 A）：检测为 TV 且用户从未手动设置过才静默开启；
/// 手动设置优先，检测失败/非 TV 不动，旧数据 tvMode=true 视为已手动设置。
void main() {
  group('applyTvAutoDetection（自动识别决策）', () {
    test('检测为 TV 且未手动设置过 → 自动开启且不标记手动', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.tvModeUserSet, isFalse);
    });

    test('用户手动关过 → 检测为 TV 也不覆盖', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(tvMode: false, tvModeUserSet: true),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isFalse);
      expect(notifier.state.tvModeUserSet, isTrue);
    });

    test('检测失败（非 TV 设备）→ 设置保持不动', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.applyTvAutoDetection(isTelevision: false);

      expect(notifier.state.tvMode, isFalse);
      expect(notifier.state.tvModeUserSet, isFalse);
    });

    test('已开启（此前自动开过）→ 再次检测无变化', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(tvMode: true, tvModeUserSet: false),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.tvModeUserSet, isFalse);
    });
  });

  group('手动路径', () {
    test('update(tvMode) 标记用户已设置，之后自动识别不再覆盖', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(tvMode: false);

      expect(notifier.state.tvModeUserSet, isTrue);

      await notifier.applyTvAutoDetection(isTelevision: true);
      expect(notifier.state.tvMode, isFalse, reason: '手动设置优先');
    });

    test('update 其它字段不动 tvModeUserSet', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(decodeMode: 'sw');

      expect(notifier.state.tvModeUserSet, isFalse);
      expect(notifier.state.tvMode, isFalse);
    });
  });

  group('旧数据兼容（fromJson）', () {
    test('无 tvModeUserSet 且 tvMode=true → 视为已手动设置', () {
      final s = AppSettings.fromJson({'tvMode': true});

      expect(s.tvMode, isTrue);
      expect(s.tvModeUserSet, isTrue, reason: '旧版本只可能由用户手动打开');
    });

    test('无 tvModeUserSet 且 tvMode=false/缺失 → 可被自动识别', () async {
      final s = AppSettings.fromJson(const {});
      expect(s.tvModeUserSet, isFalse);

      final notifier = FakeSettingsNotifier(s);
      await notifier.applyTvAutoDetection(isTelevision: true);
      expect(notifier.state.tvMode, isTrue);
    });

    test('显式 tvModeUserSet=false 覆盖旧值推断', () {
      final s = AppSettings.fromJson({
        'tvMode': true,
        'tvModeUserSet': false,
      });
      expect(s.tvModeUserSet, isFalse);
    });
  });

  group('序列化 roundtrip', () {
    test('tvModeUserSet 随 toJson/fromJson 往返', () {
      const s = AppSettings(tvMode: true, tvModeUserSet: true);
      final back = AppSettings.fromJson(s.toJson());

      expect(back.tvMode, isTrue);
      expect(back.tvModeUserSet, isTrue);
    });
  });

  group('TvDetectionService', () {
    test('测试宿主非 Android → 直接返回 false 不抛异常', () async {
      expect(await const TvDetectionService().isTelevision(), isFalse);
    });
  });
}
