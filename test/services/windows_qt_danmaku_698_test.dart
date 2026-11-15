import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698：Windows（Qt 模式）弹幕一直 0 个 / 一条都不显示。
///
/// ## 根因
///
/// Qt 模式下 mpv 跑在 **Qt 进程**里，Dart 的 `mpv` 适配器是**空闲引擎**：
///
/// | 字段 | 空闲引擎的值 | 后果 |
/// |---|---|---|
/// | `positionMs` | 恒 0 | 弹幕切窗只覆盖前 30s → 之后没有数据 |
/// | `paused` | 旧值（可能 true） | QML 的帧定时器 `running: playing` 不成立 → 一条不画 |
/// | `durationMs` | 0 | 进度/统计异常 |
///
/// `playerReady` 在 681/682 已单独修过（改用 `qt.hasMedia`），但**播放字段
/// 没修**，于是面板显示「总 3563 · 在屏 0」而画面里一条弹幕都没有。
///
/// ## 修法
///
/// `_syncQtState` 用 Qt 的真实值覆盖，并把位置作为弹幕切窗基准传进去
/// （只改 stateJson 不够——`_buildDanmakuWindow` 用的是适配器自己的位置）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String screen;
  late String adapter;
  late String qtAdapter;

  setUpAll(() {
    screen = read('lib/screens/player/player_screen.dart');
    adapter = read('lib/services/player/mpv_player_adapter.dart');
    qtAdapter = read('lib/services/player/qt_player_adapter.dart');
  });

  group('1. 快照构建支持位置覆盖', () {
    test('1.1 buildNativePlayerState 接受 positionMsOverride', () {
      expect(adapter,
          contains('buildNativePlayerState({int? positionMsOverride})'));
      expect(adapter, contains('_buildNativePlayerState(positionMsOverride:'));
    });

    test('1.2 覆盖值同时用于 state 与弹幕切窗', () {
      // state 字段
      expect(adapter, contains('positionMs: posMs,'));
      // 弹幕窗口基准（只改 state 不够：窗口按适配器位置切片）
      expect(adapter, contains('danmakuItems: _buildDanmakuWindow(posMs),'));
      expect(adapter, contains('List<NativeDanmakuItem> _buildDanmakuWindow([int? positionMs])'));
      expect(adapter, contains('(positionMs ?? _positionMs) / 1000.0'));
    });
  });

  group('2. Qt 分支用真实播放态覆盖', () {
    test('2.1 位置/时长/暂停/倍速全部覆盖', () {
      expect(screen, contains('buildNativePlayerState(positionMsOverride: qt.position)'));
      expect(screen, contains("stateJson['durationMs'] = qt.duration;"));
      expect(screen, contains(
          "stateJson['paused'] = qt.state != AdapterPlaybackState.playing;"));
      expect(screen, contains("stateJson['speed'] = qt.playbackRate;"));
    });

    test('2.2 Qt 适配器确实暴露这些 getter', () {
      expect(qtAdapter, contains('int get position => _positionMs;'));
      expect(qtAdapter, contains('int get duration => _durationMs;'));
      expect(qtAdapter, contains('double get playbackRate => _playbackRate;'));
    });

    test('2.3 覆盖发生在 pushNativeState 之前', () {
      final idx = screen.indexOf('buildNativePlayerState(positionMsOverride: qt.position)');
      final push = screen.indexOf('qt.pushNativeState(', idx);
      expect(idx, greaterThan(0));
      expect(push, greaterThan(idx));
    });
  });

  group('3. 面板指标不再恒 0', () {
    test('3.1 在屏数用切窗位置统计', () {
      expect(adapter, contains('if (age >= 0 && age <= life) _dmOnscreen++;'));
      // 统计与切片用同一个 posSec
      expect(adapter, contains('final age = posSec - c.time;'));
    });

    test('3.2 采样字段保留但恒 0（面板兼容旧快照）', () {
      expect(adapter, contains('_dmSampled = 0;'));
      expect(adapter, isNot(contains('_dmSampled = comments.length - maxCount')));
    });
  });
}
