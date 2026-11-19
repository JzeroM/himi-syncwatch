import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_clock.dart';

/// 弹幕时钟四端同构（P1）：数据结构与阈值必须一致。
///
/// 真机症状：全平台 MPV 弹幕「跳跃抖动」——
///
/// - Windows 直接吃 mpv 原始 `time-pos`（**完全没有插值**）→ 一段一段蹦；
/// - Flutter 投影**没乘播放速率** → 非 1x 时每 500ms 被拽一次；
/// - 安卓/鸿蒙用**墙钟**（`currentTimeMillis` / `Date.now`）→ NTP 校时会跳；
/// - 四端都快照硬重锚 → IPC 抖动直接变成位移跳变。
///
/// 本文件锁死修复后的四条不变量：
/// 1. 单调时钟（不用墙钟）；
/// 2. 死区 40ms / 硬对齐 400ms / 收敛 ±5%；
/// 3. 换速率前先重锚（否则位置瞬移）；
/// 4. Windows 必须走 PlayerState 的插值属性，而不是玩家原始位置。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String overlay;
  late String android;
  late String ohosHost;
  late String ohosLayer;
  late String winStateH;
  late String winStateCpp;
  late String winQml;
  late String overlayQml;

  setUpAll(() {
    overlay = read('lib/screens/player/widgets/danmaku_overlay.dart');
    android = read('android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'DanmakuLayerView.kt');
    ohosHost = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/HimiMpvNativeHost.ets');
    ohosLayer = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/DanmakuLayer.ets');
    winStateH = read('native/windows_qt_player/src/player_state.h');
    winStateCpp = read('native/windows_qt_player/src/player_state.cpp');
    winQml = read('native/windows_qt_player/src/qml/DanmakuLayer.qml');
    overlayQml = read('native/windows_qt_player/src/qml/Overlay.qml');
  });

  group('1. 共享实现与阈值', () {
    test('1.1 阈值常量固定（四端必须抄同一组）', () {
      expect(DanmakuClock.deadbandMs, 40);
      expect(DanmakuClock.hardResyncMs, 400);
      expect(DanmakuClock.convergeMs, 600);
      expect(DanmakuClock.maxRateAdjust, 0.05);
    });
  });

  group('2. Flutter：用 DanmakuClock + 播放速率', () {
    test('2.1 引入时钟并投影', () {
      expect(overlay, contains('DanmakuClock'));
      expect(overlay, contains('_clock.positionAt('));
    });

    test('2.2 投影必须带 playbackRate（非 1x 不再被拽）', () {
      expect(overlay, contains('playbackRate'));
      expect(overlay, contains('baseRate: widget.playbackRate'));
    });

    test('2.3 播放页把播放速率传进来', () {
      final screen = read('lib/screens/player/player_screen.dart');
      expect(screen, contains('playbackRate: _speed'));
    });
  });

  group('3. 安卓：单调时钟 + 死区 + 收敛', () {
    test('3.1 用 elapsedRealtimeNanos，且弹幕路径不再用墙钟', () {
      expect(android, contains('SystemClock.elapsedRealtimeNanos()'));
      expect(
        android,
        isNot(contains('snapAtMs = System.currentTimeMillis()')),
        reason: '旧的墙钟锚点必须消失',
      );
    });

    test('3.2 阈值与收敛参数齐全', () {
      expect(android, contains('DEADBAND_MS = 40L'));
      expect(android, contains('HARD_RESYNC_MS = 400L'));
      expect(android, contains('MAX_RATE_ADJUST = 0.05'));
    });

    test('3.3 换速率前必须重锚（防瞬移）', () {
      expect(android, contains('rebaseAnchor()'));
      expect(android, contains('hardResync('));
    });
  });

  group('4. 鸿蒙：独立弹幕时钟', () {
    test('4.1 宿主提供 danmakuPositionNowMs', () {
      expect(ohosHost, contains('danmakuPositionNowMs(): number'));
      expect(ohosHost, contains('danmakuClockSync(): void'));
      expect(ohosHost, contains('danmakuClockHardResync('));
    });

    test('4.2 阈值同构', () {
      expect(ohosHost, contains('DM_DEADBAND_MS: number = 40'));
      expect(ohosHost, contains('DM_HARD_RESYNC_MS: number = 400'));
      expect(ohosHost, contains('DM_MAX_ADJUST: number = 0.05'));
    });

    test('4.3 弹幕层读专用时钟（不是进度条时钟）', () {
      expect(ohosLayer, contains('danmakuPositionNowMs()'));
      // 注意 `danmakuPositionNowMs()` 本身包含 `positionNowMs()` 子串，
      // 这里断言的是「不再直接调用进度条那个方法」。
      expect(ohosLayer, isNot(contains('.positionNowMs()')),
          reason: '弹幕层不应再复用进度条插值');
    });
  });

  group('5. Windows：C++ 插值属性', () {
    test('5.1 PlayerState 暴露 danmakuPositionMs', () {
      expect(winStateH, contains('Q_PROPERTY(qint64 danmakuPositionMs'));
      expect(winStateH, contains('qint64 danmakuPositionMs() const'));
    });

    test('5.2 单调时钟 + 阈值', () {
      expect(winStateH, contains('QElapsedTimer'));
      expect(winStateCpp, contains('dmAnchorTimer_.nsecsElapsed()'));
      expect(winStateCpp, contains('err > 400 || err < -400'));
      // 695：死区 40→80 + 软同步节流（减推进抖动「跑一秒停顿一下」）
      expect(winStateCpp, contains('err > 80 || err < -80'));
      expect(winStateCpp, contains('dmSoftSyncTimer_'));
      expect(winStateCpp, contains('0.05'));
    });

    test('5.3 QML 读插值位置而不是原始 positionMs', () {
      expect(winQml, contains('danmakuPositionMs'));
      expect(winQml, contains('function currentPos()'));
      expect(winQml, contains('var pos = currentPos()'));
      expect(overlayQml, contains('playerState: playerState'));
    });
  });
}
