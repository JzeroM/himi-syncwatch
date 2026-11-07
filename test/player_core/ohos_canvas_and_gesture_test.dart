import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 623：鸿蒙画布自适应 + 手势指示器/柱条对齐 Flutter。
///
/// ① 画布拉伸：`XComponent.onAreaChange` 在「房间面板初始就展开」场景
///    可能早于 Flex 布局完成（拿到全屏尺寸）→ mpv 按全屏画布合成 →
///    画面拉伸。「隐藏再显示面板」时尺寸二次变化、onAreaChange 正确触发
///    → 正常。修法：缓存实测值 + `tick()` 每 250ms 兜底同步。
/// ② 双击播放/暂停图标不在画布中心：容器 `100%/100%` 是全屏。
/// ③ 音量/亮度滑杆不在画布两侧 + 样式不符：需完整复刻 Flutter
///    `_buildVerticalBar`（36 宽 / 圆角 18 / 图标 + 竖排滑杆 + 数值）。
void main() {
  final ohos = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiNativePlayerView.ets',
  ).readAsStringSync();
  final plugin = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/'
    'HimiMpvOhosPlugin.ets',
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

  group('① 画布尺寸兜底同步', () {
    test('缓存 XComponent 实测尺寸', () {
      expect(ohos, contains('private xcWidth: number = 0;'));
      expect(ohos, contains('private xcHeight: number = 0;'));
      // onAreaChange 里写缓存。
      final idx = ohos.indexOf('.onAreaChange(');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 1400);
      expect(body, contains('this.xcWidth = wVp;'));
      expect(body, contains('this.xcHeight = hVp;'));
    });

    test('tick() 调用 syncSurfaceSize 兜底', () {
      final body = bodyOf(ohos, 'private tick(): void {');
      expect(body, contains('this.syncSurfaceSize()'));
    });

    test('syncSurfaceSize 有幂等短路（避免每 tick 重复 setProperty）', () {
      final body = bodyOf(ohos, 'private syncSurfaceSize(): void {');
      expect(body, contains('if (wPx === host.canvasWidth && hPx === host.canvasHeight)'));
      expect(body, contains('return;'));
      // vp → px 换算（单位陷阱：vp 当 px 会让画布变成 1/3）。
      expect(body, contains('this.getUIContext().vp2px(wVp)'));
    });

    test('宿主侧 handleSurfaceChanged 已有幂等保护（双保险）', () {
      final body = bodyOf(plugin, 'handleSurfaceChanged(surfaceId: string, width: number, height: number): void {');
      expect(body, contains('if (prevW !== width || prevH !== height)'));
    });
  });

  group('② 手势提示在视频区居中（三处）', () {
    test('gestureHint 与倍速胶囊用 videoW/videoH', () {
      final count = 'this.videoW > 0 ? this.videoW'.allMatches(ohos).length;
      expect(count, greaterThanOrEqualTo(2), reason: '手势提示 + 倍速胶囊');
      final hCount = 'this.videoH > 0 ? this.videoH'.allMatches(ohos).length;
      // 手势提示 + 倍速胶囊 + 竖条容器 + 加载转圈 ≥ 4
      expect(hCount, greaterThanOrEqualTo(4));
    });

    test('不再对这三处使用全屏 100%/100% 居中', () {
      // gestureHint 容器后不应紧跟 width('100%') + height('100%')。
      final idx = ohos.indexOf('if (this.gestureHint.length > 0) {');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 1400);
      expect(body, isNot(contains(".width('100%')\n        .height('100%')\n        .justifyContent(FlexAlign.Center)")));
    });
  });

  group('③ 竖条完整复刻 Flutter 样式', () {
    test('竖条本体 36 宽 / 圆角 18 / 黑54 底', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 5000);
      expect(body, contains('.width(36)'));
      expect(body, contains('.borderRadius(18)'));
      expect(body, contains("'#8C000000'")); // black54
    });

    test('三段结构：图标 + 轨道 + 数值', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 5000);
      // 图标（18px white70）
      expect(body, contains('.fontSize(18)'));
      expect(body, contains("'#B3FFFFFF'"));
      // 轨道区（624：改为垂直 Stack + onAreaChange 实测，不再用 rotate）
      expect(body, contains('Stack({ alignContent: Alignment.Top })'));
      expect(body, contains('.onAreaChange('));
      // 数值（11px，无 % 号）
      expect(body, contains('.fontSize(11)'));
      expect(body, contains('Text(`\${this.verticalBarPercent}`)'));
      expect(body, isNot(contains('.width(48)')));
      expect(body, isNot(contains('Text(`\${this.verticalBarPercent}%`)')));
    });

    test('音量图标随百分比切换', () {
      expect(ohos, contains('private volumeGlyphFor(percent: number): number {'));
      final body = bodyOf(ohos, 'private volumeGlyphFor(percent: number): number {');
      expect(body, contains('NativePlayerIcons.ICON_VOLUME_OFF'));
      expect(body, contains('NativePlayerIcons.ICON_VOLUME_DOWN'));
      expect(body, contains('NativePlayerIcons.ICON_VOLUME_UP'));
    });

    test('配色：音量靛蓝 / 亮度琥珀', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 3000);
      expect(body, contains("'#6366F1'")); // 音量
      expect(body, contains("'#FFD54F'")); // 亮度
    });

    test('定位：视频区两侧 + 上下 30%（长度 40%，624 统一）', () {
      final idx = ohos.indexOf('if (this.verticalBarPercent >= 0) {');
      final body = ohos.substring(idx, idx + 5000);
      expect(body, contains('left: this.verticalBarOnLeft ? 0 : 20'));
      expect(body, contains('right: this.verticalBarOnLeft ? 20 : 0'));
      expect(body, contains('* 0.30'));
      expect(body, contains('.height(this.videoH > 0 ? this.videoH'));
      // 624：宽度也取视频区（旧实现 '100%' → 亮度条落到资源面板上）。
      expect(body, contains('.width(this.videoW > 0 ? this.videoW'));
    });
  });
}
