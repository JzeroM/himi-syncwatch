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

    test('2.3b DanmakuPanel 已注册进 CMake QML 清单（漏注 = 冒烟必红）', () {
      final cmake = File('native/windows_qt_player/CMakeLists.txt')
          .readAsStringSync();
      expect(cmake, contains('src/qml/DanmakuPanel.qml'));
      expect(
        cmake,
        contains(
          'DisplayAdjustPanel WindowResizeEdges DanmakuLayer DebugPanel\n'
          '             DanmakuPanel)',
        ),
      );
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

    test('3.4 空关键词 = 预填标题（TV 无输入法可直搜）', () {
      expect(screen, contains('_danmakuSearchKeyword() ?? '));
    });
  });

  group('4. Android TV Kotlin 壳', () {
    late String kotlinView;
    late String kotlinState;
    late String kotlinHost;

    setUpAll(() {
      const dir =
          'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer';
      kotlinView = File('$dir/NativePlayerScreenView.kt').readAsStringSync();
      kotlinState = File('$dir/AndroidNativePlayerState.kt').readAsStringSync();
      kotlinHost = File('$dir/AndroidNativePlayerHost.kt').readAsStringSync();
    });

    test('4.1 弹幕按钮点击弹窗（PANEL_DANMAKU，不再直接 toggle）', () {
      expect(kotlinView, contains('openPanel(PANEL_DANMAKU)'));
      expect(kotlinView, contains('PANEL_DANMAKU -> buildDanmakuContent()'));
      expect(kotlinView, contains('PANEL_DANMAKU -> "弹幕"'));
    });

    test('4.2 动效开关胶囊 + 搜索结果绑定 + 解除绑定', () {
      expect(kotlinView, contains('danmakuSwitchCapsule'));
      expect(kotlinView, contains('listener?.onSearchDanmaku("")'));
      expect(kotlinView, contains('listener?.onBindDanmaku(hit.episodeId)'));
      expect(kotlinView, contains('listener?.onUnbindDanmaku()'));
    });

    test('4.3 Listener 三回调 + Host 命令路由', () {
      expect(kotlinView, contains('fun onSearchDanmaku(keyword: String)'));
      expect(kotlinView, contains('fun onBindDanmaku(episodeId: Int)'));
      expect(kotlinView, contains('fun onUnbindDanmaku()'));
      expect(kotlinHost, contains('"type" to "searchDanmaku"'));
      expect(kotlinHost, contains('"type" to "bindDanmaku"'));
      expect(kotlinHost, contains('"type" to "unbindDanmaku"'));
    });

    test('4.4 状态解析四字段 + 搜索结果模型', () {
      expect(kotlinState, contains('data class DanmakuSearchHit('));
      expect(kotlinState, contains('optString("danmakuBinding"'));
      expect(kotlinState, contains('optJSONArray("danmakuSearchResults")'));
      expect(kotlinState, contains('optBoolean("danmakuSearching"'));
      expect(kotlinState, contains('optString("danmakuSearchError"'));
    });

    test('4.5 弹幕按钮图标随开关状态变色', () {
      expect(kotlinView, contains('0xFFFF8A3D.toInt() else Color.WHITE'));
    });
  });

  group('6. 鸿蒙 ArkTS 壳（M3e）', () {
    late String ohosHost;
    late String ohosPanel;
    late String ohosView;
    late String ohosPanelHost;

    setUpAll(() {
      const dir =
          'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native';
      ohosHost = File('$dir/HimiMpvNativeHost.ets').readAsStringSync();
      ohosPanel = File('$dir/DanmakuPanel.ets').readAsStringSync();
      ohosView = File('$dir/HimiNativePlayerView.ets').readAsStringSync();
      ohosPanelHost = File('$dir/NativePlayerPanel.ets').readAsStringSync();
    });

    test('6.1 弹幕按钮点击弹窗（不再直接 toggle）', () {
      expect(ohosView, contains('this.openPanel(NativePlayerPanelType.danmaku)'));
      expect(
        ohosView,
        isNot(contains(
            'HimiMpvNativeHost.getInstance().optimisticToggleDanmaku();')),
        reason: '按钮 onClick 已改弹窗；toggle 在弹窗开关行',
      );
      // 开关行仍走 optimisticToggleDanmaku（弹窗内）
      expect(ohosPanel, contains('optimisticToggleDanmaku'));
    });

    test('6.2 面板类型 + 分发 + 标题', () {
      expect(ohosHost, contains("static readonly danmaku: string = 'danmaku';"));
      expect(ohosPanelHost, contains("this.panelType === 'danmaku'"));
      expect(ohosPanelHost, contains('DanmakuPanelContent({ revision: this.revision })'));
      expect(ohosPanelHost, contains("return '弹幕';"));
    });

    test('6.3 动效开关 + 搜索结果绑定 + 解除绑定', () {
      expect(ohosPanel, contains('SwitchCapsule'));
      expect(ohosPanel, contains('.animation({ duration: 180'));
      expect(ohosPanel, contains("this.host.searchDanmaku('')"));
      expect(ohosPanel, contains('this.host.bindDanmaku(hit.episodeId)'));
      expect(ohosPanel, contains('this.host.unbindDanmaku()'));
    });

    test('6.4 状态解析四字段 + 搜索结果模型', () {
      expect(ohosHost, contains('class NativeDanmakuSearchHitUi'));
      expect(ohosHost, contains('parseDanmakuSearchResults'));
      expect(ohosHost, contains("jsonStr(obj.danmakuBinding"));
      expect(ohosHost, contains('obj.danmakuSearchResults !== undefined'));
      expect(ohosHost, contains('jsonBool(obj.danmakuSearching'));
      expect(ohosHost, contains('jsonStr(obj.danmakuSearchError'));
    });

    test('6.5 命令封装 + 图标随状态变色', () {
      expect(ohosHost, contains("this.sendCommand('searchDanmaku', fields)"));
      expect(ohosHost, contains("this.sendCommand('bindDanmaku', fields)"));
      expect(ohosHost, contains("this.sendCommand('unbindDanmaku', null)"));
      expect(ohosView, contains('DANMAKU_ICON_TINT'));
      expect(ohosView, contains('activeColor: string = SEL_COLOR'));
    });
  });

  group('7. 结果可滚动 + 面板不盖进度条（694 反馈修正）', () {
    test('7.1 Flutter 弹卡抬升控制条之上 + 限高滚动', () {
      final sheet = File('lib/screens/player/danmaku_control_sheet.dart')
          .readAsStringSync();
      expect(sheet, contains('bottom: bottomReserve'));
      expect(sheet, contains('SingleChildScrollView'));
      expect(sheet, contains('maxHeight: MediaQuery.sizeOf(context).height * 0.6'));
    });

    test('7.2 Qt 面板高度钳制（panelBottomOffset）+ 结果 ScrollView', () {
      final panel =
          File('native/windows_qt_player/src/qml/DanmakuPanel.qml')
              .readAsStringSync();
      expect(panel, contains('Theme.panelBottomOffset'));
      expect(panel, contains('height: Math.min(implicitHeight, maxPanelHeight)'));
      expect(panel, contains('ScrollView {'));
    });

    test('7.3 鸿蒙内容 Scroll + layoutWeight（侧栏容器下避进度条）', () {
      final panel = File(
              'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/DanmakuPanel.ets')
          .readAsStringSync();
      expect(panel, contains('Scroll()'));
      expect(panel, contains('.layoutWeight(1)'));
      expect(panel, contains('ScrollDirection.Vertical'));
    });

    test('7.4 安卓 TV 已有 scrollWrap + PANEL_BOTTOM_OFFSET 避让', () {
      final kotlin = File(
              'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerScreenView.kt')
          .readAsStringSync();
      expect(kotlin, contains('panelContainer.addView(scrollWrap(list))'));
      expect(
        kotlin,
        contains('dp(NPTheme.PANEL_BOTTOM_OFFSET) + safeBottomPx()'),
      );
    });
  });

  group('8. 即时刷新 + 搜索输入框（694 真机反馈修正）', () {
    late String kotlinView;
    late String ohosPanel;
    late String ohosHost;
    late String sheet;

    setUpAll(() {
      kotlinView = File(
              'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerScreenView.kt')
          .readAsStringSync();
      ohosPanel = File(
              'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/DanmakuPanel.ets')
          .readAsStringSync();
      ohosHost = File(
              'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/HimiMpvNativeHost.ets')
          .readAsStringSync();
      sheet = File('lib/screens/player/danmaku_control_sheet.dart')
          .readAsStringSync();
    });

    test('8.1 安卓：overlayContentSig 含弹幕字段（开关/结果即时重建）', () {
      expect(kotlinView, contains(r'${lastState.danmakuEnabled}|'));
      expect(kotlinView, contains('lastState.danmakuSearchResults.joinToString'));
      expect(kotlinView, contains('danmakuKeywordDraft'));
    });

    test('8.2 安卓：搜索输入框（EditText + 搜索按钮）', () {
      expect(kotlinView, contains('EditText(context)'));
      expect(kotlinView, contains('listener?.onSearchDanmaku(keywordInput.text.toString())'));
      expect(kotlinView, contains('import android.widget.EditText'));
    });

    test('8.3 鸿蒙：自驱签名 → epoch/ForEach 重建（revision 不可靠教训）', () {
      expect(ohosPanel, contains('this.epoch = this.epoch + 1'));
      expect(ohosPanel, contains(r'`dm-panel-${e}`'));
      expect(ohosPanel, contains('setInterval'));
      // 关键词不进签名（打字不得触发重建）
      final sigFn = ohosPanel.substring(
        ohosPanel.indexOf('private stateSig'),
        ohosPanel.indexOf('private state()'),
      );
      expect(sigFn, isNot(contains('this.keyword')));
    });

    test('8.4 鸿蒙：TextInput 输入框 + 草稿保持', () {
      expect(ohosPanel, contains('TextInput({ text: this.keyword'));
      expect(ohosPanel, contains('this.host.searchDanmaku(this.keyword)'));
      expect(ohosPanel, contains('@State keyword: string'));
    });

    test('8.5 Dart 推送预填关键词（原生输入框用）', () {
      expect(screen, contains("danmakuSearchKeyword: _danmakuSearchKeyword() ?? ''"));
      expect(ohosHost, contains('jsonStr(obj.danmakuSearchKeyword'));
    });

    test('8.6 Flutter 壳无此病（锁定回归）', () {
      // 输入框 + revision 驱动即时重建 + 开关 setState 翻转
      expect(sheet, contains('TextField('));
      expect(sheet, contains('ListenableBuilder('));
      expect(sheet, contains('controller.revision'));
      expect(sheet, contains('setState(() => _on = !_on)'));
    });
  });

  group('5. 设置页绑定管理区块', () {
    test('5.1 「已保存的弹幕绑定」列表 + 删除 + 全部清除', () {
      final config = File('lib/screens/settings/danmaku_config_screen.dart')
          .readAsStringSync();
      expect(config, contains('已保存的弹幕绑定'));
      expect(config, contains('DanmakuCaches.matchMemory.all()'));
      expect(config, contains("remove(itemKey: entry.key, nameKey: entry.key)"));
      expect(config, contains('DanmakuCaches.matchMemory.clear()'));
      expect(config, contains('手动绑定'));
    });
  });
}
