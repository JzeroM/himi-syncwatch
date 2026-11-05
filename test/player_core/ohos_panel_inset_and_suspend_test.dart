import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 603：横屏弹出面板收窄到视频区 + suspend/resume 替代 close/reopen。
void main() {
  final view = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final panel = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'NativePlayerPanel.ets',
  ).readAsStringSync();
  final ohosPlugin = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
    'HimiMpvOhosPlugin.ets',
  ).readAsStringSync();
  final ohosLib = File('plugins/himi_mpv_ohos/lib/himi_mpv_ohos.dart')
      .readAsStringSync();
  final androidHost = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'AndroidNativePlayerHost.kt',
  ).readAsStringSync();
  final androidChannel = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'AndroidNativePlayerChannel.kt',
  ).readAsStringSync();
  final platform = File('lib/services/player/mpv_session_platform.dart')
      .readAsStringSync();
  final adapter = File('lib/services/player/mpv_player_adapter.dart')
      .readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();

  group('① 横屏弹出面板收窄到视频区', () {
    test('NativePlayerPanel 新增 @Prop videoW', () {
      expect(panel, contains('@Prop videoW: number = 0;'));
    });

    test('面板根容器按 videoW 收窄，0 回落 100%', () {
      expect(panel, contains(".width(this.videoW > 0 ? this.videoW : '100%')"));
      expect(panel, contains(".height('100%')"));
    });

    test('调用点传入 videoW', () {
      expect(view, contains('videoW: this.videoW,'));
    });

    test('安卓参考基准仍在（panelLeftMarginPx）', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerScreenView.kt',
      ).readAsStringSync();
      expect(kotlin, contains('private fun panelLeftMarginPx(panelW: Int, fullBleed: Boolean): Int'));
      expect(kotlin, contains('videoAreaWidth() - panelW - dp(NPTheme.PANEL_RIGHT)'));
    });
  });

  group('② 适配器 suspend/resume（不销毁 session）', () {
    test('适配器提供 suspendNativeUi / resumeNativeUi', () {
      expect(adapter, contains('Future<void> suspendNativeUi() async {'));
      expect(adapter, contains('Future<void> resumeNativeUi() async {'));
      expect(adapter, contains('bool _nativeUiSuspended = false;'));
    });

    test('close 时重置 suspend 标记', () {
      final idx = adapter.indexOf('Future<void> _closeNativeUi() async {');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 300);
      expect(body, contains('_nativeUiSuspended = false;'));
    });

    test('platform 层转发到两平台', () {
      expect(platform, contains('static Future<void> suspendNativeUi()'));
      expect(platform, contains('static Future<void> resumeNativeUi()'));
      expect(platform, contains('HimiMpvPlayer.suspendNativeUi()'));
      expect(platform, contains('AndroidNativePlayer.suspend()'));
    });
  });

  group('③ 平台侧只隐藏不销毁', () {
    test('鸿蒙用 minimize / showWindow，不 destroyWindow', () {
      // SDK 的 Window 没有 hideWindow()；官方文档：子窗口/悬浮窗调
      // minimize() 即隐藏，可用 showWindow() 恢复。
      expect(ohosPlugin, contains("case 'suspendNativeUi':"));
      expect(ohosPlugin, contains("case 'resumeNativeUi':"));
      final idx = ohosPlugin.indexOf('private suspendNativeUi(result: MethodResult): void {');
      expect(idx, greaterThan(0));
      final body = ohosPlugin.substring(idx, idx + 700);
      // 只检查代码行（注释里会提到 hideWindow 说明为何不用它）。
      final codeLines = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeLines, contains('win.minimize()'));
      expect(codeLines, isNot(contains('destroyWindow')));
      expect(codeLines, isNot(contains('hideWindow')));
      // resume 用 showWindow。
      final rIdx = ohosPlugin.indexOf('private resumeNativeUi(result: MethodResult): void {');
      expect(rIdx, greaterThan(0));
      expect(ohosPlugin.substring(rIdx, rIdx + 700), contains('win.showWindow()'));
    });

    test('鸿蒙 Dart 侧方法存在', () {
      expect(ohosLib, contains("invokeMethod<void>('suspendNativeUi')"));
      expect(ohosLib, contains("invokeMethod<void>('resumeNativeUi')"));
    });

    test('安卓用 hide/show，不 dismiss', () {
      final idx = androidHost.indexOf('fun suspend() {');
      expect(idx, greaterThan(0));
      final body = androidHost.substring(idx, idx + 900);
      expect(body, contains('ctrl.hide()'));
      expect(body, contains('surf.hide()'));
      expect(body, isNot(contains('dismiss()')));
    });

    test('安卓 channel 路由 suspend/resume', () {
      expect(androidChannel, contains('"suspend" ->'));
      expect(androidChannel, contains('"resume" ->'));
    });
  });

  group('④ 离房确认：suspend → 弹框 → 取消 resume / 确认 close', () {
    test('先 suspend 再 _confirmLeaveRoom', () {
      final idx = screen.indexOf('Future<void> _exitFromNativeUi() async {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 2600);
      final suspendIdx = body.indexOf('await mpv.suspendNativeUi();');
      final confirmIdx = body.indexOf('await _confirmLeaveRoom();');
      expect(suspendIdx, greaterThan(0));
      expect(confirmIdx, greaterThan(suspendIdx), reason: '必须先隐藏原生窗口再弹框');
    });

    test('取消分支 resume（不 close）', () {
      final idx = screen.indexOf('Future<void> _exitFromNativeUi() async {');
      final body = screen.substring(idx, idx + 2600);
      final cancelIdx = body.indexOf('if (!shouldPop) {');
      expect(cancelIdx, greaterThan(0));
      // 取消分支到 `return;` 为止（不含后面的确认分支）。
      final cancelEnd = body.indexOf('return;', cancelIdx);
      expect(cancelEnd, greaterThan(cancelIdx));
      final cancelBody = body.substring(cancelIdx, cancelEnd);
      expect(cancelBody, contains('await mpv.resumeNativeUi();'));
      expect(cancelBody, isNot(contains('closeNativeUi')));
    });

    test('确认分支 close + pop', () {
      final idx = screen.indexOf('Future<void> _exitFromNativeUi() async {');
      final body = screen.substring(idx, idx + 2600);
      expect(body, contains('await mpv.closeNativeUi();'));
      expect(body, contains('Navigator.pop(context)'));
    });
  });

  group('⑤ 搜索流程改用 suspend/resume', () {
    test('搜索前 suspend，返回后 resume（不再 close/reopen）', () {
      final idx = screen.indexOf(
          'Future<void> _openRoomResourceSearchFromNative() async {');
      expect(idx, greaterThan(0));
      final body = screen.substring(idx, idx + 2600);
      expect(body, contains('await mpv.suspendNativeUi();'));
      expect(body, contains('await resume.resumeNativeUi();'));
      // 旧路径已移除。
      expect(body, isNot(contains('await mpv.closeNativeUi();')));
      expect(body, isNot(contains('reopenNativeUi()')));
    });
  });
}
