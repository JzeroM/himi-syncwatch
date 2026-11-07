import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 614：无媒体不转圈 + 安卓回退 613 的提前打开 + 弹幕单层插值对齐鸿蒙。
void main() {
  final adapter = File('lib/services/player/mpv_player_adapter.dart')
      .readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final danmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/DanmakuLayerView.kt',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerScreenView.kt',
  ).readAsStringSync();

  group('① 无媒体时不显示加载器', () {
    test('showLoading 有 hasMedia 守卫', () {
      final idx = adapter.indexOf('final hasMedia = _prepared || _uri != null;');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 400);
      expect(body, contains('final showLoading = hasMedia &&'));
    });

    test('注释记录「初始未播放永久转圈」根因', () {
      expect(adapter, contains('初始未播放时仍有加载器'));
    });
  });

  group('② 安卓回退 613 的提前打开（只在鸿蒙生效）', () {
    test('_openNativeUiIfNeeded 的补算有 isOhos 守卫', () {
      final idx = adapter.indexOf('Future<void> _openNativeUiIfNeeded({');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 1200);
      expect(body, contains('if (!MpvSessionPlatform.isOhos) return;'));
      // 不再写回 _nativeUiEnabled。
      expect(body, isNot(contains('_nativeUiEnabled = prefersNativeRoomUi;')));
    });

    test('_closeNativeUi 重置 _nativeUiEnabled', () {
      final idx = adapter.indexOf('Future<void> _closeNativeUi() async {');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 500);
      expect(body, contains('_nativeUiEnabled = false;'));
    });

    test('退场条件按平台分支', () {
      final idx = screen.indexOf('final nativeShortCircuit');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 400);
      expect(body, contains('MpvSessionPlatform.isOhos ? _roomUiShouldBeNative : _nativeUiActive'));
    });

    test('initState 的 reopen 有 isOhos 守卫', () {
      final idx = screen.indexOf('MpvSessionPlatform.isOhos &&');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 300);
      expect(body, contains('prefersNativeRoomUi'));
      expect(body, contains('reopenNativeUi()'));
    });

    test('_switchPlayerKernel 重新判定有 isOhos 守卫', () {
      expect(screen, contains('if (widget.roomCode != null && MpvSessionPlatform.isOhos) {'));
    });

    test('注释记录安卓拉伸根因', () {
      expect(screen, contains('安卓画面拉伸'));
    });
  });

  group('③ 安卓弹幕单层插值（对齐鸿蒙）', () {
    test('618 起改用无状态纯函数（Choreographer 帧驱动保留）', () {
      expect(danmaku, contains('Choreographer'));
      expect(danmaku, contains('elapsed * snapSpeed'));
      // 616 的锚点/收敛方案已移除（鸿蒙已验证会「忽快忽慢」）。
      expect(danmaku, isNot(contains('drift / 10')));
      // 614 的 positionProvider 方案已移除。
      expect(danmaku, isNot(contains('fun setPositionProvider')));
    });

    test('setClock 收四参（618：位置/冻结三态/倍速/时长）', () {
      expect(danmaku, contains('durationMs: Long,'));
    });

    test('宿主传原始快照位置（不叠加宿主插值）', () {
      expect(kotlinScreen, contains('state.positionMs.toLong(),'));
      expect(kotlinScreen, isNot(contains('danmakuLayer.setPositionProvider {')));
    });

    test('调用点传 positionMs + paused（616）', () {
      expect(kotlinScreen, contains('state.positionMs.toLong(),'));
    });

    test('鸿蒙参考：弹幕直接读宿主 positionNowMs（单层插值）', () {
      final ohosDanmaku = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/DanmakuLayer.ets',
      ).readAsStringSync();
      expect(ohosDanmaku, contains('positionNowMs()'));
    });
  });
}
