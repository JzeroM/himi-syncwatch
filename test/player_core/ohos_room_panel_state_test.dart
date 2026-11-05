import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 605：鸿蒙面板显隐/头部控件必须走 @State（宿主普通字段不在观察链）。
/// 反引号（避免在断言里写模板字符串时被 Dart 当插值）。
String chr(int code) => String.fromCharCode(code);

void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('① 面板显隐镜像到 @State（收起后真正消失）', () {
    test('新增 @State roomPanelShown', () {
      expect(view, contains('@State roomPanelShown: boolean = false;'));
    });

    test('syncFromHost 同步 roomPanelShown', () {
      final idx = view.indexOf('private syncFromHost(): void {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 3000);
      expect(body, contains('this.roomPanelShown = s.isRoom && s.resourcePanelOpen;'));
    });

    test('build 的 if 条件读 @State（不读 roomPanelVisible()）', () {
      // ArkUI 的 if 节点不随宿主普通字段变化重新求值 → 收起后视频全屏了
      // 但面板节点还留在树里（真机回归）。
      final idx = view.indexOf('if (this.roomPanelShown) {');
      expect(idx, greaterThan(0));
      expect(view.substring(idx, idx + 200), contains('this.RoomPanelSlot();'));
      // 渲染路径里不得再用 roomPanelVisible()。
      final buildIdx = view.indexOf('  build() {');
      final buildBody = view.substring(buildIdx, buildIdx + 3000);
      expect(buildBody, isNot(contains('roomPanelVisible()')));
    });

    test('updateControlsSplit 也用 @State', () {
      final idx = view.indexOf('private updateControlsSplit(): void {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 900);
      expect(body, contains('const split = this.roomPanelShown &&'));
      expect(body, isNot(contains('this.roomPanelVisible()')));
    });
  });

  group('② 头部三控件数据源镜像到 @State（空房间也显示）', () {
    test('新增三个 @State 镜像字段', () {
      expect(view, contains('@State roomIsHost: boolean = false;'));
      expect(view, contains('@State roomOnlineCount: number = 0;'));
      expect(view, contains("@State roomAudienceName: string = '';"));
    });

    test('syncFromHost 同步三者', () {
      final idx = view.indexOf('private syncFromHost(): void {');
      final body = view.substring(idx, idx + 3000);
      expect(body, contains('this.roomIsHost = s.isHost;'));
      expect(body, contains('this.roomOnlineCount = s.onlineUserCount;'));
      expect(body, contains('this.roomAudienceName = s.audienceName;'));
    });

    test('搜索条件读 @State roomIsHost', () {
      expect(view, contains('if (this.roomIsHost && this.paused) {'));
      expect(
        view,
        isNot(contains('if (this.state().isHost && this.state().paused) {')),
      );
    });

    test('人数胶囊读 @State roomOnlineCount', () {
      // 用拼接避免 Dart 把 ${...} 当插值。
      expect(view, contains('Text(' + chr(96) + '\${this.roomOnlineCount}' + chr(96) + ')'));
      expect(
        view,
        isNot(contains('Text(' + chr(96) + '\${this.state().onlineUserCount}' + chr(96) + ')')),
      );
    });

    test('角色徽章读 @State', () {
      expect(view, contains('Text(this.roomIsHost\n          ? \'房主\''));
      expect(view, contains('this.roomAudienceName.length > 0'));
    });

    test('资源行的房主判断也读 @State（图标/删除/点击）', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      expect(body, contains('if (this.roomIsHost) {'));
      expect(body, isNot(contains('this.state().isHost')));
    });
  });

  group('③ 折叠态进签名（资源列表能展开子分支）', () {
    test('groupsSig 含组 collapsed', () {
      final idx = view.indexOf('const groupsSig =');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 500);
      expect(body, contains(r'${g.collapsed}'));
    });

    test('groupsSig 含季 collapsed', () {
      final idx = view.indexOf('const groupsSig =');
      final body = view.substring(idx, idx + 500);
      expect(body, contains(r'${s.collapsed}'));
    });

    test('注释记录根因', () {
      expect(view, contains('资源列表无法展开子分支'));
    });
  });

  group('④ 604 的修复保持不回退', () {
    test('底栏面板开关按钮仍在', () {
      expect(view, contains("'panelToggle'"));
      expect(view, contains("sendCommand('toggleResourcePanel', null)"));
    });

    test('删除按钮仍与内容区是兄弟节点', () {
      final idx = view.indexOf('RoomEpisodeRow(ep: NativeResourceItemUi) {');
      final end = view.indexOf('   * 视频层 + 手势层', idx);
      final body = view.substring(idx, end);
      final tail = body.substring(body.indexOf('.border(ep.isPlaying'));
      expect(tail, isNot(contains('.onClick(')));
    });
  });
}
