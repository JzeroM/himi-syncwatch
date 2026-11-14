import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：Windows Qt 播放调试信息（`DebugPanel.qml` 纯文字叠加）。
///
/// ## 为什么从「浮层面板」改成「文字叠加」
///
/// 真机回归：浮层把 `height` 绑定到 `contentColumn.implicitHeight`，而
/// 指标定时刷新、某些行（如「P5 风险」）会随数据出现/消失 → 行数变化
/// → 面板高度跳变 → 透明叠加窗每秒重绘 → 与 mpv 的 D3D11 交换链合成
/// 冲突 → **视频画面每秒闪一下**。
///
/// 用户实测「不打开面板就不闪」，直接证实这条链路。
///
/// 所以本测试的核心不是「面板长什么样」，而是**防闪烁的结构约束**：
/// 不得存在任何「内容高度 → 容器高度 → 窗口几何」的绑定链。
///
/// ## 数据来源的特殊性
///
/// Windows 与其他三端不同：mpv 跑在独立进程，Dart 的 `_player` 是空闲
/// 引擎 → 属性读出来恒为空。数据只能由 Qt 侧 `MpvWindow::debugText()`
/// 自己读。这是必要差异，测试要锁住它（不能有人「优化」回 Dart 下发）。
void main() {
  const dir = 'native/windows_qt_player';
  String read(String p) => File(p).readAsStringSync();

  late String panelQml;
  late String overlayQml;
  late String cmake;
  late String stateH;
  late String stateCpp;
  late String mpvH;
  late String mpvCpp;
  late String mainCpp;
  late String sessionDart;
  late String playerScreen;

  setUpAll(() {
    panelQml = read('$dir/src/qml/DebugPanel.qml');
    overlayQml = read('$dir/src/qml/Overlay.qml');
    cmake = read('$dir/CMakeLists.txt');
    stateH = read('$dir/src/player_state.h').replaceAll(RegExp(r'\s+'), ' ');
    stateCpp = read('$dir/src/player_state.cpp');
    mpvH = read('$dir/src/mpv_window.h');
    mpvCpp = read('$dir/src/mpv_window.cpp');
    mainCpp = read('$dir/src/main.cpp');
    sessionDart = read('lib/services/player/qt_player_session.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
  });

  group('1. 防闪烁：不得有内容高度 → 窗口几何的绑定链', () {
    test('1.1 不得把容器 height 绑到内容 implicitHeight', () {
      // 这是真机「每秒闪一下」的直接原因
      expect(
        RegExp(r'height:\s*Math\.min\([^)]*implicitHeight')
            .hasMatch(panelQml),
        isFalse,
        reason: 'height 绑 implicitHeight 会让窗口每秒跳变',
      );
      expect(
        RegExp(r'height:\s*[a-zA-Z]+Column\.implicitHeight')
            .hasMatch(panelQml),
        isFalse,
      );
    });

    test('1.2 不得有半透明背景矩形（合成层越简单越不闪）', () {
      // 旧实现：color: Qt.rgba(0, 0, 0, 0.72) + radius + border
      expect(panelQml, isNot(contains('Qt.rgba(0, 0, 0, 0.72)')));
      expect(panelQml, isNot(contains('border.width')));
      expect(panelQml, isNot(contains('radius:')));
      // 根节点是 Column（无背景属性），不是 Rectangle
      expect(panelQml, contains('Column {'));
      expect(panelQml, isNot(contains('Rectangle {')));
    });

    test('1.3 不得有分组折叠（折叠会改变行数 → 几何变化）', () {
      expect(panelQml, isNot(contains('collapsedMap')));
      expect(panelQml, isNot(contains('toggleRequested')));
    });

    test('1.4 不得用 Flickable/ScrollView（滚动区需要固定高度）', () {
      expect(panelQml, isNot(contains('Flickable')));
      expect(panelQml, isNot(contains('ScrollView')));
    });

    test('1.5 文字用 Outline 描边保证可读（不依赖底色）', () {
      expect(panelQml, contains('style: Text.Outline'));
      expect(panelQml, contains('styleColor'));
    });

    test('1.5b 旧的浮层子组件已删除', () {
      // DebugRow / DebugGroupHeader 只为浮层面板存在，文字叠加不再需要
      expect(
        File('$dir/src/qml/DebugRow.qml').existsSync(),
        isFalse,
        reason: 'DebugRow.qml 应随浮层一起删除',
      );
      expect(
        File('$dir/src/qml/DebugGroupHeader.qml').existsSync(),
        isFalse,
      );
      expect(cmake, isNot(contains('DebugRow')));
      expect(cmake, isNot(contains('DebugGroupHeader')));
    });

    test('1.6 锚定左上角（固定位置，不参与几何计算）', () {
      expect(panelQml, contains('anchors.left: parent.left'));
      expect(panelQml, contains('anchors.top: parent.top'));
      expect(panelQml, contains('anchors.leftMargin: 16'));
      expect(panelQml, contains('anchors.topMargin: 56'));
    });
  });

  group('2. 数据由 Qt 自己读 mpv', () {
    test('2.1 MpvWindow 提供 debugText()', () {
      expect(mpvH, contains('QString debugText()'));
      expect(mpvCpp, contains('QString MpvWindow::debugText()'));
    });

    test('2.2 提供标量属性读取封装', () {
      expect(mpvH, contains('QString readMpvString(const char* name)'));
      expect(mpvH, contains('int readMpvInt(const char* name)'));
      expect(mpvH, contains('double readMpvDouble(const char* name)'));
      expect(mpvCpp, contains('mpv_get_property(mpv_, name, MPV_FORMAT_STRING'));
      expect(mpvCpp, contains('mpv_get_property(mpv_, name, MPV_FORMAT_INT64'));
      expect(mpvCpp, contains('mpv_get_property(mpv_, name, MPV_FORMAT_DOUBLE'));
    });

    test('2.3 字段名必须是 mpv 真实存在的路径', () {
      // DV 在 current-tracks/video 下（不在 video-params）
      expect(mpvCpp,
          contains('current-tracks/video/dolby-vision-profile'));
      expect(mpvCpp, contains('current-tracks/video/dolby-vision-level'));
      // 色彩走 video-params 子属性
      expect(mpvCpp, contains('video-params/primaries'));
      expect(mpvCpp, contains('video-params/gamma'));
      expect(mpvCpp, contains('video-params/sig-peak'));
      // 绝不能用不存在的 video-params/dovi-*
      expect(mpvCpp, isNot(contains('video-params/dovi')));
    });

    test('2.4 sig-peak 必须 ×100 换算成 nits', () {
      // mpv 的 sig-peak 是 max_luma/100 的倍数
      expect(mpvCpp, contains('sigPeak * 100.0'));
    });

    test('2.5 DV 读不到时回退 Emby 元数据', () {
      expect(mpvCpp, contains('dvContent_'));
      expect(mpvCpp, contains('Emby 元数据'));
    });

    test('2.6 定时器驱动且受 showDebug 门控', () {
      expect(mainCpp, contains('debugTimer'));
      expect(mainCpp, contains('state.showDebug()'));
      expect(mainCpp, contains('state.setDebugText(mpv.debugText())'));
      // 2s 一次（不是每帧）
      expect(mainCpp, contains('setInterval(2000)'));
    });

    test('2.7 player_state 暴露 debugText 且用独立信号', () {
      expect(stateH, contains('Q_PROPERTY(QString debugText READ debugText'));
      // 【必须独立信号】复用 changed 会让所有绑定每秒全量重算
      expect(stateH, contains('NOTIFY debugTextChanged'));
      expect(stateH, contains('void debugTextChanged();'));
      expect(stateCpp, contains('emit debugTextChanged();'));
    });
  });

  group('3. Dart 侧不再下发 Qt 调试数据', () {
    test('3.1 会话里没有调试采集链路', () {
      expect(sessionDart, isNot(contains('collectDebugMetrics')));
      expect(sessionDart, isNot(contains('isDebugEnabled')));
      expect(sessionDart, isNot(contains('_debugTimer')));
      expect(sessionDart, isNot(contains('_startDebugTicker')));
    });

    test('3.2 播放页没有 Qt 调试补丁', () {
      expect(playerScreen, isNot(contains('_collectQtDebugMetrics')));
    });

    test('3.3 保留 Flutter 面板自己的采集器（手机端仍用）', () {
      expect(playerScreen, contains('_debugMetricsCollector'));
    });
  });

  group('4. 面板挂载与构建注册', () {
    test('4.1 DebugPanel 仍注册在 CMake', () {
      expect(cmake, contains('src/qml/DebugPanel.qml'));
      expect(cmake, contains('DebugPanel'));
    });

    test('4.2 Overlay 里绑定 showDebug', () {
      expect(overlayQml, contains('DebugPanel {'));
      expect(overlayQml, contains('shown: playerState.showDebug'));
    });

    test('4.3 锁定态隐藏', () {
      expect(panelQml, contains('!playerState.locked'));
    });

    test('4.4 关闭按钮不破坏 shown 绑定', () {
      expect(panelQml, contains('root.dismissed = true'));
      expect(panelQml, isNot(contains('root.shown = false')));
      expect(panelQml, contains('if (shown) dismissed = false'));
    });
  });

  group('5. SDR 分支不残留 HDR 属性', () {
    test('5.1 applyHdrOptions 的 SDR 分支显式复位', () {
      // mpv 属性是持久的：只重置 d3d11-output-format 会残留
      // target-prim/trc/tone-mapping，导致面板与实际渲染不一致。
      final idx = mpvCpp.indexOf('void MpvWindow::applyHdrOptions');
      expect(idx, greaterThan(0));
      final block = mpvCpp.substring(idx, idx + 2200);
      final elseIdx = block.indexOf('} else {');
      expect(elseIdx, greaterThan(0), reason: 'SDR 分支缺失');
      final sdrBlock = block.substring(elseIdx, elseIdx + 900);
      expect(sdrBlock, contains('"target-prim", QStringLiteral("auto")'));
      expect(sdrBlock, contains('"target-trc", QStringLiteral("auto")'));
      expect(sdrBlock, contains('"tone-mapping"'));
    });
  });
}
