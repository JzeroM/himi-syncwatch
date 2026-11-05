import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 601：鸿蒙横屏控件层贴左 + 房间模式锁控件不再消失。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final flutter = File('lib/screens/player/player_screen.dart').readAsStringSync();

  group('① 横屏控件层贴左上（不再居中/被面板切掉）', () {
    test('控件层靠根 Stack 的 TopStart 贴左（不是 .align）', () {
      // `Alignment.Top` 的**水平**对齐是 Center——容器宽度是具体数值
      //（屏宽 - 320vp，不足 100%）时会被水平居中，右缘被资源面板切掉。
      // `.align()` 只管「内容在自身绘制区内对齐」，无法定位自身在父 Stack
      // 的位置（601 用它是错的，真机截图证实无效）。
      expect(view, contains('Stack({ alignContent: Alignment.TopStart })'));
      // 601 的无效写法已移除（注释里提到它不算，只检查属性行）。
      final attrLines = view
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(attrLines, isNot(contains('.align(Alignment.TopStart)')));
    });

    test('控件层仍按 controlsW/controlsH 收窄', () {
      final idx = view.indexOf('if (this.showControls && this.renderTick >= 0) {');
      final body = view.substring(idx, idx + 5000);
      expect(body, contains(".width(this.controlsW > 0 ? this.controlsW : '100%')"));
      expect(body, contains(".height(this.controlsH > 0 ? this.controlsH : '100%')"));
    });

    test('根 Stack 改为 TopStart（.align 无效已被替换）', () {
      // 601 加的 `.align(Alignment.TopStart)` 是**错的**：`.align()` 语义是
      // 「组件内容在自身绘制区内的对齐」，不能定位组件在父 Stack 中的位置。
      expect(view, contains('Stack({ alignContent: Alignment.TopStart })'));
      expect(view, contains('根 Stack 对齐改 TopStart'));
    });
  });

  group('② 房间模式锁控件不再消失', () {
    test('底栏锁钮条件只看 tvMode，不含 isRoom', () {
      final idx = view.indexOf('ControlRow() {');
      expect(idx, greaterThan(0));
      final body = view.substring(idx, idx + 3000);
      // 锁钮必须出现在 ControlRow 内，且其 if 条件不含 isRoom。
      expect(body, contains('if (!this.state().tvMode) {'));
      expect(body, contains('NativePlayerIcons.ICON_LOCK_OPEN'));
      // 旧条件（房间模式跳过锁钮）已移除。
      expect(
        body,
        isNot(contains('if (!this.state().tvMode && !this.state().isRoom) {')),
      );
    });

    test('安卓参考基准：lockButton 只看 tv', () {
      expect(kotlin, contains('lockButton.visibility = if (!tv) VISIBLE else GONE'));
    });

    test('Flutter 参考基准：showPhoneLock 不含房间判断', () {
      expect(flutter, contains('final showPhoneLock ='));
      expect(
        flutter,
        contains('phoneControls && PlayerScreen.showLockButton(tvMode: tvMode)'),
      );
    });

    test('注释记录根因', () {
      expect(view, contains('房间模式锁控件消失'));
    });
  });

  group('③ 600 的分栏/流式布局保持不回退', () {
    test('控件层仍是 Column + Blank 流式（无 position/markAnchor）', () {
      expect(RegExp(r'^\s*\.position\(', multiLine: true).hasMatch(view), isFalse);
      expect(RegExp(r'^\s*\.markAnchor\(', multiLine: true).hasMatch(view), isFalse);
      expect(view, contains('Blank();'));
    });

    test('updateControlsSplit 仍在三处被调用', () {
      expect(
        RegExp(r'this\.updateControlsSplit\(\);').allMatches(view).length,
        greaterThanOrEqualTo(3),
      );
    });

    test('资源行图标仍按 roomPlayEpoch 重建', () {
      expect(view, contains('@State roomPlayEpoch: number = 0;'));
      expect(view, contains('ForEach([this.roomPlayEpoch]'));
      expect(view, contains('ep.isPlaying && !this.paused'));
    });

    test('599 的单 Stack 结构保持', () {
      expect(
        RegExp(r'GestureGroup\(GestureMode\.Parallel').allMatches(view).length,
        1,
      );
      expect(RegExp(r'XComponent\(\{').allMatches(view).length, 1);
      expect(view, isNot(contains('.translate(')));
    });
  });
}
