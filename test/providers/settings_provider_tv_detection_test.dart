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

  group('TV 默认 SurfaceView + AudioTrack（tvMode 键控，v1.1.75 起 videoOutput、'
      'v1.1.176 增 audioRenderer）', () {
    test('TV 设备自动开 tvMode → 同时默认 surfaceView+AudioTrack 并落盘', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.videoOutput, 'surfaceView');
      expect(notifier.state.videoOutputUserSet, isFalse, reason: '自动默认不标记手动');
      expect(notifier.state.audioRenderer, 'AudioTrack');
      expect(notifier.state.audioRendererUserSet, isFalse);
      expect(notifier.persistCount, 1);
    });

    test('手动关过 tvMode → tvMode 与输出/后端皆保持不动', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(tvMode: false, tvModeUserSet: true),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isFalse);
      expect(notifier.state.videoOutput, 'texture');
      expect(notifier.state.audioRenderer, 'auto');
    });

    test('手动选过输出（userSet=true, texture）→ 输出尊重不动，tvMode 照翻', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(videoOutput: 'texture', videoOutputUserSet: true),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.videoOutput, 'texture', reason: 'E4 逃生口：手动档位一律优先');
    });

    test('手动选过后端（userSet=true, auto）→ 后端尊重不动', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(audioRenderer: 'auto', audioRendererUserSet: true),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.audioRenderer, 'auto', reason: '手动档位一律优先');
      expect(notifier.state.videoOutput, 'surfaceView');
    });

    test('非 TV 设备但 tvMode 已开启 → 输出/后端翻 TV 默认（mode 键控语义）', () async {
      final notifier = FakeSettingsNotifier(const AppSettings(tvMode: true));
      await notifier.applyTvAutoDetection(isTelevision: false);

      expect(notifier.state.videoOutput, 'surfaceView');
      expect(notifier.state.audioRenderer, 'AudioTrack');
      expect(notifier.state.tvMode, isTrue);
    });

    test('非 TV 且 tvMode 关闭 → 全部不动（手机端默认 auto/texture）', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.applyTvAutoDetection(isTelevision: false);

      expect(notifier.state.tvMode, isFalse);
      expect(notifier.state.videoOutput, 'texture');
      expect(notifier.state.audioRenderer, 'auto');
      expect(notifier.persistCount, 0, reason: '无变更不落盘');
    });

    test('幂等：已是 tvMode+TV 默认组合 → 无变更不落盘', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          tvMode: true,
          videoOutput: 'surfaceView',
          audioRenderer: 'AudioTrack',
        ),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.videoOutput, 'surfaceView');
      expect(notifier.state.audioRenderer, 'AudioTrack');
      expect(notifier.persistCount, 0);
    });

    test('老装机迁移：tvMode 已 true + texture/auto → 下次引导翻 TV 默认', () async {
      final notifier = FakeSettingsNotifier(const AppSettings(tvMode: true));
      expect(notifier.state.videoOutput, 'texture');

      await notifier.applyTvAutoDetection(isTelevision: true);
      expect(notifier.state.videoOutput, 'surfaceView');
      expect(notifier.state.audioRenderer, 'AudioTrack');
    });

    test('关闭 TV 模式不回写输出/后端（单向默认）', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          tvMode: true,
          videoOutput: 'surfaceView',
          audioRenderer: 'AudioTrack',
        ),
      );
      await notifier.update(tvMode: false);

      expect(notifier.state.tvMode, isFalse);
      expect(notifier.state.videoOutput, 'surfaceView',
          reason: '关 tvMode 不自动回写 texture');
      expect(notifier.state.audioRenderer, 'AudioTrack',
          reason: '关 tvMode 不自动回写 auto');
    });
  });

  group('手动开启 TV 模式立即应用 TV 默认（update 路径，v1.1.176）', () {
    test('update(tvMode:true) → 同帧落盘 surfaceView+AudioTrack', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(tvMode: true);

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.videoOutput, 'surfaceView');
      expect(notifier.state.audioRenderer, 'AudioTrack');
      expect(notifier.state.videoOutputUserSet, isFalse);
      expect(notifier.state.audioRendererUserSet, isFalse);
    });

    test('同一次 update 手动指定后端 → 手动值优先且标记 userSet', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(tvMode: true, audioRenderer: 'AAudio');

      expect(notifier.state.tvMode, isTrue);
      expect(notifier.state.audioRenderer, 'AAudio');
      expect(notifier.state.audioRendererUserSet, isTrue);
      expect(notifier.state.videoOutput, 'surfaceView',
          reason: '视频输出仍走 TV 默认');
    });

    test('再次 update(tvMode:true)（已开启）→ 不重复应用', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(tvMode: true, audioRenderer: 'OpenSL',
            audioRendererUserSet: true),
      );
      final before = notifier.persistCount;
      await notifier.update(tvMode: true);

      expect(notifier.state.audioRenderer, 'OpenSL');
      expect(notifier.persistCount, before + 1, reason: '仅常规落盘一次');
    });

    test('非 TV 平台 update(tvMode:true) 同样应用（effective 层另有平台钳制）',
        () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(tvMode: true);

      expect(notifier.state.audioRenderer, 'AudioTrack',
          reason: '落盘 TV 默认；非 Android 生效层固定 auto，互不影响');
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
