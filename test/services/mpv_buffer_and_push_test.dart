import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// 695 追补守卫：
/// - F：MPV 缓冲双滑杆（三端统一默认 256MB/60s）+ load 前统一下发；
/// - A：网速 1s tick 走轻量 statePatch（「跑一秒停顿一下」根因）；
/// - E：鸿蒙详情面板可滚动（真机回归）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  final screen = read('lib/screens/player/player_screen.dart');
  final adapter = read('lib/services/player/qt_player_adapter.dart');
  final mainCpp =
      read('native/windows_qt_player/src/main.cpp');
  final engineCfg = read('lib/screens/settings/engine_config_screen.dart');
  final ohosPlugin = read(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvOhosPlugin.ets');
  final ohosPanel = read(
      'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerPanel.ets');

  group('① F 缓冲双滑杆（默认 256MB/60s 三端统一）', () {
    test('AppSettings 默认值与钳位', () {
      const s = AppSettings();
      expect(s.mpvMaxBufferMb, 256);
      expect(s.mpvMaxBufferSecs, 60);
      final j = AppSettings.fromJson(
          const {'mpvMaxBufferMb': 99999, 'mpvMaxBufferSecs': 1});
      expect(j.mpvMaxBufferMb, 2048, reason: '上限钳位 2048');
      expect(j.mpvMaxBufferSecs, 5, reason: '下限钳位 5');
    });

    test('load 前统一写入 demuxer-max-bytes/半值 back/cache-secs', () {
      expect(screen, contains("'demuxer-max-bytes'"));
      expect(screen, contains("'demuxer-max-back-bytes'"));
      expect(screen, contains("'cache-secs'"));
      expect(screen, contains('settings.mpvMaxBufferMb'),
          reason: '写入值跟随滑杆设置');
    });

    test('设置页两个滑杆（TV 遥控：settingsTvSliderRow 既有范式）', () {
      expect(engineCfg, contains("sliderKey: 'mpvMaxBufferMb'"));
      expect(engineCfg, contains("sliderKey: 'mpvMaxBufferSecs'"));
      expect(engineCfg, contains('settingsTvSliderRow('),
          reason: 'TV 整行聚焦 + 左右键 ±step（settings_common 既有）');
    });

    test('鸿蒙 native 硬编码对齐 256/128MiB', () {
      expect(ohosPlugin, isNot(contains("'1024MiB'")));
      expect(ohosPlugin, contains("'256MiB'"));
      expect(ohosPlugin, contains("'128MiB'"));
    });
  });

  group('② A 网速 1s tick 走轻量 statePatch（跑一秒停顿一下 根因）', () {
    test('Qt 适配器 pushStatePatch + C++ statePatch 命令', () {
      expect(adapter, contains('void pushStatePatch('));
      expect(mainCpp, contains('QLatin1String("statePatch")'));
      expect(mainCpp, contains('state.applyJson('),
          reason: 'patch 并入 PlayerState（既有机制）');
    });

    test('player_screen 网速分支走 patch（Qt），不再全量推送', () {
      final i = screen.indexOf("'networkSpeedText': text");
      expect(i, greaterThan(0));
      final branch = screen.substring(i - 400, i + 50);
      expect(branch, contains('pushStatePatch'),
          reason: '1Hz 网速变化不得触发全量 _syncNativePanelData');
    });
  });

  group('③ E 鸿蒙详情面板可滚动（真机回归）', () {
    test('MediaInfoContent 包 Scroll 纵向滚动', () {
      final i = ohosPanel.indexOf('MediaInfoContent() {');
      expect(i, greaterThan(0));
      final body = ohosPanel.substring(i, i + 200);
      expect(body, contains('Scroll()'));
      expect(ohosPanel, contains('.scrollable(ScrollDirection.Vertical)'));
    });
  });
}
