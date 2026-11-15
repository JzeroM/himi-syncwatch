import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 694 M3b：Windows Qt 弹幕弹窗接线（源码断言）。
///
/// 覆盖：DanmakuPanel.qml 动效开关/搜索态、Overlay 接线、命令路由、
/// PlayerState 新字段。QML 渲染正确性由 CI「QML 冒烟自检」把关。
void main() {
  late String panel;
  late String overlay;
  late String bottomBar;
  late String stateH;
  late String stateCpp;
  late String commands;
  late String screen;

  setUpAll(() {
    panel = File('native/windows_qt_player/src/qml/DanmakuPanel.qml')
        .readAsStringSync();
    overlay =
        File('native/windows_qt_player/src/qml/Overlay.qml').readAsStringSync();
    bottomBar = File('native/windows_qt_player/src/qml/BottomBar.qml')
        .readAsStringSync();
    stateH = File('native/windows_qt_player/src/player_state.h')
        .readAsStringSync();
    stateCpp = File('native/windows_qt_player/src/player_state.cpp')
        .readAsStringSync();
    commands = File('lib/services/player/native/native_player_command.dart')
        .readAsStringSync();
    screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  });

  group('1. DanmakuPanel.qml（弹窗本体）', () {
    test('1.1 动效开关（滑轨 + 缓动滑钮 + 180ms）', () {
      expect(panel, contains('id: track'));
      expect(panel, contains('id: knob'));
      expect(panel, contains('duration: 180'));
      expect(panel, contains('Easing.OutBack'));
      expect(panel, contains('toggleRequested'));
    });

    test('1.2 搜索态（关键词输入 + 结果绑定 + 返回）', () {
      expect(panel, contains('TextField {'));
      expect(panel, contains('openSearch'));
      expect(panel, contains('searchRequested(keywordField.text)'));
      expect(panel, contains('bindRequested(modelData.episodeId)'));
      expect(panel, contains('unbindRequested'));
    });

    test('1.3 属性名不遮蔽全局单例（stateRef，防 Binding loop）', () {
      expect(panel, contains('property var stateRef: null'));
      expect(panel, isNot(contains('property var playerState')));
    });

    test('1.4 字号全部取整/用 Theme 常量（QML 只吃整数）', () {
      // 算出的字号必须 Math.round 且声明 int
      expect(panel, contains('readonly property int glyphSize: Math.round'));
      expect(panel, contains('readonly property int subSize:'));
      // 不得出现小数字号字面量
      expect(RegExp(r'font\.pixelSize:\s*\d+\.\d+').hasMatch(panel), isFalse);
    });
  });

  group('2. Overlay / BottomBar 接线', () {
    test('2.1 点击弹幕按钮弹窗（不再直接 toggle）', () {
      expect(overlay, contains('onDanmakuClicked: root.openDanmakuPanel()'));
      expect(overlay, contains('property bool danmakuPanelOpen: false'));
      expect(overlay, contains('danmakuPanelOpen = false')); // closePanels
    });

    test('2.2 弹窗命令接线（search/bind/unbind/toggle）', () {
      expect(overlay, contains('"type": "searchDanmaku"'));
      expect(overlay, contains('"type": "bindDanmaku"'));
      expect(overlay, contains('"type": "unbindDanmaku"'));
      expect(overlay, contains('onToggleRequested:'));
    });

    test('2.3 手势层识别弹幕弹窗（panelsOpen 含 danmakuPanelOpen）', () {
      expect(overlay, contains('|| root.danmakuPanelOpen'));
    });

    test('2.4 按钮图标随开关状态变色', () {
      expect(bottomBar, contains('iconColor: playerState.danmakuEnabled'));
      expect(bottomBar, contains('"#FF8A3D"'));
    });
  });

  group('3. 状态与命令管道', () {
    test('3.1 PlayerState 四字段 + 搜索结果解析', () {
      expect(stateH, contains('Q_PROPERTY(QString danmakuBinding'));
      expect(stateH, contains('Q_PROPERTY(QVariantList danmakuSearchResults'));
      expect(stateH, contains('Q_PROPERTY(bool danmakuSearching'));
      expect(stateH, contains('Q_PROPERTY(QString danmakuSearchError'));
      expect(stateCpp, contains('setDanmakuSearchResults'));
      expect(stateCpp, contains('readString(json, "danmakuBinding"'));
    });

    test('3.2 命令解析（searchDanmaku/bindDanmaku/unbindDanmaku）', () {
      expect(commands, contains("case 'searchDanmaku':"));
      expect(commands, contains("case 'bindDanmaku':"));
      expect(commands, contains("case 'unbindDanmaku':"));
    });

    test('3.3 Dart 侧处理并推送状态快照', () {
      expect(screen, contains('_searchDanmakuFromPanel'));
      expect(screen, contains('_bindDanmakuFromPanel'));
      expect(screen, contains('_unbindDanmakuFromPanel'));
      expect(screen, contains('danmakuBinding: _dmBindingLabel'));
      expect(screen, contains('danmakuSearchResults: _dmSearchResults'));
    });
  });
}
