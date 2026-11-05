import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 604：鸿蒙房间面板头部/开关按钮/删除冒泡/列表刷新 + 分享面板遮挡。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();

  group('① 空房间/未播放时头部控件能出现（重建签名补全）', () {
    test('签名含 isHost / onlineUserCount / audienceName / resourcePanelOpen', () {
      final idx = view.indexOf('const playSig =');
      expect(idx, greaterThan(0));
      // 605 起改用 @State 镜像（宿主普通字段不在 ArkUI 观察链）。
      final body = view.substring(idx, idx + 900);
      expect(body, contains('this.roomIsHost'));
      expect(body, contains('this.roomOnlineCount'));
      expect(body, contains('this.roomAudienceName'));
      expect(body, contains('this.roomPanelShown'));
    });

    test('注释记录空房间根因', () {
      expect(view, contains('空房间/未播放时头部缺搜索、人数、角色徽章'));
    });
  });

  group('② 鸿蒙底栏有资源面板开关按钮（对齐安卓）', () {
    test('ControlRow 右侧簇有 panelToggle 按钮', () {
      final idx = view.indexOf('ControlRow() {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 7600);
      expect(body, contains("'panelToggle'"));
      expect(body, contains("sendCommand('toggleResourcePanel', null)"));
    });

    test('条件只看 isRoom（对齐安卓 panelToggleButton）', () {
      final idx = view.indexOf("'panelToggle'");
      final body = view.substring(idx - 400, idx + 100);
      expect(body, contains('if (this.state().isRoom) {'));
    });

    test('图标与安卓同源 ICON_OPEN_IN_FULL', () {
      expect(view, contains('NativePlayerIcons.ICON_OPEN_IN_FULL'));
      expect(kotlin, contains('NativePlayerIcons.ICON_OPEN_IN_FULL'));
    });

    test('安卓参考：panelToggleButton.visibility = if (state.isRoom)', () {
      expect(kotlin, contains('panelToggleButton.visibility = if (state.isRoom) VISIBLE else GONE'));
    });
  });

  group('③ 删除按钮不再冒泡到切集', () {
    test('行容器 Row 本身不再挂 onClick（改为内容区容器挂）', () {
      // 旧结构：删除按钮是行容器子节点 + 行容器有 onClick → 点击冒泡，
      // 删除后还会触发一次切集。ClickEvent 没有 stopPropagation，
      // 只能改结构：删除与内容区成为兄弟。
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      expect(idx, greaterThan(0));
      // 到「视频层 + 手势层」注释为止（本 @Builder 的结束边界）。
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      expect(end, greaterThan(idx));
      final body = view.substring(idx, end);
      // 内容区容器挂 onClick（切集/暂停）。
      expect(body, contains('this.host().optimisticSelectEpisode(ep.index)'));
      expect(body, contains('this.host().optimisticTogglePaused()'));
      // 行容器收尾不再有 onClick。
      final endIdx = body.indexOf('.border(ep.isPlaying');
      expect(endIdx, greaterThan(0));
      // `.border(...)` 之后到本 @Builder 结束（尾部可能不足 300 字符）。
      final tail = body.substring(endIdx);
      expect(tail, isNot(contains('.onClick(')));
    });

    test('删除按钮仍是兄弟节点（在内容区容器之外）', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      // 内容区容器在删除按钮之前闭合（`}` + layoutWeight 收尾）。
      final contentEnd = body.indexOf('// 删除（房主）');
      expect(contentEnd, greaterThan(0));
      final before = body.substring(0, contentEnd);
      expect(before, contains('.layoutWeight(1)'));
    });

    test('注释记录 ClickEvent 无 stopPropagation', () {
      expect(view, contains('stopPropagation'));
    });
  });

  group('④ 搜索添加的资源立即显示', () {
    test('_addResourceLocally 末尾调 _syncNativePanelData', () {
      final idx = screen.indexOf('void _addResourceLocally(Map<String, dynamic> data) {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 2000);
      expect(body, contains('_syncNativePanelData();'));
    });

    test('重建签名含资源分组内容', () {
      expect(view, contains('const groupsSig ='));
      expect(view, contains('resourceGroups'));
    });
  });

  group('⑤ 删除最后一个资源后真清空', () {
    test('_resourceGroupsCleared 标记存在', () {
      expect(screen, contains('bool _resourceGroupsCleared = false;'));
    });

    test('_nativeResourceGroups 据此放行空列表', () {
      final idx = screen.indexOf('List<NativeResourceGroup> _nativeResourceGroups() {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 1600);
      expect(body, contains('if (_resourceGroupsCleared) {'));
      expect(body, contains('return groups;'));
    });

    test('_removeEpisode 置标记并推原生', () {
      final idx = screen.indexOf('void _removeEpisode(int index, {bool sendRtm = true}) {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 1500);
      expect(body, contains('_resourceGroupsCleared = true;'));
      expect(body, contains('_syncNativePanelData();'));
    });
  });

  group('⑥ 分享面板/房间解散提示不被原生层遮挡', () {
    test('有公共 suspend/resume 辅助方法', () {
      expect(screen, contains('Future<bool> _suspendNativeUiForDialog() async {'));
      expect(screen, contains('Future<void> _resumeNativeUiAfterDialog(bool suspended) async {'));
    });

    test('分享面板：先 suspend 再 showDialog，关闭后 resume', () {
      final idx = screen.indexOf('Future<void> _showShareRoomDialog() async {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 1800);
      final suspendIdx = body.indexOf('await _suspendNativeUiForDialog();');
      final dialogIdx = body.indexOf('await showDialog<void>(');
      expect(suspendIdx, greaterThan(0));
      expect(dialogIdx, greaterThan(suspendIdx), reason: '必须先隐藏原生窗口');
      expect(body, contains('await _resumeNativeUiAfterDialog(suspended);'));
    });

    test('房间解散提示：弹框前 suspend', () {
      final idx = screen.indexOf('void _showRoomDestroyedDialog() {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 1200);
      expect(body, contains('unawaited(_suspendNativeUiForDialog());'));
    });

    test('603 的离房确认 suspend/resume 保持不回退', () {
      final idx = screen.indexOf('Future<void> _exitFromNativeUi() async {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 2600);
      expect(body, contains('await mpv.suspendNativeUi();'));
      expect(body, contains('await mpv.resumeNativeUi();'));
    });
  });
}
