import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 625：三件事——
/// ① 鸿蒙竖条填充方向反了（顶部往下，应为底部往上）；
/// ② 鸿蒙画布拉伸（ohosvk 不响应运行时 swapchain 重配 → 改让画布本身
///    就是视频比例）；
/// ③ 安卓手势图标/柱条不在视频区（`Gravity.CENTER`/`END` 相对全屏）。
void main() {
  final flutter = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final android = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final gauge = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'VerticalGaugeView.kt',
  ).readAsStringSync();
  final state = File(
    'lib/services/player/native/native_player_state.dart',
  ).readAsStringSync();
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final ohosHost = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiMpvNativeHost.ets',
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

  group('① 竖条填充方向（底部往上）', () {
    test('鸿蒙用容器级 alignContent: Bottom（不是组件级 .align）', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 5000);
      expect(body, contains('Stack({ alignContent: Alignment.Bottom })'));
      // 旧实现用 .align(Alignment.Bottom)——ArkUI 里只管内容对齐，无效。
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('.align(Alignment.Bottom)')));
    });

    test('Flutter 基准：RotatedBox(-1) 使值 0 在底部', () {
      expect(flutter, contains('quarterTurns: -1'));
    });

    test('安卓基准：从 trackBottom 往上填充', () {
      expect(gauge, contains('trackBottom - filled'));
    });
  });

  group('② 画布按视频比例（鸿蒙）', () {
    test('NativePlayerState 有 videoWidth/videoHeight', () {
      expect(state, contains('final int videoWidth;'));
      expect(state, contains('final int videoHeight;'));
      // 序列化完整。
      expect(state, contains("'videoWidth': videoWidth"));
      expect(state, contains("json['videoWidth']"));
      expect(state, contains('videoWidth: videoWidth ?? this.videoWidth'));
      expect(state, contains('other.videoWidth == videoWidth'));
    });

    test('Dart 下发 _lastVideoW/_lastVideoH', () {
      expect(adapter, contains('videoWidth: _lastVideoW'));
      expect(adapter, contains('videoHeight: _lastVideoH'));
    });

    test('鸿蒙宿主解析两字段（在 NativePlayerUiState 内）', () {
      expect(ohosHost, contains('videoWidth: number = 0;'));
      expect(ohosHost, contains('videoHeight: number = 0;'));
      expect(ohosHost, contains('this.videoWidth = jsonNum(obj.videoWidth'));
      expect(ohosHost, contains('this.videoHeight = jsonNum(obj.videoHeight'));
      // 字段必须落在 NativePlayerUiState 类内（视图经 host.state 访问）。
      final stateIdx = ohosHost.indexOf('export class NativePlayerUiState {');
      final fieldIdx = ohosHost.indexOf('videoWidth: number = 0;');
      expect(stateIdx, greaterThan(0));
      expect(fieldIdx, greaterThan(stateIdx));
      // 视图用 state.videoWidth（不是 host.videoWidth）。
      expect(ohos, contains('HimiMpvNativeHost.getInstance().state.videoWidth'));
    });

    test('videoFitW/videoFitH 比例算法（宽高择一）', () {
      final w = bodyOf(ohos, 'private videoFitW(): number {');
      expect(w, contains('videoAspect > areaAspect ? aw : ah * videoAspect'));
      final h = bodyOf(ohos, 'private videoFitH(): number {');
      expect(h, contains('videoAspect > areaAspect ? aw / videoAspect : ah'));
      // 未就绪返回 -1（调用方回落 100%）。
      expect(w, contains('return -1;'));
      expect(h, contains('return -1;'));
    });

    test('XComponent 按 videoFitW/H 布局（不再撑满）', () {
      final idx = ohos.indexOf('XComponent({');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 1500);
      // 627：改为直读 @State 镜像（方法体内读取不进 ArkUI 依赖集）。
      expect(body, contains('this.fitVideoW > 0 ? this.fitVideoW'));
      expect(body, contains('this.fitVideoH > 0 ? this.fitVideoH'));
    });

    test('视频区实测 + Center 对齐（黑边对称）', () {
      expect(ohos, contains('@State videoAreaW: number = 0;'));
      expect(ohos, contains('@State videoAreaH: number = 0;'));
      expect(ohos, contains('Stack({ alignContent: Alignment.Center })'));
      // 测量挂在视频子节点（拿到视频区而非全屏）。
      expect(ohos, contains('this.videoAreaW = w;'));
      expect(ohos, contains('this.videoAreaH = h;'));
    });
  });

  group('③ 安卓手势图标/柱条在视频区', () {
    test('手势提示有视频区定位方法', () {
      expect(android, contains('private fun positionGestureHintInVideoArea()'));
      final body = bodyOf(android, 'private fun positionGestureHintInVideoArea() {');
      expect(body, contains('videoAreaWidth()'));
      expect(body, contains('videoAreaHeight()'));
      // WRAP_CONTENT 必须 post 实测。
      expect(body, contains('gestureHint.post {'));
      expect(body, contains('((videoW - w) / 2)'));
      expect(body, contains('((videoH - h) / 2)'));
    });

    test('showHintFor 里调用定位', () {
      final body = bodyOf(
        android,
        'private fun showHintFor(\n        text: String,\n        ms: Long,\n        iconFont: Typeface?,\n        withBackground: Boolean = true,\n    ) {',
      );
      expect(body, contains('positionGestureHintInVideoArea()'));
    });

    test('柱条用 START + marginStart（不再 END）', () {
      final body = bodyOf(android, 'private fun paintVerticalBar() {');
      expect(body, contains('lp.gravity = Gravity.START or Gravity.TOP'));
      expect(body, contains('(videoW - barW - edge).coerceAtLeast(0)'));
      expect(body, contains('lp.marginEnd = 0'));
      // 旧的 END 定位必须消失（注释除外）。
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('Gravity.END')));
    });

    test('初始 addView 也用 START', () {
      final idx = android.indexOf('addView(\n            gestureHint,');
      expect(idx, greaterThan(0));
      final body = android.substring(idx, idx + 400);
      expect(body, contains('Gravity.START or Gravity.TOP'));
    });
  });
}
