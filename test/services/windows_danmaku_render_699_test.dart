import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 699：Windows 弹幕「面板有在屏数、画面里一条都没有」。
///
/// ## 两个独立根因
///
/// **1. `font.pixelSize` 收到非整数（主因）**
///
/// QML 的 `font.pixelSize` 是 **int** 属性。`fontSize = 25 × 0.5 = 12.5`
/// 会报 `Invalid property assignment: int expected`。放在 `Repeater`
/// delegate 里时**不会崩整个 Overlay**（所以控件/面板都正常），而是该
/// delegate 创建失败 → 文字不出现。这与「只有弹幕不显示」完全吻合。
///
/// 交叉验证：该文件里其他所有 QML 字号都是整数（Theme 里 12/24/9/18），
/// 只有弹幕这一处是算出来的小数。
///
/// **2. Qt 侧弹幕时钟可能永久冻结**
///
/// - `dmAnchorTimer_` 声明后从未 `start()`；未启动的 `QElapsedTimer`
///   调 `nsecsElapsed()` 是未定义行为；
/// - `buffering_` 被算进「暂停」→ 缓冲期间 `dmPaused_` 恒 true →
///   位置冻在锚点 → 时间窗全被判「超前过多」丢弃 → 一条都不画。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String qml;
  late String stateH;
  late String stateCpp;
  late String mainCpp;

  setUpAll(() {
    qml = read('native/windows_qt_player/src/qml/DanmakuLayer.qml');
    stateH = read('native/windows_qt_player/src/player_state.h');
    stateCpp = read('native/windows_qt_player/src/player_state.cpp');
    mainCpp = read('native/windows_qt_player/src/main.cpp');
  });

  group('1. font.pixelSize 必须是整数', () {
    test('1.1 fontSize 显式取整', () {
      expect(
        qml,
        contains('Math.round(baseFontSize * fontSizeScale)'),
        reason: '25 × 0.5 = 12.5，不取整会让 delegate 创建失败',
      );
    });

    test('1.2 不再把小数直接喂给 pixelSize', () {
      // 声明类型也必须是 int（real 会让 QML 认为可能收到小数）
      expect(qml, contains('readonly property int fontSize: Math.round('));
      expect(qml, isNot(contains('readonly property real fontSize:')));
    });

    test('1.3 注释记录真机症状（防后人改回去）', () {
      expect(qml, contains('Invalid property assignment: int expected'));
      expect(qml, contains('在屏'));
    });
  });

  group('2. Qt 侧弹幕时钟健壮性', () {
    test('2.1 构造即启动单调计时器', () {
      expect(stateCpp, contains('dmAnchorTimer_.start();'));
      expect(stateCpp, contains('PlayerState::PlayerState(QObject* parent)'));
    });

    test('2.2 nsecsElapsed 前判 isValid', () {
      expect(stateCpp, contains('if (!dmAnchorTimer_.isValid()) return dmAnchorPosMs_;'));
    });

    test('2.3 buffering 不算暂停（位置仍在推进）', () {
      // hardResync 与 sync 两处都不能再出现 `buffering_ ||`
      final hits = RegExp(r'paused_ \|\| buffering_').allMatches(stateCpp).length;
      expect(hits, 0, reason: 'buffering 会把弹幕时钟冻死 → 时间窗全丢弃');
      expect(stateCpp, contains('paused_ || speed_ <= 0.0'));
    });
  });

  group('2.5 属性名不能遮蔽全局单例', () {
    test('2.5.1 DanmakuLayer 用 stateRef 而不是 playerState', () {
      // playerState 是 qmlRegisterSingletonInstance 注册的全局单例；
      // 同名属性会遮蔽它 → `playerState: playerState` 自赋值 → Binding loop
      // → 读到 null → 时钟恒 0 → 一条都不画（699 真机）。
      expect(qml, contains('property var stateRef: null'));
      expect(qml, isNot(contains('property var playerState')));
      expect(qml, contains('stateRef.danmakuPositionMs'));
    });

    test('2.5.2 Overlay 传 stateRef 而不是 playerState', () {
      final overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay, contains('stateRef: playerState'));
      expect(overlay, isNot(contains('        playerState: playerState')));
    });
  });

  group('2.8 弹幕窗口必须跟随播放位置重算', () {
    test('2.8.1 Windows Qt 分支在 500ms 位置节拍里重推（轻量路径）', () {
      // Qt 模式没有安卓/鸿蒙那条 200ms 原生 UI 轮询（_pushNativeUiState
      // 只服务同进程宿主）。此前只在事件时调用 → 弹幕时间窗冻结在首次
      // 推送位置 → 在屏恒 0（699 真机）。
      //
      // 用**轻量** `_pushQtDanmakuTick()` 而不是完整 `_syncNativePanelData()`：
      // 后者每次会重建整份剧集列表（List.generate，长剧集上千对象），
      // 500ms 一次是纯 GC 压力。
      final screen = read('lib/screens/player/player_screen.dart');
      final idx = screen.indexOf('_evaluateSkipPrompt(pos);');
      expect(idx, greaterThan(0));
      final after = screen.substring(idx, idx + 1200);
      expect(after, contains('_pushQtDanmakuTick();'));
      expect(after, contains('TargetPlatform.windows'));
      expect(after, contains('activeQtAdapter != null'));
      // 轻量路径只推弹幕相关字段
      expect(screen, contains('void _pushQtDanmakuTick()'));
      expect(screen, contains('buildDanmakuWindowFor(posMs)'));
      expect(screen, contains("'danmakuOnscreen': stats.onscreen"));
    });

    test('2.8.1b 窗口变空也要推（否则 Qt 残留旧弹幕）', () {
      final screen = read('lib/screens/player/player_screen.dart');
      // 不能按「window.isEmpty」提前 return —— 必须按内容签名去重。
      expect(screen, contains('_lastQtDanmakuSig'));
      expect(screen, contains("if (sig == _lastQtDanmakuSig) return;"));
      expect(
        screen,
        isNot(contains('if (window.isEmpty && mpv.danmakuStats.onscreen == 0)')),
        reason: '按空提前返回会让关弹幕/全过期时残留旧节点',
      );
    });

    test('2.8.2 Qt 侧 setDanmakuItems 有内容相等短路（不白刷 QML）', () {
      final cpp = read('native/windows_qt_player/src/player_state.cpp');
      final idx = cpp.indexOf('void PlayerState::setDanmakuItems');
      expect(idx, greaterThan(0));
      final body = cpp.substring(idx, idx + 1200);
      expect(body, contains('if (same) return;'));
    });
  });

  group('3. 面板可观测', () {
    test('3.1 调试面板显示 Qt 侧弹幕时钟实际值', () {
      expect(mainCpp, contains('时钟 %3ms'));
      expect(mainCpp, contains('state.danmakuPositionMs()'));
    });

    test('3.2 PlayerState 暴露 danmakuPositionMs 属性', () {
      expect(stateH, contains('Q_PROPERTY(qint64 danmakuPositionMs'));
    });
  });
}
