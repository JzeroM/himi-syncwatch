import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 689：Windows 播放未向 Emby 上报进度（参考 Android / 鸿蒙）。
///
/// ## 真机现象
///
/// Windows 单人播放完整播完一集，Emby 里**没有任何观看记录/续播进度**。
/// Android / 鸿蒙正常。
///
/// ## 两个根因
///
/// ### 1. Qt 接管分支直接 return，跳过了 `_reportStart()`
///
/// `_loadStream` 里：
/// ```dart
/// if (tookOver) {
///   _isSwitchingMedia = false;
///   return true;          // ← 下面的 _reportStart() 永远不执行
/// }
/// ...
/// unawaited(_reportStart());
/// ```
///
/// Windows 单人播放走 Qt 独立窗口 → `tookOver == true` → **会话从未开始
/// 上报**。
///
/// ### 2. 上报链路读的是空闲引擎 `_player`
///
/// Qt 接管后真正的 mpv 在 Qt 进程里，本页 `_player` 是**从未起播的空闲
/// 引擎**：
///   - `_player.position` 恒 0 → 进度永远写 0
///   - `_player.state` 恒 stopped → `isPaused` 判定错误
///   - `_player.duration` 恒 0 → 时长只能靠 fallback
///
/// 房间模式早已用 `_roomEngine` 处理，但单人模式漏了。
///
/// ## 修复
///
/// 1. Qt 接管分支补 `unawaited(_reportStart())`
/// 2. 新增 `_reportEngine`（语义同 `_roomEngine`），上报链路全部改读它
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String playerScreen;

  setUpAll(() {
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
  // A. Qt 接管分支补上报启动
  // ═══════════════════════════════════════════════════════════════

  group('A Qt 接管分支', () {
    test('A1 接管后补 _reportStart（否则会话永不开始）', () {
      final body = extract(playerScreen, 'Future<bool> _loadStream(');
      final tookIdx = body.indexOf('if (tookOver)');
      expect(tookIdx, greaterThan(0));
      // 接管分支内必须有 _reportStart()
      // 690：接管分支补了「解除片段抑制」等逻辑，窗口扩大到 2000
      final tookBlock =
          body.substring(tookIdx, (tookIdx + 2000).clamp(0, body.length));
      expect(tookBlock, contains('_reportStart()'));
      expect(tookBlock, contains('return true;'));
      // 顺序：先启动上报，再 return
      expect(tookBlock.indexOf('_reportStart()'),
          lessThan(tookBlock.indexOf('return true;')));
    });

    test('A2 非 Qt 路径的上报仍在（不误删）', () {
      final body = extract(playerScreen, 'Future<bool> _loadStream(');
      // 内置播放器路径也有 _reportStart
      final count = RegExp(r'_reportStart\(\)').allMatches(body).length;
      expect(count, greaterThanOrEqualTo(2),
          reason: 'Qt 接管分支 + 内置播放器路径各一次');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 上报链路读真实引擎
  // ═══════════════════════════════════════════════════════════════

  group('B 上报引擎', () {
    test('B1 新增 _reportEngine（Windows 且 Qt 存活用 Qt）', () {
      // getter 没有参数括号，不能用 extract（它按 `(` 定位）
      final start = playerScreen.indexOf('PlayerAdapter get _reportEngine');
      expect(start, greaterThan(0));
      final body = playerScreen.substring(start, start + 400);
      expect(body, contains('TargetPlatform.windows'));
      expect(body, contains('MpvSessionPlatform.activeQtAdapter'));
      expect(body, contains('qt.isAlive'));
      expect(body, contains('return qt;'));
      // 回退本页引擎
      expect(body, contains('return _player;'));
    });

    test('B2 _reportPosition 读真实引擎（不再恒 0）', () {
      final body = extract(playerScreen, 'int get _reportPosition');
      expect(body, contains('_reportEngine.position'));
      expect(body, isNot(contains('_player.position')));
    });

    test('B3 isPaused 读真实引擎（不再恒 stopped）', () {
      final body = extract(playerScreen, 'Future<void> _reportProgress()');
      expect(body, contains('_reportEngine.state'));
      expect(body, isNot(contains('_player.state')));
    });

    test('B4 时长同步读真实引擎', () {
      final start = playerScreen.indexOf('void _syncDurationFromPlayer()');
      expect(start, greaterThan(0));
      final body = codeOnly(playerScreen.substring(start, start + 400));
      expect(body, contains('_reportEngine.duration'));
      expect(body, isNot(contains('_player.duration')));
    });

    test('B5 其它平台行为不变（非 Windows 直接回退 _player）', () {
      // Android / 鸿蒙 / iOS 上 activeQtAdapter 恒 null（只有 Windows 拉起），
      // 所以 _reportEngine 等价于 _player，行为与旧版完全一致。
      final body = extract(playerScreen, 'PlayerAdapter get _reportEngine');
      expect(body, contains('if (defaultTargetPlatform == TargetPlatform.windows)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 上报完整性（开始 / 进度 / 停止）
  // ═══════════════════════════════════════════════════════════════

  group('C 上报三阶段完整', () {
    test('C1 会话开始：reportPlaybackStart', () {
      final body = extract(playerScreen, 'Future<void> _reportStart()');
      expect(body, contains('reportPlaybackStart'));
      expect(body, contains('positionMs: _reportPosition'));
      expect(body, contains('_startReportTimer()'));
    });

    test('C2 定期进度：reportPlaybackProgress + isPaused', () {
      final body = extract(playerScreen, 'Future<void> _reportProgress()');
      expect(body, contains('reportPlaybackProgress'));
      expect(body, contains('isPaused:'));
    });

    test('C3 会话停止：reportPlaybackStopped（写最终进度）', () {
      final body = extract(playerScreen, 'Future<void> _reportStopped(');
      expect(body, contains('reportPlaybackStopped'));
      expect(body, contains('positionMs: finalPosition'));
    });

    test('C4 定时器周期已配置', () {
      final body = extract(playerScreen, 'void _startReportTimer()');
      expect(body, contains('PlayerScreen.playbackReportInterval'));
      expect(body, contains('_reportProgress()'));
    });

    test('C5 仅单人/房主上报（房间观众不上报）', () {
      expect(playerScreen, contains('bool get _shouldReportPlayback => widget.roomCode == null;'));
    });
  });
}
