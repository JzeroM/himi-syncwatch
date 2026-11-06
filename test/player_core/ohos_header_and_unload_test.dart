import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 606：鸿蒙头部控件不被挤压 + 面板开关位置 + 删除播放中资源真正停播。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final adapter = File('lib/services/player/mpv_player_adapter.dart')
      .readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();

  group('① 头部三控件不被标题的 layoutWeight 挤压', () {
    test('人数胶囊有 constraintSize 下限', () {
      // ArkUI 的 layoutWeight(1) 会吃掉全部剩余空间，把兄弟节点压到 0 宽。
      // 安卓注释记录过同一 bug：「标题撑满后把三者挤到最右」。
      final idx = view.indexOf("backgroundColor('#1FFFFFFF')");
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 700);
      expect(body, contains('.constraintSize({ minWidth: 40, minHeight: 20 })'));
    });

    test('角色徽章有 constraintSize 下限', () {
      final idx = view.indexOf("backgroundColor(this.roomIsHost ? SEL_COLOR : '#E53935')");
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 500);
      expect(body, contains('.constraintSize({ minWidth: 32, minHeight: 20 })'));
    });

    test('搜索图标仍有显式宽高（28）', () {
      final idx = view.indexOf('if (this.roomIsHost && this.paused) {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 400);
      expect(body, contains('.width(28)'));
      expect(body, contains('.height(28)'));
    });

    test('注释记录根因', () {
      expect(view, contains('初始房间头部不显示搜索/人数/房主徽章'));
    });
  });

  group('② 面板开关按钮对齐安卓 trailing 槽布局', () {
    test('panelToggle 在 trailing 槽内、图标簇之后', () {
      // 安卓：trailingGroup.addView(panelToggleButton, llp(dp(32), dp(32), CONTROL_GAP))
      // 结构要求：panelToggle 必须在图标簇（内层 Row）闭合之后，且位于
      // trailing 槽（justifyContent: End）的属性链之内。
      final toggleIdx = view.indexOf("'panelToggle'");
      expect(toggleIdx, greaterThan(0));

      // 图标簇（20 间距 Row）的起始位置必须在 panelToggle 之前。
      final clusterIdx = view.lastIndexOf('Row({ space: 20 * this.bottomScale })', toggleIdx);
      expect(clusterIdx, greaterThan(0), reason: 'panelToggle 应在图标簇之后');

      // trailing 槽的收尾属性在 panelToggle 之后（说明它在该槽内）。
      final slotEnd = view.indexOf('.justifyContent(FlexAlign.End)', toggleIdx);
      expect(slotEnd, greaterThan(toggleIdx), reason: 'panelToggle 应在 trailing 槽内');
    });

    test('panelToggle 有与图标簇的间距（外层 Row 承载，@Builder 不能接链式）', () {
      // `this.IconChip(...)` 是 @Builder、返回 void，不能写 `.margin(...)`
      //（ArkTS 报 "Property 'margin' does not exist on type 'void'"）。
      final idx = view.indexOf("'panelToggle'");
      final body = view.substring(idx, idx + 700);
      // 607 起额外加了 right: 8（防压线资源面板边界）。
      expect(body, contains(".margin({ left: 20 * this.bottomScale, right: 8 })"));
      // 必须由外层 Row 承载。
      final before = view.substring(idx - 300, idx);
      expect(before, contains('Row() {'));
    });

    test('安卓参考基准仍在', () {
      expect(kotlin, contains('panelToggleButton.visibility = if (state.isRoom) VISIBLE else GONE'));
      expect(kotlin, contains('trailingGroup.addView(panelToggleButton'));
    });
  });

  group('③ 删除正在播放的资源要真正停播', () {
    test('适配器新增 unloadMedia 并重置 _prepared', () {
      expect(adapter, contains('Future<void> unloadMedia() async {'));
      final idx = adapter.indexOf('Future<void> unloadMedia() async {');
      final body = adapter.substring(idx, idx + 900);
      expect(body, contains('_prepared = false;'));
      expect(body, contains('_positionMs = 0;'));
      expect(body, contains('_durationMs = 0;'));
      expect(body, contains('await _player?.stop();'));
    });

    test('_removeEpisode 调 unloadMedia（不是只设 state）', () {
      final idx = screen.indexOf('void _removeEpisode(int index, {bool sendRtm = true}) {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 2000);
      expect(body, contains('unawaited(p.unloadMedia());'));
    });

    test('注释记录轮询把 stopped 覆盖回 playing 的根因', () {
      expect(adapter, contains('把 stopped 覆盖回 playing'));
    });

    test('轮询逻辑本身未被误改（仍按 _prepared 判断）', () {
      expect(adapter, contains('if (_prepared && hasProgress) {'));
    });
  });
}
