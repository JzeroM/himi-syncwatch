import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 618：安卓弹幕重写为**无状态纯函数**（对齐鸿蒙 `positionNowMs()`）。
///
/// 【真机回归：616 后弹幕仍然左右跳】616 引入了自维护锚点
///（`anchorPosMs`/`anchorFrameMs`）+ `drift/10` 平滑收敛——这正是鸿蒙在
/// 600 轮次**已经删掉**的东西（`DanmakuLayer.ets` 的「非匀速根因」注释：
/// *旧实现在外推上叠了「漂移 10%/帧牵引」→ 弹幕忽快忽慢*）。
///
/// 自维护锚点的致命缺陷：`setClock` 被两条路径调用——
///   ① Dart 每 200ms 的 `render()`（新快照）；
///   ② 本地 500ms 的 `applyState()`（**同一份旧快照**）。
/// 本地 tick 触发时帧时间已推进 ~250ms，`drift` 超过 150ms 阈值 → 重锚
/// → 位置回退 250ms → 视觉左右跳。
void main() {
  final danmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'DanmakuLayerView.kt',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final ohos = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'DanmakuLayer.ets',
  ).readAsStringSync();
  final ohosHost = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
    'HimiMpvNativeHost.ets',
  ).readAsStringSync();

  /// 提取函数体（配平大括号）。
  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx; i < src.length; i++) {
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

  group('① 位置计算：无状态纯函数（对齐鸿蒙）', () {
    test('616 的自维护锚点已全部删除（只查代码行，注释可留根因说明）', () {
      // 剥离注释后再断言——保留注释说明「为什么删」是必要的。
      final code = danmaku
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => !l.trimLeft().startsWith('*'))
          .join('\n');
      expect(code, isNot(contains('anchorPosMs')));
      expect(code, isNot(contains('anchorFrameMs')));
      expect(code, isNot(contains('SEEK_THRESHOLD_MS')));
      expect(code, isNot(contains('drift / 10')));
      expect(code, isNot(contains('frameStartNanos')));
      expect(code, isNot(contains('playRate')));
    });

    test('位置 = 快照 + 墙钟×倍速（与鸿蒙 positionNowMs 同构）', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('snapPosMs'));
      expect(body, contains('System.currentTimeMillis() - snapAtMs'));
      expect(body, contains('elapsed * snapSpeed'));
    });

    test('暂停 / 倍速<=0 时冻结在快照值', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('if (snapPaused || snapSpeed <= 0.0) return snapPosMs'));
    });

    test('时长未知（<=0）不外推（同鸿蒙 600 防御）', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('if (snapDurationMs <= 0) return snapPosMs'));
    });

    test('钳到时长上限、负数归零', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('if (projected > snapDurationMs) snapDurationMs'));
      expect(body, contains('if (capped < 0) 0'));
    });
  });

  group('② setClock 幂等（重复调用同一份快照无副作用）', () {
    test('直接覆盖快照字段，无收敛/无阈值', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      expect(body, contains('snapPosMs = positionMs'));
      expect(body, contains('snapAtMs = System.currentTimeMillis()'));
      expect(body, contains('snapPaused = paused'));
      expect(body, contains('snapSpeed = if (speed > 0.0) speed else 1.0'));
      expect(body, contains('snapDurationMs = durationMs'));
      // 不得出现任何「漂移吸收」逻辑。
      expect(body, isNot(contains('drift')));
      expect(body, isNot(contains('anchor')));
    });

    test('接收 durationMs 参数（第四参）', () {
      expect(danmaku, contains('durationMs: Long,'));
    });

    test('暂停停帧循环、播放启动帧循环', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      expect(body, contains('stopFrameLoop()'));
      expect(body, contains('startFrameLoop()'));
    });
  });

  group('③ Choreographer 帧驱动保留（只负责重绘）', () {
    test('帧回调仍用 Choreographer', () {
      expect(danmaku, contains('import android.view.Choreographer'));
      expect(
        danmaku,
        contains('private var frameCallback: Choreographer.FrameCallback? = null'),
      );
      expect(danmaku, contains('Choreographer.getInstance().postFrameCallback(cb)'));
      expect(danmaku, contains('Choreographer.getInstance().removeFrameCallback(it)'));
    });

    test('onDraw 不再自驱 postInvalidate（帧回调统一驱动）', () {
      final idx = danmaku.indexOf('override fun onDraw(canvas: Canvas) {');
      expect(idx, greaterThan(0));
      final body = danmaku.substring(idx);
      expect(body, isNot(contains('postInvalidateOnAnimation()')));
      expect(body, contains('if (!drewAny) stopFrameLoop()'));
    });

    test('空态停帧 + 销毁清理', () {
      expect(danmaku, contains('if (!enabled || items.isEmpty())'));
      expect(danmaku, contains('override fun onDetachedFromWindow()'));
    });
  });

  group('④ 618 诊断：位置回退打日志', () {
    test('回退时 Log.w 记录快照上下文', () {
      expect(danmaku, contains('import android.util.Log'));
      expect(danmaku, contains('位置回退'));
      expect(danmaku, contains('Log.w('));
      // 日志内容包含快照字段，便于定位是哪份快照导致的回退。
      expect(danmaku, contains('snap=\${snapPosMs}'));
    });

    test('正常播放不刷屏（仅回退且非暂停时打）', () {
      expect(danmaku, contains('if (pos < lastDiagPosMs && !paused)'));
    });
  });

  group('⑤ 调用方传四参（位置/冻结三态/倍速/时长）', () {
    test('setClock 传 state.durationMs', () {
      expect(
        kotlinScreen,
        contains('state.paused || state.buffering || state.ended'),
      );
      expect(kotlinScreen, contains('state.durationMs.toLong(),'));
    });

    test('注释记录 618 根因（两条调用路径）', () {
      expect(kotlinScreen, contains('618 真机回归：安卓弹幕仍然左右跳'));
      expect(kotlinScreen, contains('无状态纯函数'));
    });
  });

  group('⑥ 鸿蒙参考实现（语义基准，证明这是已验证做法）', () {
    test('鸿蒙弹幕直接读宿主 positionNowMs（无自维护锚点）', () {
      expect(ohos, contains('positionNowMs()'));
      expect(ohos, isNot(contains('anchorPosMs')));
    });

    test('鸿蒙 positionNowMs = 快照 + 墙钟×倍速', () {
      final body = bodyOf(ohosHost, 'positionNowMs(): number {');
      expect(body, contains('Date.now() - this.lastStateAtMs'));
      expect(body, contains('s.positionMs + elapsed * s.speed'));
      // 同样的三态冻结 + 时长未知不外推。
      expect(body, contains('s.paused || s.buffering || s.ended'));
      expect(body, contains('if (s.durationMs <= 0)'));
    });

    test('鸿蒙注释记录了「删除速度修正项」的教训', () {
      expect(ohos, contains('非匀速根因'));
      // 原文跨行：「修复 = 删除一切\n   * 速度修正项」。
      expect(ohos, contains('删除一切'));
      expect(ohos, contains('速度修正项'));
    });
  });
}
