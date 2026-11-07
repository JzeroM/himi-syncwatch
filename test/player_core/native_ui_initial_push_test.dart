import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 612：原生 UI 打开时补推快照（初始房间头部三控件）+ 标题 flexGrow + 类型修复。
void main() {
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();

  group('① 原生 UI 打开时补推快照（初始房间头部三控件）', () {
    test('_onNativeUiActiveChanged 在激活时调 _syncNativePanelData', () {
      final idx = screen.indexOf('void _onNativeUiActiveChanged() {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 2200);
      expect(body, contains('if (_nativeUiActive) _syncNativePanelData();'));
    });

    test('注释记录「_player 还不是 MpvPlayerAdapter → 守卫拦截」根因', () {
      expect(screen, contains('还不是 MpvPlayerAdapter'));
    });

    test('_syncNativePanelData 的守卫仍在（不是删守卫，是补推送时机）', () {
      final idx = screen.indexOf('void _syncNativePanelData() {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 200);
      expect(body, contains('if (mpv is! MpvPlayerAdapter || _disposed) return;'));
    });

    test('不造成递归：applyNativePanelData 不改 nativeUiActive', () {
      final adapter = File('lib/services/player/mpv_player_adapter.dart')
          .readAsStringSync();
      final idx = adapter.indexOf('void applyNativePanelData({');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 900);
      expect(body, isNot(contains('nativeUiActive.value =')));
    });
  });

  group('② 头部标题 flexGrow(1)（对齐安卓权重 1，把三控件推到右边）', () {
    test('标题同时有 flexGrow(1) 与 flexShrink(1)', () {
      final idx = view.indexOf("Text('资源')");
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 800);
      expect(body, contains('.flexGrow(1)'));
      expect(body, contains('.flexShrink(1)'));
    });

    test('注释记录「flexShrink 不会撑开」根因', () {
      expect(view, contains('不会撑开'));
    });

    test('安卓参考：LayoutParams(0, WRAP_CONTENT, 1f)', () {
      expect(
        kotlinScreen,
        contains('LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)'),
      );
    });
  });

  group('③ Kotlin 类型修复（positionMs Int → Long）', () {
    test('616 起 setClock 传 positionMs + paused（帧驱动）', () {
      expect(
        kotlinScreen,
        contains('state.positionMs.toLong(),'),
      );
    });

    test('618 起 setClock 收四参（位置/冻结三态/倍速/时长）', () {
      final danmaku = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/DanmakuLayerView.kt',
      ).readAsStringSync();
      expect(danmaku, contains('durationMs: Long,'));
      expect(danmaku, contains('snapDurationMs = durationMs'));
    });
  });
}
