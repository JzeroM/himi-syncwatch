import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 624：音量/亮度柱条**三端样式统一** + 长度缩短到 40% + 鸿蒙位置修复。
///
/// 参数逐项对齐 Flutter `_buildVerticalBar` / 安卓 `VerticalGaugeView`：
///   宽 36 · 圆角 18 · 黑54 底
///   [图标 18 white70，上边距 12] → [间距 8]
///   [轨道：粗 4 白24% + 填充 accent + 光晕 r10 + 拇指 r6 白]
///   → [间距 8] → [数值 11 white70，**纯数字无 % 号**]
///
/// 另修两处鸿蒙专属 bug：
/// ① 竖条容器 `width('100%')` 是全屏 → 亮度条贴全屏右缘、落到资源面板上；
/// ② 滑块用 `calc()` 定位 → ArkUI 不支持，滑块跑到轨道外。
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
  final gaugeConst = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerUi.kt',
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

  group('① 长度统一 40%（上下各留 30%）', () {
    test('Flutter 亮度/音量条用 0.30', () {
      final bright = bodyOf(flutter, 'Widget _buildBrightnessBar() {');
      expect(bright, contains('* 0.30'));
      final volume = bodyOf(flutter, 'Widget _buildVolumeBar() {');
      expect(volume, contains('* 0.30'));
      // 旧值 0.15 必须消失。
      expect(bright, isNot(contains('* 0.15')));
      expect(volume, isNot(contains('* 0.15')));
    });

    test('安卓用 videoAreaHeight() * 0.4f', () {
      expect(android, contains('(videoAreaHeight() * 0.4f).toInt()'));
      // 旧的固定 dp(160) 必须消失（注释除外）。
      final code = android
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('dp(160)')));
    });

    test('鸿蒙上下留白 0.30', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      expect(idx, greaterThan(0));
      // 625：竖条结构变长（新增嵌套 Stack），截取范围放宽。
      final body = ohos.substring(idx, idx + 6500);
      expect(body, contains('* 0.30'));
      expect(body, isNot(contains('* 0.15')));
    });
  });

  group('② 百分比格式统一为纯数字', () {
    test('安卓不再输出 % 号', () {
      expect(gauge, contains('canvas.drawText("\${percentOf(value)}"'));
      expect(gauge, isNot(contains('canvas.drawText("\${percentOf(value)}%"')));
    });

    test('鸿蒙输出纯数字', () {
      expect(ohos, contains('Text(`\${this.verticalBarPercent}`)'));
      expect(ohos, isNot(contains('Text(`\${this.verticalBarPercent}%`)')));
    });

    test('Flutter 输出纯数字（基准）', () {
      expect(flutter, contains("'\${(value * 100).round()}'"));
    });
  });

  group('③ 鸿蒙竖条位置修复（视频区而非全屏）', () {
    test('容器宽度用 videoW', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 4000);
      expect(body, contains(".width(this.videoW > 0 ? this.videoW : '100%')"));
    });

    test('左右贴边 20（音量左/亮度右）', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 6500);
      expect(body, contains('left: this.verticalBarOnLeft ? 0 : 20'));
      expect(body, contains('right: this.verticalBarOnLeft ? 20 : 0'));
    });
  });

  group('④ 鸿蒙滑块定位（弃用 calc，改 onAreaChange 实测）', () {
    test('不再使用 calc()（注释里的根因说明除外）', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 4000);
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('calc(')));
    });

    test('轨道 onAreaChange 实测高度', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 4000);
      expect(body, contains('.onAreaChange('));
      expect(body, contains('this.gaugeTrackH = h'));
    });

    test('gaugeThumbTop 按 ratio 反算（底部起填充）', () {
      final body = bodyOf(ohos, 'private gaugeThumbTop(radius: number): number {');
      expect(body, contains('this.gaugeTrackH'));
      expect(body, contains('(1 - ratio) * h - radius'));
    });
  });

  group('⑤ 鸿蒙样式补齐（图标间距 8 / 光晕 10）', () {
    test('图标上边距 12 + 轨道上下间距 8', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 4000);
      expect(body, contains('margin({ top: 12 })'));
      expect(body, contains('margin({ top: 8, bottom: 8 })'));
    });

    test('光晕 20/圆角 10/透明度 0.25', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 4000);
      expect(body, contains('.width(20)'));
      expect(body, contains('.borderRadius(10)'));
      expect(body, contains('.opacity(0.25)'));
    });

    test('拇指 12/圆角 6/白色', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 4000);
      expect(body, contains('.width(12)'));
      expect(body, contains('.borderRadius(6)'));
      expect(body, contains('Color.White'));
    });
  });

  group('⑥ 加载指示器不再铺满全屏（宽高都取视频区）', () {
    test('宽度也用 videoW', () {
      final idx = ohos.indexOf('if (this.showLoading) {');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 1200);
      expect(body, contains(".width(this.videoW > 0 ? this.videoW : '100%')"));
      expect(body, contains(".height(this.videoH > 0 ? this.videoH : '100%')"));
    });
  });

  group('⑦ 三端基础尺寸一致（36 / 18 / 黑54）', () {
    test('宽度 36', () {
      expect(flutter, contains('width: 36'));
      expect(gaugeConst, contains('GAUGE_WIDTH = 36'));
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      expect(ohos.substring(idx, idx + 4000), contains('.width(36)'));
    });

    test('圆角 18', () {
      expect(flutter, contains('BorderRadius.circular(18)'));
      expect(gaugeConst, contains('GAUGE_RADIUS = 18'));
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      expect(ohos.substring(idx, idx + 4000), contains('.borderRadius(18)'));
    });
  });
}
