import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 616：安卓弹幕 Choreographer 帧驱动 + 平滑收敛（对齐 Flutter Ticker）。
void main() {
  final danmaku = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'DanmakuLayerView.kt',
  ).readAsStringSync();
  final kotlinScreen = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();
  final flutter = File('lib/screens/player/widgets/danmaku_overlay.dart')
      .readAsStringSync();

  group('① Choreographer 帧驱动（等价 Flutter Ticker）', () {
    test('引入 Choreographer 并维护帧回调', () {
      expect(danmaku, contains('import android.view.Choreographer'));
      expect(danmaku, contains('private var frameCallback: Choreographer.FrameCallback? = null'));
      expect(danmaku, contains('Choreographer.getInstance().postFrameCallback(cb)'));
      expect(danmaku, contains('Choreographer.getInstance().removeFrameCallback(it)'));
    });

    test('帧时间基准用单调时钟 nanoTime', () {
      expect(danmaku, contains('private var frameStartNanos = System.nanoTime()'));
      expect(danmaku, contains('(System.nanoTime() - frameStartNanos) / 1_000_000L'));
    });

    test('位置 = 锚点 + 帧时间增量（与 Flutter _nowPosition 等价）', () {
      expect(danmaku, contains('anchorPosMs + (frameElapsedMs() - anchorFrameMs) * playRate'));
    });

    test('onDraw 不再自驱 postInvalidate（帧回调统一驱动）', () {
      final idx = danmaku.indexOf('override fun onDraw(canvas: Canvas) {');
      expect(idx, greaterThan(0));
      final body = danmaku.substring(idx);
      expect(body, isNot(contains('postInvalidateOnAnimation()')));
      expect(body, contains('if (!drewAny) stopFrameLoop()'));
    });

    test('无弹幕空态也停帧循环（防空转耗电）', () {
      expect(
        danmaku,
        contains('''        if (!enabled || items.isEmpty()) {
            // 616：无弹幕可画时停掉帧循环（否则 Choreographer 空转耗电）。
            stopFrameLoop()
            return
        }'''),
      );
    });

    test('暂停停帧循环、销毁清理', () {
      expect(danmaku, contains('stopFrameLoop()'));
      expect(danmaku, contains('override fun onDetachedFromWindow()'));
    });
  });

  group('② 平滑收敛（消除「不同源」造成的左右跳）', () {
    test('大跳阈值常量存在', () {
      expect(danmaku, contains('private val SEEK_THRESHOLD_MS = 150L'));
    });

    test('小漂移吸收 10%、大跳直接重锚', () {
      expect(danmaku, contains('if (Math.abs(drift) > SEEK_THRESHOLD_MS) {'));
      expect(danmaku, contains('anchorPosMs = projected + drift / 10.0'));
      expect(danmaku, contains('val drift = positionMs - projected'));
    });

    test('注释记录「不同源」根因', () {
      expect(danmaku, contains('不同源'));
    });
  });

  group('③ 倍速与冻结语义（对齐宿主 positionAt）', () {
    test('位置按播放倍速推进（2x 不被误判成大跳）', () {
      expect(danmaku, contains('private var playRate = 1.0'));
      expect(
        danmaku,
        contains('(anchorPosMs + (frameElapsedMs() - anchorFrameMs) * playRate).toLong()'),
      );
      expect(
        danmaku,
        contains('anchorPosMs + (frameElapsedMs() - anchorFrameMs) * playRate'),
      );
    });

    test('setClock 接收倍速（第三参默认 1.0）', () {
      expect(danmaku, contains('fun setClock(positionMs: Long, paused: Boolean, speed: Double = 1.0)'));
      expect(danmaku, contains('this.playRate = if (speed > 0.0) speed else 1.0'));
    });

    test('暂停 / 缓冲 / 播完 三态合并传入（与 positionAt 冻结一致）', () {
      expect(
        kotlinScreen,
        contains('state.paused || state.buffering || state.ended'),
      );
      expect(kotlinScreen, contains('state.speed,'));
    });
  });

  group('④ 调用方传原始快照位置（不叠加宿主插值）', () {
    test('setClock 传 state.positionMs', () {
      expect(kotlinScreen, contains('state.positionMs.toLong(),'));
    });

    test('不再绑定 positionProvider', () {
      expect(kotlinScreen, isNot(contains('setPositionProvider')));
      expect(danmaku, isNot(contains('fun setPositionProvider')));
    });
  });

  group('④ Flutter 参考实现（语义基准）', () {
    test('_nowPosition = _lastPosition + (_elapsed - _alignElapsed)', () {
      expect(flutter, contains('_lastPosition + (_elapsed - _alignElapsed)'));
    });

    test('Ticker 逐帧驱动', () {
      expect(flutter, contains('createTicker'));
      expect(flutter, contains('_ticker.start()'));
    });
  });
}
