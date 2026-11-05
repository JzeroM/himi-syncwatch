import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 600：鸿蒙房间模式控件层收窄 / 资源行图标刷新 / 起播进度条跑末端。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final host = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiMpvNativeHost.ets',
  ).readAsStringSync();

  group('① 房间模式控件层收窄到视频区（对齐安卓 applyVideoSplit）', () {
    test('新增 controlsW / controlsH 两个 @State', () {
      expect(view, contains('@State controlsW: number = 0;'));
      expect(view, contains('@State controlsH: number = 0;'));
    });

    test('控件层容器按 controlsW/controlsH 收窄，0 时回落 100%', () {
      expect(view, contains(".width(this.controlsW > 0 ? this.controlsW : '100%')"));
      expect(view, contains(".height(this.controlsH > 0 ? this.controlsH : '100%')"));
    });

    test('横屏只收宽度、竖屏只收高度（对齐安卓语义）', () {
      expect(view, contains('this.controlsW = Math.max(1, w - ROOM_PANEL_WIDTH);'));
      expect(view, contains('this.controlsH = 0;'));
      expect(view, contains('this.controlsW = 0;'));
      expect(view, contains('this.controlsH = Math.max(1, h - ROOM_PANEL_HEIGHT);'));
    });

    test('updateControlsSplit 在 onAreaChange / onStateChanged / tick 都被调用', () {
      // onAreaChange 只在屏幕尺寸变化时触发；房间面板开关时屏幕尺寸不变，
      // 只靠它收窄永远不生效（面板盖住控件）。
      expect(
        RegExp(r'this\.updateControlsSplit\(\);').allMatches(view).length,
        greaterThanOrEqualTo(3),
        reason: 'onAreaChange + onStateChanged + tick 兜底',
      );
    });

    test('未分栏时两者归零（回落 100%，行为与分栏前一致）', () {
      final idx = view.indexOf('private updateControlsSplit(): void {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 900);
      expect(body, contains('this.controlsW = 0;'));
      expect(body, contains('this.controlsH = 0;'));
    });
  });

  group('② 控件层改为流式布局（彻底去掉百分比定位）', () {
    test('全文件不再有 .position / .markAnchor 实际调用', () {
      // 597 的 .translate 与 position/markAnchor 叠加把控件推出屏幕外；
      // 600 改用 Column + Blank 流式布局，彻底移除百分比定位。
      expect(
        RegExp(r'^\s*\.position\(', multiLine: true).hasMatch(view),
        isFalse,
        reason: '控件层必须流式布局，禁用 position',
      );
      expect(
        RegExp(r'^\s*\.markAnchor\(', multiLine: true).hasMatch(view),
        isFalse,
        reason: '控件层必须流式布局，禁用 markAnchor',
      );
    });

    test('底栏靠 Blank 弹性占位推到视频区底缘', () {
      final idx = view.indexOf('if (this.showControls && this.renderTick >= 0) {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 4000);
      expect(body, contains('Blank();'));
    });

    test('控件层不挡下层手势层', () {
      final idx = view.indexOf('if (this.showControls && this.renderTick >= 0) {');
      final body = view.substring(idx, idx + 4000);
      expect(body, contains('.hitTestBehavior(HitTestMode.Transparent);'));
    });

    test('锁定态锁钮也走流式（Blank 在前推到底）', () {
      final idx = view.indexOf('if (this.showControls && this.renderTick >= 0) {');
      final body = view.substring(idx, idx + 4000);
      expect(body, contains('this.LockOnlyBar({ rev: this.renderTick });'));
      // 锁定分支里 Blank 必须在 LockOnlyBar 之前（把锁钮推到底）。
      final blankIdx = body.indexOf('Blank();');
      final lockIdx = body.indexOf('this.LockOnlyBar({ rev: this.renderTick });');
      expect(blankIdx, lessThan(lockIdx));
    });
  });

  group('③ 资源行播放/暂停图标随状态刷新', () {
    test('新增 roomPlayEpoch 纪元与签名', () {
      expect(view, contains('@State roomPlayEpoch: number = 0;'));
      expect(view, contains("private roomPlaySig: string = '';"));
    });

    test('签名只含 paused | currentEpisodeIndex（不每 250ms 推进）', () {
      expect(
        view,
        contains(r'const playSig = `${this.paused}|${this.currentEpisodeIndex}`;'),
      );
      // 只有变化时才自增（不是 tick 无条件推进）。
      expect(view, contains('if (playSig !== this.roomPlaySig) {'));
    });

    test('RoomPanelSlot 按 roomPlayEpoch 重建', () {
      final idx = view.indexOf('RoomPanelSlot() {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 900);
      expect(body, contains('ForEach([this.roomPlayEpoch]'));
      expect(body, contains(r'`room-${epoch}`'));
      expect(body, contains('this.RoomPanel();'));
    });

    test('图标判定读 @State this.paused，不读 state().paused', () {
      expect(view, contains('ep.isPlaying && !this.paused'));
      expect(
        view,
        isNot(contains('ep.isPlaying && !this.state().paused')),
        reason: 'state() 是宿主普通字段，不在 ArkUI 观察链上',
      );
    });
  });

  group('④ 起播加载时进度条不再跑到末端', () {
    test('positionNowMs 在 durationMs <= 0 时直接返回上报位置', () {
      final idx = host.indexOf('positionNowMs(): number {');
      expect(idx, greaterThan(0));
      final body = host.substring(idx, idx + 1400);
      expect(body, contains('if (s.durationMs <= 0) {'));
      expect(body, contains('return s.positionMs;'));
    });

    test('注释说明根因（max 兜底 1 + 无上限外推）', () {
      expect(host, contains('起播加载时进度条跑到最末端'));
    });

    test('ProgressRow 的 max 兜底不再固定为 1', () {
      // 旧兜底 `durationMs > 0 ? durationMs : 1` 会让任何非零 value 算出
      // ratio=1（进度条顶到最右）。改为至少覆盖当前位置。
      expect(
        view,
        isNot(contains('max: this.durationMs > 0 ? this.durationMs : 1,')),
      );
      expect(
        view,
        contains('Math.max(this.dragging ? this.dragMs : this.posMs, 1)'),
      );
    });
  });

  group('⑤ 599 的结构修复保持不回退', () {
    test('手势层仍只有一层、XComponent 仍只有一个', () {
      expect(
        RegExp(r'GestureGroup\(GestureMode\.Parallel').allMatches(view).length,
        1,
      );
      expect(RegExp(r'XComponent\(\{').allMatches(view).length, 1);
    });

    test('VideoStack 仍是单 Stack 包裹', () {
      expect(view, contains('Stack({ alignContent: Alignment.Top }) {'));
      expect(view, contains(".width(this.roomPanelVisible() ? 'auto' : '100%')"));
      expect(view, contains('.layoutWeight(this.roomPanelVisible() ? 1 : 0)'));
    });

    test('不含 .translate', () {
      expect(view, isNot(contains('.translate(')));
    });
  });
}
