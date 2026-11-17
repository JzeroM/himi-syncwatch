import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 694 真机回归三连守卫（日志钉死根因后的修复，防回退）：
///
/// 1. **MDK→其它引擎闪退**：`_recreateEngineForLoad` 旧序「先卸视频视图
///    → 再释放引擎」与 fvp 的异步原生 `mdkPlayerAPI_delete`（另一 isolate、
///    无完成信号）对撞 → SIGSEGV。必须**先释放旧引擎（视图仍挂载）再卸层**。
/// 2. **原生 UI 打开失败回退黑屏**：失败 catch 必须 `refreshSurface()`
///    重同步（成功路径有，失败路径曾漏 → 平台视图重挂后绑定靠运气）。
/// 3. **鸿蒙切解码模式卡顿**：`textureSize` 的 1.2s 短等在鸿蒙必然吃满
///    （video-params 是 NODE 属性读不到）→ 必须有 `width/height` 标量兜底。
void main() {
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final adapter =
      File('lib/services/player/mpv_player_adapter.dart').readAsStringSync();

  String extractFun(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    // 跳过参数表（签名可能以 `({` 结尾，参数表 `{}` 会被误当函数体）。
    // 仅当 `(` 出现在首个 `{` 之前才算参数表——getter（get xxx）没有参数
    // 表，直接找 `(` 会跳进函数体内的调用括号。
    var i = start;
    final firstParen = src.indexOf('(', start);
    final firstBrace = src.indexOf('{', start);
    if (firstParen >= 0 && (firstBrace < 0 || firstParen < firstBrace)) {
      var paren = 0;
      for (i = firstParen; i < src.length; i++) {
        if (src[i] == '(') paren++;
        if (src[i] == ')') {
          paren--;
          if (paren == 0) break;
        }
      }
    }
    var depth = 0;
    var started = false;
    for (; i < src.length; i++) {
      if (src[i] == '{') {
        depth++;
        started = true;
      } else if (src[i] == '}') {
        depth--;
        if (started && depth == 0) {
          // 剥整行注释：注释里会引用 addView/removeAllViews 等字样（说明
          // 为什么改），直接 indexOf 会误中注释。
          return src
              .substring(start, i + 1)
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
        }
      }
    }
    return src.substring(start);
  }

  group('① 引擎重建步序：先释放旧引擎、后卸视频层', () {
    test('_recreateEngineForLoad 里 _disposeOldEngine 在 _switchingEngine 之前', () {
      final body = extractFun(
          screen, 'Future<void> _recreateEngineForLoad(');
      final disposeIdx = body.indexOf('await _disposeOldEngine();');
      final hideIdx = body.indexOf('setState(() => _switchingEngine = true);');
      expect(disposeIdx, greaterThanOrEqualTo(0), reason: '必须释放旧引擎');
      expect(hideIdx, greaterThanOrEqualTo(0), reason: '必须隐藏视频层');
      expect(disposeIdx, lessThan(hideIdx),
          reason:
              '694 闪退根因：先卸视图（SurfaceView/纹理销毁）再释放引擎会与 '
              'fvp 的异步原生 delete 对撞 → SIGSEGV。顺序不得回退');
    });

    test('步序日志同步落盘（崩溃取证）', () {
      final body = extractFun(
          screen, 'Future<void> _recreateEngineForLoad(');
      expect(body, contains('[rebuild] 3/7 释放旧引擎'));
      expect(body, contains('[rebuild] 4/7 隐藏视频层'));
      expect(body, contains('sync: true'));
    });
  });

  group('② 原生 UI 打开失败回退链', () {
    test('catch 必须 refreshSurface 重同步', () {
      final body = extractFun(
          adapter, 'Future<void> _openNativeUiIfNeeded({');
      // 失败分支（原生 UI 打开失败）之后必须有 surface 重同步。
      final failIdx = body.indexOf('原生 UI 打开失败');
      expect(failIdx, greaterThanOrEqualTo(0));
      expect(body.substring(failIdx), contains('refreshSurface()'),
          reason:
              '694 黑屏次生因素：失败回退漏 refreshSurface，平台视图重挂后 '
              'mpv 绑定靠事件碰运气');
    });
  });

  group('③ 鸿蒙 textureSize 短等不再必然超时', () {
    test('known() 有 width/height 标量兜底（NODE 读不到的端可早退）', () {
      final body = extractFun(adapter, 'Future<Size?> get textureSize');
      expect(body, contains('_lastVideoW'),
          reason:
              '694 鸿蒙卡顿根因：video-params 是 NODE 属性鸿蒙读不到 → '
              'mediaInfo 恒空 → 1.2s 每次吃满。需标量兜底');
    });

    test('轮询循环内直接问标量属性（一次往返即返回）', () {
      final body = extractFun(adapter, 'Future<Size?> get textureSize');
      expect(body, contains("getProperty('width')"));
      expect(body, contains("getProperty('height')"));
    });
  });

  group('④ MDK 释放确定性 teardown（3/3 必闪退根因）', () {
    final mdkAdapter = File('lib/player_core/adapters/nipa_mdk_adapter.dart')
        .readAsStringSync();

    test('teardown 步序：stop → 释放纹理 → delete → settle', () {
      final stopIdx = mdkAdapter.indexOf('mdk teardown: stop');
      final textureIdx = mdkAdapter.indexOf('mdk teardown: texture released');
      final completeIdx = mdkAdapter.indexOf('mdk teardown: complete');
      final settledIdx = mdkAdapter.indexOf('mdk teardown: settled');
      expect(stopIdx, greaterThanOrEqualTo(0));
      expect(textureIdx, greaterThan(stopIdx), reason: '先 stop 再释放纹理');
      expect(completeIdx, greaterThan(textureIdx), reason: '释放纹理后才 delete');
      expect(settledIdx, greaterThan(completeIdx), reason: 'delete 后 settle');
    });

    test('delete 前必须确定性释放纹理（updateTexture(-1)）', () {
      expect(mdkAdapter, contains('updateTexture(width: -1)'),
          reason:
              'fvp dispose 是 fire-and-forget 的 mdkPlayerAPI_delete，裸删必崩；'
              '必须先 await 释放纹理（MdkPlayerAdapter._disposeImpl 范式）');
    });

    test('Flutter TV 引擎胶囊为纯文字且切换联动', () {
      expect(screen, contains("ValueKey('playerKernelTextChip')"));
      expect(screen, contains('_currentEngine.shortLabel'),
          reason: '切引擎后文案随 _currentEngine 联动');
      expect(screen, isNot(contains('Icons.memory')),
          reason: 'TV 引擎胶囊已改纯文字（MDK/Erika/MPV）');
    });
  });
}
