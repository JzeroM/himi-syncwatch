import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 602：横竖屏切换不再黑屏（视频层移出 if/else 分支）+ 控件层贴左。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  group('① 视频层唯一实例（转屏不销毁 XComponent）', () {
    test('全文件只调用一次 VideoStack（注释里的示例不算）', () {
      // 594 的 `if (portrait) { Column{VideoStack} } else { Row{VideoStack} }`
      // 双分支各写一份 → ArkUI 条件翻转整体销毁旧分支、创建新分支，
      // XComponent 随之 onSurfaceDestroyed → 解绑 → 黑一帧 → 重建重绑。
      final calls = view
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('this.VideoStack();'))
          .length;
      expect(calls, 1, reason: '视频层必须只有一个实例，转屏才不黑屏');
    });

    test('面板按方向用 margin 定位（只移动面板，不动视频）', () {
      // 视频层唯一实例后，方向切换只改面板的 margin。
      // - 竖屏：marginTop = videoH（贴底）；
      // - 横屏：marginStart(left) = videoW（贴右）。
      final idx = view.indexOf('RoomPanelSlot() {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 1200);
      expect(body, contains('this.videoH > 0 ? this.videoH : 0'));
      expect(body, contains('this.videoW > 0 ? this.videoW : 0'));
    });
  });

  group('② 视频区尺寸改用显式 videoW/videoH', () {
    test('新增 @State videoW / videoH', () {
      expect(view, contains('@State videoW: number = 0;'));
      expect(view, contains('@State videoH: number = 0;'));
    });

    test('VideoStack 按 videoW/videoH 收窄，0 时回落 100%', () {
      expect(view, contains(".width(this.videoW > 0 ? this.videoW : '100%')"));
      expect(view, contains(".height(this.videoH > 0 ? this.videoH : '100%')"));
    });

    test('不再使用 layoutWeight（视频层已不在弹性布局里）', () {
      final attrLines = view
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(attrLines, isNot(contains('.layoutWeight(this.roomPanelVisible()')));
    });

    test('updateControlsSplit 同时算 videoW/videoH', () {
      final idx = view.indexOf('private updateControlsSplit(): void {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 1400);
      expect(body, contains('this.videoW = Math.max(1, w - ROOM_PANEL_WIDTH);'));
      expect(body, contains('this.videoH = Math.max(1, h - ROOM_PANEL_HEIGHT);'));
    });
  });

  group('③ 控件层贴左靠根 Stack 的 TopStart', () {
    test('根 Stack alignContent 是 TopStart', () {
      // `Alignment.Top` 的水平对齐是 Center → 不足宽的子节点会被居中。
      expect(view, contains('Stack({ alignContent: Alignment.TopStart })'));
    });

    test('601 的无效 .align 已移除（属性行层面）', () {
      final attrLines = view
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(attrLines, isNot(contains('.align(Alignment.TopStart)')));
    });
  });

  group('④ 599/600 的修复保持不回退', () {
    test('手势层只有一层、XComponent 只有一个', () {
      expect(
        RegExp(r'GestureGroup\(GestureMode\.Parallel').allMatches(view).length,
        1,
      );
      expect(RegExp(r'XComponent\(\{').allMatches(view).length, 1);
    });

    test('控件层仍按 controlsW/controlsH 收窄', () {
      expect(view, contains(".width(this.controlsW > 0 ? this.controlsW : '100%')"));
      expect(view, contains(".height(this.controlsH > 0 ? this.controlsH : '100%')"));
    });

    test('仍无 position / markAnchor / translate', () {
      expect(RegExp(r'^\s*\.position\(', multiLine: true).hasMatch(view), isFalse);
      expect(RegExp(r'^\s*\.markAnchor\(', multiLine: true).hasMatch(view), isFalse);
      expect(view, isNot(contains('.translate(')));
    });

    test('房间模式锁钮条件只看 tvMode', () {
      final idx = view.indexOf('ControlRow() {');
      final body = view.substring(idx, idx + 3000);
      expect(body, contains('if (!this.state().tvMode) {'));
      expect(body, isNot(contains('if (!this.state().tvMode && !this.state().isRoom) {')));
    });

    test('资源行图标按 roomPlayEpoch 重建', () {
      expect(view, contains('ForEach([this.roomPlayEpoch]'));
      expect(view, contains('ep.isPlaying && !this.paused'));
    });
  });
}
