import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 627：鸿蒙 letterbox 尺寸必须镜像到 `@State`。
///
/// 真机症状：**初始进房间拉伸，隐藏再显示资源面板后才正常**。
///
/// 根因：`build()` 里写 `this.videoFitW()`——**方法体内**的
/// `@State`/宿主字段读取**不进 ArkUI 细粒度依赖集** → 视频宽高到达后
/// 不触发重绘 → XComponent 停留在 `'100%'`。
/// 「隐藏再显示面板」时 `roomPanelShown`（@State）翻转引起**整树重建**，
/// 顺带重算了尺寸 → 看起来正常。
///
/// 本文件已有三处同款记录（播放/暂停图标、控件状态、加载指示器），
/// 都是「方法体内读取不进依赖集」这个坑。
void main() {
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

  group('① 存在 @State 镜像字段', () {
    test('fitVideoW / fitVideoH 是 @State', () {
      expect(ohos, contains('@State fitVideoW: number = -1;'));
      expect(ohos, contains('@State fitVideoH: number = -1;'));
    });

    test('注释记录「方法体内读取不进依赖集」根因', () {
      expect(ohos, contains('不进依赖集'));
      expect(ohos, contains('隐藏再显示资源面板后才正常'));
    });
  });

  group('② build() 直读 @State（不调方法）', () {
    test('XComponent 宽高用 fitVideoW/H', () {
      final idx = ohos.indexOf('XComponent({');
      expect(idx, greaterThan(0));
      final body = ohos.substring(idx, idx + 2000);
      expect(body, contains('this.fitVideoW > 0 ? this.fitVideoW'));
      expect(body, contains('this.fitVideoH > 0 ? this.fitVideoH'));
      // 旧的「直接调方法」必须消失（那不进依赖集）。
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('.width(this.videoFitW()')));
      expect(code, isNot(contains('.height(this.videoFitH()')));
    });
  });

  group('③ refreshVideoFit 方法与三处触发', () {
    test('方法存在且带值比对（防无效重绘）', () {
      final body = bodyOf(ohos, 'private refreshVideoFit(): void {');
      expect(body, contains('this.videoFitW()'));
      expect(body, contains('this.videoFitH()'));
      expect(body, contains('if (w !== this.fitVideoW)'));
      expect(body, contains('if (h !== this.fitVideoH)'));
    });

    test('三处触发：tick / videoArea onAreaChange / syncFromHost', () {
      // tick()
      final tick = bodyOf(ohos, 'private tick(): void {');
      expect(tick, contains('this.refreshVideoFit()'));
      // syncFromHost()
      final sync = bodyOf(ohos, 'private syncFromHost(): void {');
      expect(sync, contains('this.refreshVideoFit()'));
      // videoArea 的 onAreaChange
      expect(ohos, contains('this.videoAreaH = h;'));
      final idx = ohos.indexOf('this.videoAreaH = h;');
      final after = ohos.substring(idx, idx + 300);
      expect(after, contains('this.refreshVideoFit()'));
    });
  });

  group('④ 比例算法仍正确（回归保护）', () {
    test('videoFitW/H 宽高择一 + 未就绪返回 -1', () {
      final w = bodyOf(ohos, 'private videoFitW(): number {');
      expect(w, contains('videoAspect > areaAspect ? aw : ah * videoAspect'));
      expect(w, contains('return -1;'));
      final h = bodyOf(ohos, 'private videoFitH(): number {');
      expect(h, contains('videoAspect > areaAspect ? aw / videoAspect : ah'));
      expect(h, contains('return -1;'));
    });
  });
}
