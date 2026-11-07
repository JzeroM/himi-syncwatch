import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 633：房主离线判定加 3 秒复核（防 RTM 网络抖动误判解散）。
///
/// 真机回归：鸿蒙观众加入房间后**几秒自动退回首页**（播报已显示进房成功）。
///
/// 根因链：
/// 1. 632 修好鸿蒙消息层（`extractMessageText`）后，roomInfo 终于能收到
///    → `_hostUserId` 首次被真正赋值。
/// 2. Presence 的「房主 leave/timeout → 判解散」判定随之**首次生效**。
/// 3. RTM 网络抖动会短暂上报 `remoteTimeout`（房主其实还在）
///    → 直接弹「房间已解散」→ 1.5s 后 `popUntil` 弹回首页。
///
/// 该判定位于**共享 Dart 层**，安卓 / Windows / 鸿蒙三端同构
///（三者 `withPresence` 均为 true，枚举值 3/4/5 一致），故一次修复三端生效。
void main() {
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    var depth = 0;
    var started = false;
    for (var i = idx + signature.length - 1; i < src.length; i++) {
      final ch = src[i];
      if (ch == '{') {
        depth++;
        started = true;
      } else if (ch == '}') {
        depth--;
        if (started && depth == 0) return src.substring(idx, i + 1);
      }
    }
    fail('$signature 的大括号未配平');
  }

  group('① Presence 离线事件不再直接判解散', () {
    test('leave/timeout 改为延迟复核', () {
      final body = stripComments(bodyOf(
        screen,
        '    _presenceSubscription = rtmService.presenceStream.listen(',
      ));
      expect(body, contains('_scheduleHostOfflineCheck()'));
      // 关键：监听器里不得再直接弹解散框。
      expect(
        body,
        isNot(contains('_showRoomDestroyedDialog()')),
        reason: '一次网络抖动就会把观众踢出房间',
      );
    });

    test('房主重新 join 时取消待执行退出', () {
      final body = stripComments(bodyOf(
        screen,
        '    _presenceSubscription = rtmService.presenceStream.listen(',
      ));
      expect(body, contains('remoteJoinChannel'));
      expect(body, contains('_cancelHostOfflineCheck()'));
    });
  });

  group('② 复核逻辑：3 秒 + whoNow 二次确认', () {
    test('新增 _scheduleHostOfflineCheck，延迟 3 秒', () {
      final body = bodyOf(screen, 'void _scheduleHostOfflineCheck()');
      expect(body, contains('Duration(seconds: 3)'));
    });

    test('复核用 getOnlineUserCount（whoNow）', () {
      final body = bodyOf(screen, 'void _scheduleHostOfflineCheck()');
      expect(body, contains('getOnlineUserCount'));
    });

    test('在线 ≥2 人视为抖动、不退出', () {
      final body = stripComments(
          bodyOf(screen, 'void _scheduleHostOfflineCheck()'));
      expect(body, contains('if (count >= 2)'));
      expect(body, contains('抖动'));
      // count>=2 分支必须 return，不能落到 _showRoomDestroyedDialog。
      final branchIdx = body.indexOf('if (count >= 2)');
      final dialogIdx = body.indexOf('_showRoomDestroyedDialog()');
      expect(dialogIdx, greaterThan(branchIdx));
    });

    test('确认离线才弹解散框', () {
      final body = stripComments(
          bodyOf(screen, 'void _scheduleHostOfflineCheck()'));
      expect(body, contains('房主确认离线'));
      expect(body, contains('_showRoomDestroyedDialog()'));
    });

    test('复核期间再次触发时重置计时（防重复）', () {
      final body = bodyOf(screen, 'void _scheduleHostOfflineCheck()');
      expect(body, contains('_hostOfflineTimer?.cancel()'));
    });
  });

  group('③ _hostUserId 赋值防御', () {
    test('排除空串与自己', () {
      final body = stripComments(bodyOf(screen, 'void _handleRoomInfo('));
      expect(
        body,
        contains('hostId != _myUserId'),
        reason: '若拿到自己的 id，Presence 会把自己的 leave 当房主离线',
      );
      expect(body, contains('hostId.isNotEmpty'));
    });
  });

  group('④ 生命周期清理', () {
    test('新增 _cancelHostOfflineCheck / _clearHostOfflineCheck', () {
      expect(screen, contains('void _cancelHostOfflineCheck()'));
      expect(screen, contains('void _clearHostOfflineCheck()'));
    });

    test('进入解散流程时静默清理（避免重复触发）', () {
      final body =
          stripComments(bodyOf(screen, 'void _showRoomDestroyedDialog()'));
      expect(body, contains('_clearHostOfflineCheck()'));
    });

    test('dispose 清理定时器', () {
      final disposeIdx = screen.indexOf('void dispose()');
      expect(disposeIdx, greaterThan(0));
      final tail = screen.substring(disposeIdx);
      expect(tail, contains('_clearHostOfflineCheck()'));
    });
  });

  group('⑤ 三端一致性（共享层，无平台分支）', () {
    test('Presence 判定与复核逻辑内无 Platform.is* 分支', () {
      for (final sig in [
        'void _scheduleHostOfflineCheck()',
        'void _cancelHostOfflineCheck()',
      ]) {
        final body = stripComments(bodyOf(screen, sig));
        expect(
          body,
          isNot(contains('Platform.is')),
          reason: '$sig 不应有平台分支（三端必须同构）',
        );
      }
      final presenceBody = stripComments(bodyOf(
        screen,
        '    _presenceSubscription = rtmService.presenceStream.listen(',
      ));
      expect(presenceBody, isNot(contains('Platform.is')));
    });

    test('保留 1.5s 自动退回首页（用户确认的既有行为）', () {
      final body =
          stripComments(bodyOf(screen, 'void _showRoomDestroyedDialog()'));
      expect(body, contains('Duration(milliseconds: 1500)'));
      expect(body, contains('popUntil'));
    });
  });
}
