import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 632：房间同步三连修（同一个根因的三种表现）。
///
/// 真机现象（鸿蒙观众）：
/// 1. 房主暂停 → 观众没暂停
/// 2. 中途进房 → 资源列表为空
/// 3. 中途进房 → 误报「房间已解散」（实际没解散）
///
/// 根因分两层：
/// - **消息层**：鸿蒙 ArkTS 侧 `typeof e.message === 'string' ? e.message : ''`
///   把非字符串消息丢成空串 → Dart `jsonDecode('')` 抛异常被静默吞掉 →
///   所有消息（roomInfo/join/heartbeat/syncPlay/pause）全部失效。
///   Windows 是 `assign(message, messageLength)` 按字节取，故正常。
/// - **逻辑层**：心跳因 `state != playing` 停发；`_syncPaused` 前置 return
///   丢弃暂停状态；观众从不主动请求 roomInfo；whoNow==0 误判解散。
void main() {
  final arktsManager = File(
    'plugins/himi_ohos_rtm/ohos/src/main/ets/RtmManager.ets',
  ).readAsStringSync();
  final rtmService = File('lib/services/rtm_service.dart').readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  /// 取方法体（从签名末尾的大括号开始配平）。
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

  group('① 消息层：鸿蒙 ArkTS 必须能还原 Uint8Array 消息', () {
    test('新增 extractMessageText 统一解码', () {
      expect(arktsManager, contains('private extractMessageText('));
      expect(arktsManager, contains('util.TextDecoder.create'));
      expect(arktsManager, contains("import util from '@ohos.util';"));
    });

    test('message 事件走 extractMessageText，不再丢弃非 string', () {
      final body = arktsManager.substring(
        arktsManager.indexOf("addEventListener(id, 'message'"),
      );
      final head = stripComments(body.substring(0, body.indexOf('});')));
      expect(head, contains('this.extractMessageText(e.message)'));
      // 旧实现的关键缺陷：三元丢弃（注释里提到旧代码不算）。
      expect(
        head,
        isNot(contains("typeof e.message === 'string'")),
        reason: '非 string 消息会被丢成空串 → Dart 侧 jsonDecode 失败',
      );
    });

    test('extractMessageText 同时处理 string 与 Uint8Array', () {
      final body = bodyOf(arktsManager, 'private extractMessageText(');
      expect(body, contains("typeof raw === 'string'"));
      expect(body, contains('Uint8Array'));
      expect(body, contains('decodeToString'));
    });
  });

  group('② 消息层：Dart 侧不再静默吞掉空消息', () {
    test('空消息显式记日志', () {
      expect(rtmService, contains('收到空消息（内容丢失）'));
      expect(rtmService, contains('if (raw.isEmpty)'));
    });

    test('解析失败带长度与片段（便于定位）', () {
      expect(rtmService, contains('len=\${raw.length}'));
      expect(rtmService, contains('前 100 字'));
    });
  });

  group('③ 暂停同步：心跳必须常发', () {
    test('_startHeartbeat 不再因非播放态停发', () {
      final body = stripComments(bodyOf(screen, 'void _startHeartbeat()'));
      expect(
        body,
        isNot(contains('!= AdapterPlaybackState.playing) return')),
        reason: '房主一暂停就停发心跳 → 观众永远收不到 playing:false',
      );
      expect(body, contains('final playing ='));
    });

    test('暂停时 rate 传 1.0（避免按暂停前倍速外推）', () {
      final body = bodyOf(screen, 'void _startHeartbeat()');
      expect(body, contains('playing ? _player.playbackRate : 1.0'));
    });

    test('_handleHeartbeat 的状态应用在所有守卫之前', () {
      final body =
          stripComments(bodyOf(screen, 'void _handleHeartbeat('));
      final stateIdx =
          body.indexOf('_player.state = AdapterPlaybackState.paused');
      final guardIdx = body.indexOf('if (_syncPaused) return;');
      expect(stateIdx, greaterThan(0));
      expect(guardIdx, greaterThan(0));
      expect(
        stateIdx,
        lessThan(guardIdx),
        reason: '_syncPaused 只应抑制位置校正，不能连带屏蔽暂停状态',
      );
    });

    test('_handleHeartbeat 无前置 _syncPaused return', () {
      final body =
          stripComments(bodyOf(screen, 'void _handleHeartbeat('));
      final firstGuard = body.indexOf('if (_isHost) return;');
      final syncPaused = body.indexOf('if (_syncPaused) return;');
      expect(firstGuard, greaterThan(0));
      // _syncPaused 必须在状态应用之后（即不是紧跟 _isHost）。
      expect(syncPaused, greaterThan(body.indexOf('_player.state =')));
    });
  });

  group('④ 暂停同步：syncPlay / roomInfo 携带 paused', () {
    test('sendCommand 支持 paused 参数', () {
      expect(rtmService, contains('bool? paused,'));
      expect(rtmService, contains("if (paused != null) 'paused': paused,"));
    });

    test('sendRoomInfo 支持 paused 参数', () {
      final idx = rtmService.indexOf('Future<void> sendRoomInfo(');
      expect(idx, greaterThan(0));
      final body = rtmService.substring(idx, idx + 2500);
      expect(body, contains('bool? paused,'));
    });

    test('房主 syncPlay 下发真实暂停状态', () {
      expect(
        screen,
        contains('paused: _player.state != AdapterPlaybackState.playing,'),
      );
    });

    test('观众收到 paused 后立即回暂停', () {
      expect(screen, contains('void _pauseAfterAudienceStart()'));
      // syncPlay 与 roomInfo 两条起播路径都要处理。
      final count = 'paused'.allMatches(screen).length;
      expect(count, greaterThanOrEqualTo(4));
      expect(screen, contains("if (message['paused'] == true)"));
    });
  });

  group('⑤ 中途进房：主动请求 roomInfo', () {
    test('新增 _startRoomInfoRequestRetry（指数退避）', () {
      expect(screen, contains('void _startRoomInfoRequestRetry()'));
      final body = bodyOf(screen, 'void _startRoomInfoRequestRetry()');
      expect(body, contains('1 << _roomInfoRequestAttempts'));
      expect(body, contains('sendRequestRoomInfo()'));
    });

    test('进房后立即启动重请求（不等 roomInfo）', () {
      // 关键：调用点必须在 _setupRoomSync 的观众分支里，而不是只在
      // _applyStreamsFromRoomInfo 末尾（旧实现导致死循环）。
      final setupIdx = screen.indexOf('void _setupRoomSync() async {');
      expect(setupIdx, greaterThan(0));
      final setupBody = bodyOf(screen, 'void _setupRoomSync() async {');
      expect(setupBody, contains('_startRoomInfoRequestRetry()'));
    });

    test('收到 roomInfo 后停止重请求', () {
      final body = bodyOf(screen, 'void _handleRoomInfo(');
      expect(body, contains('_stopRoomInfoRequestRetry()'));
    });

    test('dispose 清理重请求定时器', () {
      expect(screen, contains('_stopRoomInfoRequestRetry();'));
      final disposeIdx = screen.indexOf('void dispose()');
      expect(disposeIdx, greaterThan(0));
    });
  });

  group('⑥ 中途进房：不再误判房间解散', () {
    test('whoNow == 0 不再判解散', () {
      final body =
          stripComments(bodyOf(screen, 'void _setupRoomSync() async {'));
      expect(
        body,
        isNot(contains('if (onlineCount == 0)')),
        reason: '刚订阅时 presence 未同步返回 0 是常态，不能据此判解散',
      );
      expect(body, contains('presence 可能未同步'));
    });

    test('roomInfo 超时从 10s 延长到 20s', () {
      final body =
          stripComments(bodyOf(screen, 'void _setupRoomSync() async {'));
      expect(body, contains('Duration(seconds: 20)'));
      expect(
        body,
        isNot(contains('Duration(seconds: 10)')),
        reason: '10s 覆盖不了 1+2+4+8=15s 的退避周期',
      );
    });
  });
}
