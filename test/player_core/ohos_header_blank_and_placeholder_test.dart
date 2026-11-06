import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 607：鸿蒙头部 Blank 占位 + 播放图标点击 + 面板开关间距 + 空态占位。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final host = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiMpvNativeHost.ets',
  ).readAsStringSync();
  final state = File(
    'lib/services/player/native/native_player_state.dart',
  ).readAsStringSync();
  final adapter = File('lib/services/player/mpv_player_adapter.dart')
      .readAsStringSync();

  group('① 头部用 Blank 弹性占位（layoutWeight 无效）', () {
    test('Text(\'资源\') 不再用 layoutWeight', () {
      final idx = view.indexOf("Text('资源')");
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 300);
      expect(body, isNot(contains('layoutWeight')));
    });

    test('头部 Row 内有 Blank()', () {
      final idx = view.indexOf("Text('资源')");
      final body = view.substring(idx, idx + 700);
      expect(body, contains('Blank();'));
    });

    test('注释记录 layoutWeight 优先级高于 constraintSize', () {
      expect(view, contains('优先级**高于**'));
    });

    test('人数胶囊/角色徽章仍保留 constraintSize 保底', () {
      expect(view, contains('.constraintSize({ minWidth: 40, minHeight: 20 })'));
      expect(view, contains('.constraintSize({ minWidth: 32, minHeight: 20 })'));
    });
  });

  group('② 面板开关按钮留出边界间距', () {
    test('panelToggle 的 margin 含 right', () {
      final idx = view.indexOf("'panelToggle'");
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 700);
      expect(body, contains('right: 8'));
    });
  });

  group('③ 播放/暂停图标有独立 onClick（不再是无响应死区）', () {
    test('图标 onClick 含暂停/切集两种语义', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      expect(body, contains('this.host().optimisticTogglePaused()'));
      expect(body, contains('this.host().optimisticSelectEpisode(ep.index)'));
    });

    test('图标有 hitTestBehavior(Block) 防穿透', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      expect(body, contains('.hitTestBehavior(HitTestMode.Block)'));
    });

    test('行内三个可点击元素都有 onClick（防同类遗漏）', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      // 播放图标 / 内容区 / 删除按钮 —— 三处都应有 onClick。
      expect(
        RegExp(r'\.onClick\(').allMatches(body).length,
        greaterThanOrEqualTo(3),
        reason: '播放图标 + 内容区 + 删除按钮都必须各自有 onClick',
      );
    });
  });

  group('④ 无播放内容时渲染占位提示', () {
    test('NativePlayerState 有 playerReady（8 层补全）', () {
      expect(state, contains('this.playerReady = true,'));
      expect(state, contains('final bool playerReady;'));
      expect(state, contains("playerReady: json['playerReady'] != false,"));
      expect(state, contains("'playerReady': playerReady,"));
      expect(state, contains('bool? playerReady,'));
      expect(state, contains('playerReady: playerReady ?? this.playerReady,'));
      expect(state, contains('other.playerReady == playerReady &&'));
      expect(state, contains('        playerReady,'));
    });

    test('_buildNativePlayerState 传 playerReady（与 _prepared 绑定）', () {
      expect(adapter, contains('playerReady: _prepared && !_disposed,'));
    });

    test('unloadMedia 重置 _prepared（删当前集后自动变 false）', () {
      final idx = adapter.indexOf('Future<void> unloadMedia() async {');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 300);
      expect(body, contains('_prepared = false;'));
    });

    test('宿主解析 playerReady', () {
      expect(host, contains('playerReady: boolean = true;'));
      expect(host, contains('this.playerReady = jsonBool(obj.playerReady, this.playerReady);'));
    });

    test('视图 @State 镜像 + syncFromHost 同步', () {
      expect(view, contains('@State playerReady: boolean = true;'));
      expect(view, contains('this.playerReady = s.playerReady;'));
    });

    test('占位层有图标 + 文案 + 不抢手势', () {
      expect(view, contains('if (!this.playerReady) {'));
      expect(view, contains('请从资源面板选择要播放的内容'));
      expect(view, contains('NativePlayerIcons.ICON_PLAY_CIRCLE'));
      final idx = view.indexOf('if (!this.playerReady) {');
      final body = view.substring(idx, idx + 900);
      expect(body, contains('.hitTestBehavior(HitTestMode.None)'));
    });

    test('文案与 Flutter 一致', () {
      final flutter = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(flutter, contains('请从资源面板选择要播放的内容'));
    });
  });
}
