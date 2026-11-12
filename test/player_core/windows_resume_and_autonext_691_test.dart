import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 691：Windows 端三个真机问题。
///
/// ## 1. 点继续观看一直黑屏（严重）
///
/// 690 试图用 `loadfile` 的 `start=12.345` 字符串选项传起点——但
/// **`mpv_command` 不接受选项字符串**（options 必须走 `mpv_command_node`
/// 的 NODE_MAP），命令失败 → 无媒体 → 黑屏。
///
/// 修复：`load` 回到最简 `{"loadfile", url, nullptr}`，起点在
/// `MPV_EVENT_FILE_LOADED` 时补 seek（那时媒体已就绪，一定生效）。
///
/// ## 2. 跳过片头/片尾胶囊位置
///
/// 移到底栏**水平居中**（底栏高 96、胶囊高 34 → `bottomMargin: 31`）。
///
/// ## 3. 自动下一集没实现
///
/// `MpvWindow::playbackEnded` 信号**无人连接**——Qt 播完一集 Dart 完全
/// 不知道。安卓靠 `AdapterMediaStatus.end` 事件驱动
/// `_handleEpisodeFinished`，Qt 缺这条链路。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String mpvCpp;
  late String mainCpp;
  late String pipeH;
  late String pipeCpp;
  late String overlayQml;
  late String pipeDart;
  late String adapterDart;
  late String playerScreen;

  setUpAll(() {
    const dir = 'native/windows_qt_player/src';
    mpvCpp = read('$dir/mpv_window.cpp');
    mainCpp = read('$dir/main.cpp');
    pipeH = read('$dir/pipe_server.h');
    pipeCpp = read('$dir/pipe_server.cpp');
    overlayQml = read('$dir/qml/Overlay.qml');
    pipeDart = read('lib/services/player/qt_player_pipe.dart');
    adapterDart = read('lib/services/player/qt_player_adapter.dart');
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
  // A. 续播黑屏
  // ═══════════════════════════════════════════════════════════════

  group('A 续播黑屏', () {
    test('A1 loadfile 不再传 start 选项（mpv_command 不支持）', () {
      final body = extract(mpvCpp, 'void MpvWindow::load(');
      final code = codeOnly(body);
      expect(code, contains('{"loadfile", u.constData(), nullptr}'));
      // 不再有 `start=` 选项拼接（关键：mpv_command 不支持选项字符串）
      expect(code, isNot(contains('QByteArray("start=")')));
      expect(code, isNot(contains('"replace"')));
    });

    test('A2 记录 pendingStartMs_ 供 FILE_LOADED 使用', () {
      final body = extract(mpvCpp, 'void MpvWindow::load(');
      expect(body, contains('pendingStartMs_ = startMs > 0 ? startMs : 0'));
    });

    test('A3 FILE_LOADED 无条件 seek（去掉 1.5s 阈值）', () {
      final start = mpvCpp.indexOf('case MPV_EVENT_FILE_LOADED:');
      expect(start, greaterThan(0));
      final block = mpvCpp.substring(start, start + 800);
      expect(block, contains('seekTo(target)'));
      // 不再有偏差判断（那是 690 的兜底逻辑，现在 seek 是唯一入口）
      expect(codeOnly(block), isNot(contains('qAbs(positionMs_ - target)')));
      expect(codeOnly(block), isNot(contains('> 1500')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 胶囊位置（底栏居中）
  // ═══════════════════════════════════════════════════════════════

  group('B 跳过胶囊位置', () {
    test('B1 水平居中', () {
      final start = overlayQml.indexOf('id: skipCapsule');
      expect(start, greaterThan(0));
      final block = overlayQml.substring(start, start + 700);
      expect(block, contains('anchors.horizontalCenter: parent.horizontalCenter'));
    });

    test('B2 底栏内垂直居中（bottomMargin 31）', () {
      final start = overlayQml.indexOf('id: skipCapsule');
      final block = overlayQml.substring(start, start + 700);
      expect(block, contains('anchors.bottomMargin: 31'));
      expect(block, contains('height: 34'));
    });

    test('B3 不受 controlsVisible 控制（独立倒计时）', () {
      final start = overlayQml.indexOf('id: skipCapsule');
      final block = overlayQml.substring(start, start + 700);
      expect(block, isNot(contains('controlsVisible')));
      expect(block, contains('playerState.skipPrompt'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 自动下一集
  // ═══════════════════════════════════════════════════════════════

  group('C 自动下一集', () {
    test('C1 Qt 侧连接 playbackEnded 信号', () {
      expect(mainCpp, contains('MpvWindow::playbackEnded'));
      expect(mainCpp, contains('pipe.sendEnded()'));
    });

    test('C2 新增 ended 帧协议', () {
      expect(pipeH, contains('void sendEnded()'));
      expect(pipeCpp, contains('QStringLiteral("ended")'));
      expect(pipeDart, contains("type == 'ended'"));
      expect(pipeDart, contains('Stream<void> get ended'));
    });

    test('C3 适配器暴露 onPlaybackEnded', () {
      expect(adapterDart, contains('void Function()? onPlaybackEnded'));
      expect(adapterDart, contains('_pipe.ended.listen'));
    });

    test('C4 房间模式接线', () {
      final body = extract(playerScreen, 'void _wireRoomQtAdapter');
      expect(body, contains('adapter.onPlaybackEnded = _handleQtPlaybackEnded'));
    });

    test('C5 单人模式也接线（Session 路径）', () {
      final body = extract(playerScreen, 'Future<bool> _startQtPlayer(');
      expect(body, contains('adapter.onPlaybackEnded = _handleQtPlaybackEnded'));
    });

    test('C6 复用 _handleEpisodeFinished + seek 冷却防误判', () {
      final body = extract(playerScreen, 'void _handleQtPlaybackEnded()');
      expect(body, contains('_handleEpisodeFinished('));
      // 与安卓同款：seek/拖动中忽略
      expect(body, contains('_isSeekingPlayback'));
      expect(body, contains('_isDraggingSlider'));
      expect(body, contains('autoNextSeekCooldown'));
    });

    test('C7 防重门由 _handleEpisodeFinished 内部保证', () {
      final body = extract(playerScreen, 'Future<void> _handleEpisodeFinished(');
      expect(body, contains('_endHandled'));
      expect(body, contains('!_canControlPlayback'));
    });
  });
}
