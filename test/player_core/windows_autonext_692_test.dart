import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 692：Windows 自动下一集（对齐安卓/鸿蒙）+ 跳过胶囊样式。
///
/// ## 自动下一集此前完全无效的根因
///
/// 项目开了 `keep-open=yes`（与安卓/鸿蒙一致，播完停在最后一帧）——
/// **该选项会让 mpv 不发送 `MPV_EVENT_END_FILE`**，所以我 691 加的
/// `playbackEnded` 链路是死的。
///
/// ## 安卓/鸿蒙的实际做法（已核实）
///
/// | 平台 | keep-open | 播完判定 |
/// |---|---|---|
/// | 鸿蒙 | `yes` | 观察 `eof-reached` 属性 |
/// | 安卓 | `yes`（media_kit 默认） | `player.stream.completed` → `eof-reached` |
///
/// 两者都**保留最后一帧**，靠 `eof-reached` 触发切集——切集瞬间画面
/// 自然换掉，用户看不到「停在最后一帧」。
///
/// ## 修复
///
/// - Qt：观察 `eof-reached` 属性（去重），不再依赖 `END_FILE`
/// - Dart：复用安卓的双守卫（时长>0 + seek 冷却期内忽略）
/// - 胶囊：圆角矩形（`radius: 8`）+ 底栏内底部（`bottomMargin: 8`）
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String mpvCpp;
  late String mpvH;
  late String overlayQml;
  late String playerScreen;

  setUpAll(() {
    const dir = 'native/windows_qt_player/src';
    mpvCpp = read('$dir/mpv_window.cpp');
    mpvH = read('$dir/mpv_window.h');
    overlayQml = read('$dir/qml/Overlay.qml');
    playerScreen = read('lib/screens/player/player_screen.dart');
  });

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  String extract(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    var i = start;
    while (i < src.length && src[i] != '(') {
      i++;
    }
    var paren = 0;
    for (; i < src.length; i++) {
      if (src[i] == '(') paren++;
      if (src[i] == ')') {
        paren--;
        if (paren == 0) {
          i++;
          break;
        }
      }
    }
    while (i < src.length && src[i] != '{') {
      i++;
    }
    var depth = 0;
    for (; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    return src.substring(start);
  }

  // ═══════════════════════════════════════════════════════════════
  // A. Qt 侧：eof-reached 属性驱动
  // ═══════════════════════════════════════════════════════════════

  group('A Qt 播完判定', () {
    test('A1 观察 eof-reached 属性', () {
      expect(mpvCpp,
          contains('mpv_observe_property(mpv_, 0, "eof-reached", MPV_FORMAT_FLAG)'));
    });

    test('A2 属性变化时去重并 emit playbackEnded', () {
      // 定位 PROPERTY_CHANGE 分支里的那处（不是 observe_property）
      final start = mpvCpp.indexOf('QLatin1String("eof-reached") &&');
      expect(start, greaterThan(0));
      final block =
          mpvCpp.substring(start, (start + 900).clamp(0, mpvCpp.length));
      // 剔除注释后判定（注释里提到 emit 是说明为什么改）
      expect(codeOnly(block), contains('emit playbackEnded()'));
      // 去重：同值不重复通知
      expect(block, contains('if (reached != eofReached_)'));
    });

    test('A3 eofReached_ 成员存在', () {
      expect(mpvH, contains('bool eofReached_ = false'));
    });

    test('A4 load/stop 时重置 eofReached_（防跨集污染）', () {
      final loadBody = extract(mpvCpp, 'void MpvWindow::load(');
      expect(loadBody, contains('eofReached_ = false'));
      final stopBody = extract(mpvCpp, 'void MpvWindow::stopPlayback()');
      expect(stopBody, contains('eofReached_ = false'));
    });

    test('A5 END_FILE 不再 emit（keep-open 下非自然播完）', () {
      final start = mpvCpp.indexOf('case MPV_EVENT_END_FILE:');
      expect(start, greaterThan(0));
      final block = mpvCpp.substring(start, start + 700);
      // 保留错误日志，但不再 emit playbackEnded
      expect(codeOnly(block), isNot(contains('emit playbackEnded()')));
      expect(block, contains('MPV_END_FILE_REASON_ERROR'));
    });

    test('A6 keep-open 仍为 yes（与安卓/鸿蒙一致，保留最后一帧）', () {
      expect(mpvCpp, contains('mpv_set_option_string(mpv_, "keep-open", "yes")'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. Dart 侧：双守卫（对齐 MpvPlayerAdapter._handleEofReached）
  // ═══════════════════════════════════════════════════════════════

  group('B Dart 双守卫', () {
    test('B1 守卫 1：时长未知忽略', () {
      final body = extract(playerScreen, 'void _handleQtPlaybackEnded()');
      expect(body, contains('_duration.inMilliseconds <= 0'));
      expect(body, contains('return;'));
    });

    test('B2 守卫 2：seek 冷却期内忽略', () {
      final body = extract(playerScreen, 'void _handleQtPlaybackEnded()');
      expect(body, contains('autoNextSeekCooldown'));
      expect(body, contains('_lastSeekCompletedAt'));
    });

    test('B3 通过守卫后调 _handleEpisodeFinished', () {
      final body = extract(playerScreen, 'void _handleQtPlaybackEnded()');
      expect(body, contains('_handleEpisodeFinished('));
      expect(body, contains('completedAtMs: _duration.inMilliseconds'));
    });

    test('B4 与安卓的 MpvPlayerAdapter 守卫一致（时长 + 冷却）', () {
      final adapter = read('lib/services/player/mpv_player_adapter.dart');
      final body = extract(adapter, 'void _handleEofReached(');
      // 安卓侧同样的两道守卫
      expect(body, contains('_durationMs <= 0'));
      expect(body, contains('_lastSeekCommandAt'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 跳过胶囊样式
  // ═══════════════════════════════════════════════════════════════

  group('C 胶囊样式与位置', () {
    test('C1 两个独立胶囊（片头贴左、片尾贴右）', () {
      expect(overlayQml, contains('id: skipIntroCapsule'));
      expect(overlayQml, contains('id: skipOutroCapsule'));
      expect(overlayQml, contains('"跳过片头"'));
      expect(overlayQml, contains('"跳过片尾"'));
    });

    test('C2 圆角矩形（radius 8，不是椭圆 16/17）', () {
      for (final id in ['skipIntroCapsule', 'skipOutroCapsule']) {
        final start = overlayQml.indexOf('id: $id');
        expect(start, greaterThan(0));
        final block =
            overlayQml.substring(start, (start + 700).clamp(0, overlayQml.length));
        expect(block, contains('radius: 8'));
        expect(block, isNot(contains('radius: 16')));
        expect(block, isNot(contains('radius: 17')));
      }
    });

    test('C3 贴在进度条上方（不遮挡进度条）', () {
      // 定位依赖 BottomBar 暴露的 sliderRect
      expect(overlayQml, contains('bottomBar.sliderRect'));
      expect(overlayQml, contains('mapToItem(skipCapsuleLayer'));
      // 垂直方向：进度条上沿再往上
      expect(overlayQml, contains('sliderRect.y - height - 8'));
    });

    test('C4 片头左对齐、片尾右对齐', () {
      // 片头 x = 进度条左端
      expect(overlayQml, contains('x: skipCapsuleLayer.sliderRect.x\n'));
      // 片尾右边缘与进度条右边缘齐平
      expect(overlayQml,
          contains('skipCapsuleLayer.sliderRect.width - width'));
    });

    test('C5 不受 controlsVisible 控制（独立倒计时）', () {
      for (final id in ['skipIntroCapsule', 'skipOutroCapsule']) {
        final start = overlayQml.indexOf('id: $id');
        final block =
            overlayQml.substring(start, (start + 700).clamp(0, overlayQml.length));
        expect(block, isNot(contains('controlsVisible')));
        expect(block, contains('playerState.skipPrompt'));
      }
    });

    test('C6 sliderRect 用 mapToItem（嵌套布局坐标必须转换）', () {
      final bottomBar =
          read('native/windows_qt_player/src/qml/BottomBar.qml');
      expect(bottomBar, contains('readonly property rect sliderRect'));
      expect(bottomBar, contains('id: seekSlider'));
      // 【关键】seekSlider 在 ColumnLayout → RowLayout 里，x/y 是相对
      // 直接父级——必须 mapToItem 映射到 BottomBar 根坐标系，否则胶囊
      // 被推到屏幕外（真机「控件未显示」）。
      expect(bottomBar, contains('seekSlider.mapToItem(root, 0, 0)'));
      expect(bottomBar, isNot(contains(
          'Qt.rect(\n        seekSlider.x, seekSlider.y')));
    });

    test('C8 坐标无效时胶囊不显示（防闪到角落）', () {
      for (final id in ['skipIntroCapsule', 'skipOutroCapsule']) {
        final idx = overlayQml.indexOf('id: $id');
        final block = overlayQml.substring(
            idx, (idx + 400).clamp(0, overlayQml.length));
        expect(block, contains('sliderRect.width > 0'));
      }
    });

    test('C7 点击回传 skipSegment（观众门控）', () {
      expect(overlayQml, contains('"type": "skipSegment"'));
      expect(overlayQml, contains('playerState.canControl'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 693：skipPrompt 必须置 dirty（否则 QML 绑定永不刷新）
  // ═══════════════════════════════════════════════════════════════

  group('D skipPrompt 信号发射', () {
    test('D1 skipPrompt 走 assign 置 dirty', () {
      final src = read('native/windows_qt_player/src/player_state.cpp');
      // 【真机根因】裸赋值 `skipPrompt_ = sp` 不置 dirty →
      // `if (dirty) emit changed()` 不发射 → QML 的
      // `playerState.skipPrompt` 绑定永不重新求值 → 胶囊不显示。
      expect(src, contains('dirty |= assign(skipPrompt_, sp)'));
    });

    test('D2 不得有裸赋值 skipPrompt_ = sp', () {
      final src = read('native/windows_qt_player/src/player_state.cpp');
      // 剔除注释后判定
      final code = src
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('*');
          })
          .join('\n');
      expect(code, isNot(contains('skipPrompt_ = sp')));
    });

    test('D3 applyJson 末尾按 dirty 发射 changed', () {
      final src = read('native/windows_qt_player/src/player_state.cpp');
      final idx = src.indexOf('dirty |= assign(skipPrompt_, sp)');
      expect(idx, greaterThan(0));
      final after = src.substring(idx, idx + 300);
      expect(after, contains('if (dirty) emit changed()'));
    });

    test('D4 QML 绑定依赖 skipPrompt 属性通知', () {
      final stateH = read('native/windows_qt_player/src/player_state.h');
      expect(stateH, contains('Q_PROPERTY(QString skipPrompt READ skipPrompt NOTIFY changed)'));
      // 胶囊 visible 直接绑该属性
      expect(overlayQml, contains('playerState.skipPrompt === "intro"'));
      expect(overlayQml, contains('playerState.skipPrompt === "outro"'));
    });
  });
}
