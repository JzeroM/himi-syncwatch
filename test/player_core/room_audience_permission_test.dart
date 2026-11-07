import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/player/native/native_player_command.dart';

/// 622：房间模式权限与观感（安卓 + 鸿蒙原生播放器）。
///
/// 四条要求：
/// ① 非房主不得控制播放/暂停（含手势）、切集、换资源、拖进度；
/// ② 非房主隐藏播放/暂停、切集、分享控件；
/// ③ 手势指示器/加载指示器在**视频区**内垂直居中（横竖屏都对）；
/// ④ 所有成员（含观众）都能手势调节音量和亮度。
void main() {
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final android = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohos = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx + signature.length - 1; i < src.length; i++) {
      final ch = src[i];
      if (ch == '{') {
        depth++;
        started = true;
      } else if (ch == '}') {
        depth--;
        if (started && depth == 0) return src.substring(idx, i + 1);
      }
    }
    fail('$signature 的大括号未配平');
  }

  group('① Dart 命令白名单（最后一道防线）', () {
    test('播放控制类命令被识别', () {
      const playbackControl = <NativePlayerCommand>[
        TogglePlay(),
        SeekTo(positionMs: 1000),
        SeekRelative(deltaMs: 5000),
        SelectEpisode(index: 1),
        SelectVersion(index: 1),
        RemoveResourceEpisode(index: 1),
        SetSpeed(speed: 2.0),
        SwitchEngine(engine: 'mdk'),
        ShareRoom(),
      ];
      for (final c in playbackControl) {
        expect(
          PlayerScreen.isPlaybackControlCommand(c),
          isTrue,
          reason: '${c.runtimeType} 应属播放控制',
        );
      }
    });

    test('本地设备类命令放行（音量/退出/面板/折叠/搜索/调试）', () {
      const allowed = <NativePlayerCommand>[
        SetVolume(volume: 0.5),
        RequestBack(),
        RequestExit(),
        ToggleResourcePanel(),
        ToggleResourceGroup(index: 0),
        ToggleResourceSeason(groupIndex: 0, seasonIndex: 0),
        OpenResourceSearch(),
        ToggleDebug(),
      ];
      for (final c in allowed) {
        expect(
          PlayerScreen.isPlaybackControlCommand(c),
          isFalse,
          reason: '${c.runtimeType} 不应被拦',
        );
      }
    });

    test('_handleNativeUiCommand 开头有守卫', () {
      final body =
          bodyOf(screen, 'Future<void> _handleNativeUiCommand(NativePlayerCommand command) async {');
      expect(body, contains('if (!_canControlPlayback &&'));
      expect(body, contains('PlayerScreen.isPlaybackControlCommand(command)'));
      expect(body, contains('观众无权执行'));
      // 守卫必须在 switch 之前。
      final guardIdx = body.indexOf('isPlaybackControlCommand');
      final switchIdx = body.indexOf('switch (command)');
      expect(guardIdx, lessThan(switchIdx));
    });
  });

  group('② 安卓按钮层守卫', () {
    test('播放/暂停、上一集、下一集 各有 canControl 检查', () {
      final body = bodyOf(android, 'private fun configureTransportListeners() {');
      final count = 'if (!lastState.canControl) return@setOnClickListener'
          .allMatches(body)
          .length;
      expect(count, 3, reason: 'prev/play/next 三处都要有');
    });

    test('进度条 seek 有 canControl 检查并回弹', () {
      final idx = android.indexOf('seekBar.onCommit = commit@{');
      expect(idx, greaterThan(0));
      final body = android.substring(idx, idx + 700);
      expect(body, contains('if (!lastState.canControl)'));
      expect(body, contains('return@commit'));
      // 回弹到权威位置（否则滑杆停在观众拖到的位置）。
      expect(body, contains('seekBar.value = lastState.positionAt('));
    });

    test('资源行点集有 canControl 检查', () {
      final idx = android.indexOf('listener?.onSelectEpisode(ep.index)');
      expect(idx, greaterThan(0));
      final before = android.substring((idx - 300).clamp(0, idx), idx);
      expect(before, contains('if (!lastState.canControl) return@setOnClickListener'));
    });
  });

  group('③ 安卓观众隐藏控件（INVISIBLE 占位）', () {
    test('分享按钮观众隐藏', () {
      expect(android, contains('if (state.isRoom && !state.isHost) INVISIBLE'));
    });

    test('播放/上一集/下一集 观众隐藏', () {
      expect(android, contains('val hideTransportForAudience = state.isRoom && !state.isHost'));
      expect(android, contains('INVISIBLE else VISIBLE'));
      expect(android, contains('playPauseButton.visibility = transportVisibility'));
      expect(android, contains('prevButton.visibility = transportVisibility'));
      expect(android, contains('nextButton.visibility = transportVisibility'));
    });
  });

  group('④ 指示器在视频区内居中', () {
    test('安卓音量/亮度竖条按视频区高居中', () {
      final body = bodyOf(android, 'private fun paintVerticalBar() {');
      expect(body, contains('videoAreaHeight()'));
      expect(body, contains('(videoH - barH) / 2'));
      // 旧实现是全屏 CENTER_VERTICAL（注释里保留了根因说明，只查代码行）。
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('Gravity.CENTER_VERTICAL')));
    });

    test('安卓加载转圈按视频区居中（新增定位方法）', () {
      expect(android, contains('private fun positionBufferingInVideoArea()'));
      final body = bodyOf(android, 'private fun positionBufferingInVideoArea() {');
      expect(body, contains('videoAreaHeight()'));
      expect(body, contains('((videoH - size) / 2)'));
      // 显示时重新定位（转屏/分栏会改变视频区高）。
      expect(android, contains('positionBufferingInVideoArea()'));
    });

    test('鸿蒙竖条与转圈用 videoH 而非全屏 100%', () {
      // 竖条
      expect(ohos, contains(".height(this.videoH > 0 ? this.videoH : '100%')"));
      final count =
          ".height(this.videoH > 0 ? this.videoH : '100%')".allMatches(ohos).length;
      expect(count, greaterThanOrEqualTo(2), reason: '竖条 + 加载转圈各一处');
    });
  });

  group('⑤ 音量/亮度手势对所有成员开放', () {
    test('安卓 onScroll 只检查 locked（不再检查 canControl）', () {
      final idx = android.indexOf('override fun onScroll(');
      expect(idx, greaterThan(0));
      final body = android.substring(idx, idx + 400);
      expect(body, contains('if (lastState.locked) return false'));
      expect(body, isNot(contains('!lastState.canControl) return false')));
    });

    test('安卓横拖 seek 仍受 canControl 限制', () {
      final idx = android.indexOf('if (dragAxis == AXIS_HORIZONTAL) {');
      expect(idx, greaterThan(0));
      final body = android.substring(idx, idx + 300);
      expect(body, contains('if (!lastState.canControl) return false'));
    });

    test('鸿蒙 onPanUpdate 只检查 locked', () {
      final body = bodyOf(ohos, 'private onPanUpdate(event: GestureEvent): void {');
      expect(body, contains('if (s.locked) {'));
      expect(body, isNot(contains('s.locked || !s.canControl')));
    });

    test('鸿蒙横拖 seek 仍受 canControl 限制', () {
      final body = bodyOf(ohos, 'private onPanUpdate(event: GestureEvent): void {');
      expect(body, contains('if (!s.canControl) {'));
    });
  });

  group('⑥ 鸿蒙进度条与控件显隐', () {
    test('进度条 onCommit 有 canControl 检查', () {
      final idx = ohos.indexOf('onCommit: (v: number): void => {');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 400);
      expect(body, contains('if (!this.canControl)'));
    });

    test('分享按钮观众隐藏（Visibility.Hidden 占位）', () {
      expect(ohos, contains('this.state().isHost ? Visibility.Visible : Visibility.Hidden'));
    });

    test('ProgressRow 声明 canControl 属性并接收（ArkTS 编译要求）', () {
      // 曾因 ProgressRow 内直接用 this.canControl 但未声明 → 编译失败
      // 「Property 'canControl' does not exist on type 'ProgressRow'」。
      final structIdx = ohos.indexOf('struct ProgressRow {');
      expect(structIdx, greaterThan(0));
      final structBody = ohos.substring(structIdx, structIdx + 900);
      expect(structBody, contains('canControl: boolean = true'));
      // 调用处必须传。
      expect(ohos, contains('canControl: this.canControl,'));
    });

    test('@Builder 调用不能链式加 .visibility（返回 void）', () {
      // 曾因 `this.IconChip(...).visibility(...)` → 编译失败
      // 「Property 'visibility' does not exist on type 'void'」。
      expect(
        ohos,
        isNot(contains("}, 1)\n            .visibility(")),
      );
      // 分享按钮改用容器包一层。
      expect(ohos, contains('.visibility(this.state().isHost ? Visibility.Visible : Visibility.Hidden)'));
    });

    test('TransportGlyph 支持 visible 参数', () {
      expect(ohos, contains('visible: boolean = true'));
      expect(ohos, contains('visible ? Visibility.Visible : Visibility.Hidden'));
      // prev/play/next 三处都传 canControl。
      final count = 'this.canControl);'.allMatches(ohos).length;
      expect(count, greaterThanOrEqualTo(3));
    });
  });
}
