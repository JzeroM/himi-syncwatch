import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 弹幕时钟（P1）：安卓 / 鸿蒙两端的**同构实现**。
///
/// ## 历史教训（为什么这里反复改）
///
/// 616 曾用「自维护锚点 + `drift/10` 牵引」，真机表现为**弹幕忽快忽慢**——
/// 因为牵引项在每帧额外注入位移，速度随漂移量变化。
///
/// 618 于是退回「快照 + 墙钟 × 倍速」的纯函数。它解决了牵引，但留下两个坑：
/// 1. **墙钟**（`currentTimeMillis` / `Date.now`）会被 NTP 校时拨动 → 整屏跳；
/// 2. **快照硬覆盖**：IPC 延迟一抖，弹幕就前后弹一下（真机「跳跃抖动」）。
///
/// 现在的方案（对齐 Dart `DanmakuClock`）：
/// - 锚点 + **单调时钟**投影（不再用墙钟）；
/// - 误差 ≤40ms 不修正；40~400ms **只改速率**（±5%）缓慢收敛；>400ms 才硬对齐；
/// - **换速率前必须先把锚点挪到当前投影位置**（rebase），否则整段 elapsed
///   会被重新缩放 → 位置瞬移（这才是 616 抽搐的真正原因，不是「有锚点」）。
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

  /// 剥离注释（保留说明是必要的，断言只看代码）。
  String stripComments(String src) => src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .where((l) => !l.trimLeft().startsWith('*'))
      .join('\n');

  group('① 安卓：单调时钟 + 锚点投影', () {
    test('1.1 用 elapsedRealtimeNanos，不再用墙钟做锚点', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('SystemClock.elapsedRealtimeNanos()'));
      expect(body, isNot(contains('System.currentTimeMillis()')));
    });

    test('1.2 位置 = 锚点 + 单调增量 × 有效速率', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('anchorPosMs'));
      expect(body, contains('anchorAtNs'));
      expect(body, contains('snapSpeed'));
    });

    test('1.3 暂停 / 速率<=0 冻结在锚点', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('if (snapPaused || snapSpeed <= 0.0) return anchorPosMs'));
    });

    test('1.4 时长未知（<=0）不外推', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('if (snapDurationMs <= 0) return anchorPosMs'));
    });

    test('1.5 钳到时长上限、负数归零', () {
      final body = bodyOf(danmaku, 'private fun currentPositionMs(): Long {');
      expect(body, contains('if (projected > snapDurationMs) snapDurationMs'));
      expect(body, contains('if (capped < 0) 0'));
    });
  });

  group('② 安卓：死区 / 收敛 / 硬对齐', () {
    test('2.1 阈值与收敛上限固定', () {
      expect(danmaku, contains('DEADBAND_MS = 40L'));
      expect(danmaku, contains('HARD_RESYNC_MS = 400L'));
      expect(danmaku, contains('CONVERGE_MS = 600.0'));
      expect(danmaku, contains('MAX_RATE_ADJUST = 0.05'));
    });

    test('2.2 大误差才硬对齐（seek / 卡顿恢复）', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      expect(body, contains('HARD_RESYNC_MS'));
      expect(body, contains('hardResync(positionMs, false, rate)'));
    });

    test('2.3 换速率前必须 rebase（防位置瞬移）', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      final rebaseIdx = body.indexOf('rebaseAnchor()');
      final speedIdx = body.indexOf('snapSpeed =');
      expect(rebaseIdx, greaterThan(0));
      expect(speedIdx, greaterThan(rebaseIdx),
          reason: '必须先 rebase 再改速率，否则整段 elapsed 被重缩放');
    });

    test('2.4 幂等：同一份快照重复调用不重锚', () {
      final body = bodyOf(danmaku, 'fun setClock(');
      expect(body, contains('val sameInput = positionMs == lastClockPosMs'));
      expect(body, contains('if (sameInput)'));
    });
  });

  group('③ 安卓：帧驱动与诊断保留', () {
    test('3.1 Choreographer 只负责重绘', () {
      expect(danmaku, contains('import android.view.Choreographer'));
      expect(danmaku, contains('Choreographer.getInstance().postFrameCallback(cb)'));
      expect(danmaku, contains('Choreographer.getInstance().removeFrameCallback(it)'));
    });

    test('3.2 onDraw 不自驱 postInvalidate', () {
      final idx = danmaku.indexOf('override fun onDraw(canvas: Canvas) {');
      expect(idx, greaterThan(0));
      final body = danmaku.substring(idx);
      expect(body, isNot(contains('postInvalidateOnAnimation()')));
      expect(body, contains('if (!drewAny) stopFrameLoop()'));
    });

    test('3.3 回退诊断仍在（正常播放不刷屏）', () {
      expect(danmaku, contains('if (pos < lastDiagPosMs && !paused)'));
      expect(danmaku, contains('位置回退'));
      expect(danmaku, contains('err=\$clockErrorMs'));
    });
  });

  group('④ 调用方：三态冻结 + 时长 + 样式', () {
    test('4.1 setClock 传「暂停/缓冲/播完」+ 倍速 + 时长', () {
      expect(kotlinScreen, contains('state.paused || state.buffering || state.ended'));
      expect(kotlinScreen, contains('state.speed,'));
      expect(kotlinScreen, contains('state.durationMs.toLong(),'));
    });

    test('4.2 同时下发样式（P3）', () {
      expect(kotlinScreen, contains('danmakuLayer.setStyle('));
      expect(kotlinScreen, contains('state.danmakuColorMode,'));
    });
  });

  group('⑤ 鸿蒙：同构实现', () {
    test('5.1 弹幕层读专用时钟', () {
      expect(ohos, contains('danmakuPositionNowMs()'));
      expect(ohos, isNot(contains('.positionNowMs()')));
    });

    test('5.2 宿主时钟有锚点 + 死区 + 收敛', () {
      final body = bodyOf(ohosHost, 'danmakuPositionNowMs(): number {');
      expect(body, contains('dmAnchorPosMs'));
      expect(body, contains('dmEffSpeed'));
      expect(ohosHost, contains('DM_DEADBAND_MS: number = 40'));
      expect(ohosHost, contains('DM_HARD_RESYNC_MS: number = 400'));
      expect(ohosHost, contains('DM_MAX_ADJUST: number = 0.05'));
    });

    test('5.3 换速率前 rebase（与安卓同一条不变量）', () {
      final body = bodyOf(ohosHost, 'danmakuClockSync(): void {');
      final rebaseIdx = body.indexOf('dmAnchorPosMs = this.danmakuPositionNowMs()');
      final speedIdx = body.indexOf('dmEffSpeed =');
      expect(rebaseIdx, greaterThan(0));
      expect(speedIdx, greaterThan(rebaseIdx));
    });

    test('5.4 进度条时钟保持原样（两套语义解耦）', () {
      final body = bodyOf(ohosHost, 'positionNowMs(): number {');
      expect(body, contains('lastStateAtMs'));
      expect(body, isNot(contains('dmAnchorPosMs')));
    });
  });

  group('⑥ 不再使用墙钟（回归防线）', () {
    test('6.1 弹幕时钟相关代码里没有墙钟调用', () {
      final code = stripComments(danmaku);
      final calc = code.substring(
        code.indexOf('private fun currentPositionMs()'),
        code.indexOf('fun setStyle('),
      );
      expect(calc, isNot(contains('System.currentTimeMillis')));
      expect(calc, isNot(contains('SystemClock.uptimeMillis')));
    });
  });
}
