import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// P4：弹幕实时统计（总条数 / 在屏 / 屏蔽 / 采样丢弃）。
///
/// 数值在**适配器构建弹幕窗口时顺带算出**（同一次遍历，零额外成本），
/// 经 `NativePlayerState` 下发到四端面板。
///
/// 用途：
/// - 「在屏」异常高（>200）说明同屏上限没生效 → 卡顿；
/// - 「已屏蔽」与用户设置不符 → 屏蔽链没生效（588 真机回归过）；
/// - 「采样丢弃」>0 说明触发了数量上限采样。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String adapter;
  late String state;
  late String collector;
  late String ktState;
  late String ktPanel;
  late String ohosHost;
  late String ohosPanel;
  late String winStateH;
  late String winMain;

  setUpAll(() {
    adapter = read('lib/services/player/mpv_player_adapter.dart');
    state = read('lib/services/player/native/native_player_state.dart');
    collector = read('lib/services/debug/debug_metrics_collector.dart');
    ktState = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/AndroidNativePlayerState.kt');
    ktPanel = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/DebugPanelView.kt');
    ohosHost = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/HimiMpvNativeHost.ets');
    ohosPanel = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/DebugPanel.ets');
    winStateH = read('native/windows_qt_player/src/player_state.h');
    winMain = read('native/windows_qt_player/src/main.cpp');
  });

  group('1. 采集（适配器侧）', () {
    test('1.1 在构建弹幕窗口时统计，不额外遍历全量', () {
      expect(adapter, contains('_dmTotal = _nativeDanmakuComments.length'));
      expect(adapter, contains('_dmOnscreen++'));
      // 698：采样上限整体移除（设置页删了「限制同屏数量」），
      // `_dmSampled` 恒 0，但仍保留字段供面板兼容旧快照。
      expect(adapter, isNot(contains('_dmSampled = comments.length - maxCount')));
    });

    test('1.2 屏蔽数与屏蔽规则同源（顶/底/关键词）', () {
      expect(adapter, contains('_dmBlocked = _dmTotal - unblocked'));
      expect(adapter, contains('danmakuBlockTop && c.mode == DanmakuMode.top'));
      expect(adapter, contains('c.text.contains(w)'));
    });

    test('1.3 暴露只读统计给面板', () {
      expect(adapter, contains('({int total, int blocked, int sampled, int onscreen}) get danmakuStats'));
    });
  });

  group('2. 下发（NativePlayerState）', () {
    test('2.1 四个字段 + JSON 往返', () {
      for (final f in ['danmakuTotal', 'danmakuBlocked', 'danmakuSampled', 'danmakuOnscreen']) {
        expect(state, contains('final int $f;'), reason: '缺字段 $f');
        expect(state, contains("'$f': $f"), reason: '缺 toJson $f');
        expect(state, contains("json['$f']"), reason: '缺 fromJson $f');
      }
    });

    test('2.2 适配器把统计写进状态', () {
      expect(adapter, contains('danmakuTotal: _dmTotal'));
      expect(adapter, contains('danmakuOnscreen: _dmOnscreen'));
    });
  });

  group('3. 四端面板', () {
    test('3.1 Flutter 面板有「弹幕」分组', () {
      expect(collector, contains("title: '弹幕'"));
      expect(collector, contains("'在屏'"));
      // 698：采样丢弃行随功能删除。
      expect(collector, isNot(contains("'采样丢弃'")));
    });

    test('3.2 安卓面板显示总条数/在屏（超 200 标黄）', () {
      expect(ktState, contains('val danmakuTotal: Int'));
      expect(ktPanel, contains('"弹幕"'));
      expect(ktPanel, contains('danmakuOnscreen > 200'));
    });

    test('3.3 鸿蒙面板同构', () {
      expect(ohosHost, contains('danmakuTotal: number'));
      expect(ohosPanel, contains('弹幕过滤'));
      expect(ohosPanel, contains('s.danmakuOnscreen'));
    });

    test('3.4 Windows 面板追加一行（在 main.cpp 拼接，MpvWindow 无状态引用）', () {
      expect(winStateH, contains('Q_PROPERTY(int danmakuTotal'));
      expect(winMain, contains('弹幕  总 %1 · 在屏 %2'));
    });
  });
}
