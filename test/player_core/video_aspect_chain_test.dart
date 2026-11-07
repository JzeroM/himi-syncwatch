import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 626：鸿蒙画布按视频比例的**数据链路**必须完整。
///
/// 625 实现了 `videoFitW/H()` 布局，但真机仍然拉伸——根因是
/// `_lastVideoW/H`（真正下发给鸿蒙的值）**恒为 0**：
///
/// `video-params` 在鸿蒙上是 NODE 属性，`getPropertyString` 返回空串
/// → `_parseVideoParams` 永不触发 → `_lastVideoW/H` 不赋值 →
/// `videoFitW()` 返回 -1 → XComponent 回落 `'100%'` 撑满。
///
/// 修法：用 `pollState` 的 `videoWidth`/`videoHeight`（走 `width`/`height`
/// 标量属性，鸿蒙可读）兜底赋值。
void main() {
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final plugin = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
    'HimiMpvOhosPlugin.ets',
  ).readAsStringSync();
  final state = File(
    'lib/services/player/native/native_player_state.dart',
  ).readAsStringSync();
  final ohos = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('① 鸿蒙侧确实提供 videoWidth/Height（标量属性）', () {
    test('pollState 用 width/height 而非 video-params', () {
      // video-params 是 NODE 类型，getPropertyString 返回空串。
      expect(plugin, contains("lib.getProperty('width')"));
      expect(plugin, contains("lib.getProperty('height')"));
      expect(plugin, contains('videoWidth: videoWidth,'));
      expect(plugin, contains('videoHeight: videoHeight,'));
    });
  });

  group('② Dart 侧把 pollState 的宽高同步给 _lastVideoW/H', () {
    test('_applyPolledState 有兜底赋值（626 修复点）', () {
      final idx = adapter.indexOf('_videoWidth = state.videoWidth;');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 1200);
      expect(body, contains('_lastVideoW = state.videoWidth!'));
      expect(body, contains('_lastVideoH = state.videoHeight!'));
      // 必须有守卫（宽高都 > 0 才写，避免 0 覆盖有效值）。
      expect(body, contains('(state.videoWidth ?? 0) > 0'));
      expect(body, contains('(state.videoHeight ?? 0) > 0'));
    });

    test('注释记录「video-params 在鸿蒙读不到」的根因', () {
      expect(adapter, contains('NODE 属性'));
      expect(adapter, contains('_lastVideoW/H'));
    });
  });

  group('③ 下发与接收链路完整', () {
    test('Dart 下发 videoWidth/videoHeight', () {
      expect(adapter, contains('videoWidth: _lastVideoW'));
      expect(adapter, contains('videoHeight: _lastVideoH'));
    });

    test('NativePlayerState 字段 + 序列化完整', () {
      expect(state, contains('final int videoWidth;'));
      expect(state, contains('final int videoHeight;'));
      expect(state, contains("'videoWidth': videoWidth"));
      expect(state, contains("json['videoWidth']"));
    });

    test('鸿蒙视图从 state 读（不是 host 顶层）', () {
      expect(ohos, contains('HimiMpvNativeHost.getInstance().state.videoWidth'));
      expect(ohos, contains('HimiMpvNativeHost.getInstance().state.videoHeight'));
    });
  });

  group('④ 比例计算与布局', () {
    test('videoFitW/H 在宽高缺失时返回 -1（回落撑满）', () {
      final wIdx = ohos.indexOf('private videoFitW(): number {');
      expect(wIdx, greaterThan(0));
      expect(ohos.substring(wIdx, wIdx + 700), contains('return -1;'));
      final hIdx = ohos.indexOf('private videoFitH(): number {');
      expect(hIdx, greaterThan(0));
      expect(ohos.substring(hIdx, hIdx + 700), contains('return -1;'));
    });

    test('XComponent 用 videoFitW/H 布局', () {
      expect(ohos, contains('this.fitVideoW > 0 ? this.fitVideoW'));
      expect(ohos, contains('this.fitVideoH > 0 ? this.fitVideoH'));
    });

    test('videoAreaW/H 由视频子节点实测', () {
      expect(ohos, contains('@State videoAreaW: number = 0;'));
      expect(ohos, contains('this.videoAreaW = w;'));
      expect(ohos, contains('this.videoAreaH = h;'));
    });
  });
}
