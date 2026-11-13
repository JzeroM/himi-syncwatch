import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：Windows 弹幕改为 QML 自绘（弃用 ASS 旁路）。
///
/// ## 为什么改
///
/// 原实现把弹幕生成 ASS 文件、作为**次字幕轨**交给 mpv。三个硬伤：
/// 1. **开关弹幕卡视频**：`sub-remove` + `sub-add` + 切 `secondary-sid`
///    会让 mpv 重建字幕/OSD 管线（真机反馈）。
/// 2. **HDR 下弹幕过曝**：HDR 管线是 BT.2020 + PQ，ASS 的 `#FFFFFF` 被当
///    作 PQ 编码的 HDR 白（≈10000 nit）。
/// 3. **与字幕设置耦合**：`sub-scale`/`sub-pos` 是全局属性。
///
/// ## 算法来源
///
/// **逐条对齐安卓 `DanmakuLayerView.kt`**（用户明确要求「全部对齐安卓鸿蒙」）。
void main() {
  String read(String p) => File(p).readAsStringSync();

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  late String overlay;
  late String layer;
  late String stateH;
  late String stateCpp;
  late String cmake;

  setUpAll(() {
    overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
    layer = read('native/windows_qt_player/src/qml/DanmakuLayer.qml');
    stateH = read('native/windows_qt_player/src/player_state.h');
    stateCpp = read('native/windows_qt_player/src/player_state.cpp');
    cmake = read('native/windows_qt_player/CMakeLists.txt');
  });

  group('1. ASS 方案已移除（消除卡顿/HDR 过曝/字幕耦合）', () {
    test('1.1 Overlay 不再生成 ASS', () {
      expect(codeOnly(overlay), isNot(contains('buildDanmakuAss')));
      expect(codeOnly(overlay), isNot(contains('setDanmakuAss')));
      expect(codeOnly(overlay), isNot(contains('assTime')));
      expect(codeOnly(overlay), isNot(contains('assColor')));
    });

    test('1.2 Overlay 不再有 ASS 重建定时器与样式签名', () {
      expect(codeOnly(overlay), isNot(contains('danmakuBuildTimer')));
      expect(codeOnly(overlay), isNot(contains('danmakuStyleSig')));
    });

    test('1.3 开关弹幕只改本地态，不触碰 mpv 管线', () {
      final start = overlay.indexOf('onDanmakuClicked');
      expect(start, greaterThan(0));
      final block = overlay.substring(start, start + 600);
      // 必须置本地态 + 通知 Dart
      expect(block, contains('danmakuOn = !danmakuOn'));
      expect(block, contains('patchState'));
      // 不得再重建 ASS / 发 mpv 字幕命令
      expect(block, isNot(contains('restart()')));
      expect(block, isNot(contains('setDanmakuAss')));
    });

    test('1.4 自绘层已挂载且位于控件之下（z=1）', () {
      expect(codeOnly(overlay), contains('DanmakuLayer {'));
      expect(codeOnly(overlay), contains('z: 1'));
    });
  });

  group('2. 参数逐条对齐安卓/Flutter', () {
    test('2.1 基准字号 25 / 行距 6 / 边距 8', () {
      expect(layer, contains('baseFontSize: 25'));
      expect(layer, contains('rowGap: 6'));
      expect(layer, contains('edgePadding: 8'));
    });

    test('2.2 穿屏 8000ms / 驻留 4000ms / 间隙 150ms', () {
      expect(layer, contains('scrollBaseMs: 8000'));
      expect(layer, contains('fixedMs: 4000'));
      expect(layer, contains('trackGapMs: 150'));
    });

    test('2.3 生命周期余量 500ms / 超前丢弃 35000ms', () {
      // 对应安卓 lifeSlackMs / keepAheadMs
      expect(layer, contains('lifeSlackMs: 500'));
      expect(layer, contains('keepAheadMs: 35000'));
    });

    test('2.4 行数按屏高自适应并夹到用户设置', () {
      expect(codeOnly(layer), contains('autoRows'));
      expect(codeOnly(layer), contains('Math.min(scrollRows, autoRows)'));
      expect(codeOnly(layer), contains('Math.min(topRows, autoRows)'));
      expect(codeOnly(layer), contains('Math.min(bottomRows, autoRows)'));
    });

    test('2.5 行数读取 playerState 真实设置', () {
      for (final f in const [
        'danmakuScrollRows',
        'danmakuTopRows',
        'danmakuBottomRows',
      ]) {
        expect(overlay, contains('playerState.$f'), reason: '应绑定 $f');
      }
    });
  });

  group('3. 核心机制对齐安卓', () {
    test('3.1 飞行缓存（防止滚动弹幕被拦腰截断）', () {
      expect(codeOnly(layer), contains('syncFlying'));
      expect(codeOnly(layer), contains('_state.flying'));
    });

    test('3.2 行号绑定一旦分配不再变（防整屏跳行）', () {
      expect(codeOnly(layer), contains('_state.laneOf'));
      // 已分配就跳过（含 -1 丢弃）
      expect(codeOnly(layer), contains('!== undefined) continue'));
    });

    test('3.3 轨道满 → 丢弃（不叠行）', () {
      expect(codeOnly(layer), contains('picked = -1'));
      expect(codeOnly(layer), contains('lane < 0) continue'));
    });

    test('3.4 占用时长 = 完全入屏 + 间隙', () {
      // 与 Flutter _occupancySeconds / 安卓 occupancyMs 同构
      expect(codeOnly(layer), contains('fullyEntered'));
      expect(codeOnly(layer), contains('textW / (width + textW)'));
      expect(codeOnly(layer), contains('travelMs * fullyEntered + trackGapMs'));
    });

    test('3.5 文本宽度估算：CJK 1.0 / 其余 0.55', () {
      expect(codeOnly(layer), contains('estimateWidth'));
      expect(codeOnly(layer), contains('units += wide ? 1.0 : 0.55'));
    });

    test('3.6 顶/底淡入淡出（首尾各 10%）', () {
      expect(codeOnly(layer), contains('fixedFade'));
      expect(codeOnly(layer), contains('progress < 0.1'));
      expect(codeOnly(layer), contains('progress > 0.9'));
    });

    test('3.7 按时间升序分配（冲突表必须按时间序推进）', () {
      expect(codeOnly(layer), contains('sort(function (a, b)'));
      expect(codeOnly(layer), contains('a.timeMs - b.timeMs'));
    });
  });

  group('4. 性能设计', () {
    test('4.1 弹幕池复用（固定 Repeater，不重建节点）', () {
      expect(codeOnly(layer), contains('Repeater {'));
      expect(codeOnly(layer), contains('model: root.poolSize'));
    });

    test('4.2 30fps 帧驱动（与鸿蒙一致）', () {
      expect(layer, contains('frameIntervalMs: 33'));
    });

    test('4.3 暂停时冻结（不空转）', () {
      expect(codeOnly(layer), contains('running: root.enabled && root.playing'));
    });

    test('4.4 中间状态不触发 QML 通知（性能）', () {
      // flying/laneOf 放在普通对象里，避免 30fps 属性通知风暴
      expect(layer, contains('readonly property var _state'));
      expect(codeOnly(layer), contains('_state.flying'));
      expect(codeOnly(layer), contains('_state.laneOf'));
    });
  });

  group('5. C++ 状态与构建注册', () {
    test('5.1 player_state 暴露三个行数属性', () {
      for (final f in const [
        'danmakuScrollRows',
        'danmakuTopRows',
        'danmakuBottomRows',
      ]) {
        expect(stateH, contains('Q_PROPERTY(int $f READ $f NOTIFY changed)'));
        expect(stateH, contains('int ${f}_ ='));
      }
    });

    test('5.2 applyJson 解析三个行数字段', () {
      for (final f in const [
        'danmakuScrollRows',
        'danmakuTopRows',
        'danmakuBottomRows',
      ]) {
        expect(stateCpp, contains('"$f"'), reason: '应解析 $f');
      }
    });

    test('5.3 新 QML 已注册进 CMake', () {
      expect(cmake, contains('DanmakuLayer'));
      expect(cmake, contains('src/qml/DanmakuLayer.qml'));
    });
  });

  group('6. Dart 侧已下发行数', () {
    test('6.1 NativePlayerState 序列化含三字段', () {
      final dart =
          read('lib/services/player/native/native_player_state.dart');
      for (final f in const [
        'danmakuScrollRows',
        'danmakuTopRows',
        'danmakuBottomRows',
      ]) {
        expect(dart, contains("'$f': $f"), reason: '应下发 $f');
      }
    });
  });
}
