import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

/// 637：四个真机问题的防回归。
///
/// 1. **Windows 开播即闪退** —— Windows 默认走 texture（`vo=libmpv` +
///    `VideoController`），开播首帧访问失效的 render context：
///    `libmpv-2.dll` / `0xc0000005` @ `mpv_render_context_render+0x1ab7c`。
///    修复：Windows 也默认走 Surface（gpu-next + HWND）。
/// 2. **观众中途加入标题不显示/错位** —— `roomInfo` 起播不传 `epIndex`，
///    `_currentEpisodeIndex` 保持 -1 → 原生标题栏空白（安卓）/ 错位（鸿蒙）。
/// 3. **房主暂停后再播放，观众恢复很慢** —— 房主 `play` 不带位置，观众
///    只能等 5s 心跳纠正。修复：带位置 + 观众先 seek 再起播。
/// 4. **退出房间人数未减** —— 观众退出只 `unsubscribe` + `logout`，
///    没发 `leave`，presence 事件来不及投递。
void main() {
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final rtmService = File('lib/services/rtm_service.dart').readAsStringSync();

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

  group('① 观众中途加入：roomInfo 起播必须带集索引', () {
    test('sendRoomInfo 支持 episodeIndex 并写入消息体', () {
      final idx = rtmService.indexOf('Future<void> sendRoomInfo(');
      expect(idx, greaterThan(0));
      final body = rtmService.substring(idx, idx + 3000);
      expect(body, contains('int? episodeIndex,'));
      expect(body, contains("if (episodeIndex != null) 'episodeIndex': episodeIndex,"));
    });

    test('房主广播 roomInfo 时带上当前集索引', () {
      final body = stripComments(bodyOf(screen, 'Future<void> _broadcastRoomInfo() async {'));
      expect(
        body,
        contains('episodeIndex:'),
        reason: '不带则观众 _currentEpisodeIndex 保持 -1 → 标题空白',
      );
      expect(body, contains('_currentEpisodeIndex >= 0'));
    });

    test('观众从 roomInfo 起播时传入 epIndex', () {
      final body = stripComments(bodyOf(screen, 'void _handleRoomInfo('));
      expect(body, contains('resolveRoomInfoEpisodeIndex'));
      expect(body, contains('epIndex:'));
    });

    test('resolveRoomInfoEpisodeIndex：显式索引优先', () {
      const episodes = <EpisodeInfo>[
        EpisodeInfo(id: 'e0', name: 'EP1'),
        EpisodeInfo(id: 'e1', name: 'EP2'),
        EpisodeInfo(id: 'e2', name: 'EP3'),
      ];
      expect(
        PlayerScreen.resolveRoomInfoEpisodeIndex(
          explicitIndex: 2,
          itemId: 'e0',
          mediaItemId: null,
          episodes: episodes,
        ),
        2,
      );
    });

    test('resolveRoomInfoEpisodeIndex：缺失时按 itemId 反查兜底', () {
      const episodes = <EpisodeInfo>[
        EpisodeInfo(id: 'e0', name: 'EP1'),
        EpisodeInfo(id: 'e1', name: 'EP2'),
      ];
      expect(
        PlayerScreen.resolveRoomInfoEpisodeIndex(
          explicitIndex: null,
          itemId: 'e1',
          mediaItemId: null,
          episodes: episodes,
        ),
        1,
      );
      // mediaItemId 兜底（电影场景）
      expect(
        PlayerScreen.resolveRoomInfoEpisodeIndex(
          explicitIndex: null,
          itemId: null,
          mediaItemId: 'e0',
          episodes: episodes,
        ),
        0,
      );
    });

    test('resolveRoomInfoEpisodeIndex：越界/找不到返回 null', () {
      const episodes = <EpisodeInfo>[EpisodeInfo(id: 'e0', name: 'EP1')];
      expect(
        PlayerScreen.resolveRoomInfoEpisodeIndex(
          explicitIndex: 5,
          itemId: null,
          mediaItemId: null,
          episodes: episodes,
        ),
        isNull,
      );
      expect(
        PlayerScreen.resolveRoomInfoEpisodeIndex(
          explicitIndex: null,
          itemId: 'nope',
          mediaItemId: null,
          episodes: episodes,
        ),
        isNull,
      );
      expect(
        PlayerScreen.resolveRoomInfoEpisodeIndex(
          explicitIndex: null,
          itemId: null,
          mediaItemId: null,
          episodes: episodes,
        ),
        isNull,
      );
    });
  });

  group('② 房主暂停后播放：指令带进度 + 观众先 seek', () {
    test('房主发 play 时带上当前进度', () {
      final body = stripComments(bodyOf(screen, 'void _togglePlayPause() {'));
      expect(body, contains('AppConstants.actionPlay'));
      expect(
        body,
        contains('position: _player.position / 1000.0'),
        reason: '不带位置则观众只能等 5s 心跳纠正（恢复很慢）',
      );
    });

    test('观众收到 play 时先 seek 再起播', () {
      final idx = screen.indexOf('case AppConstants.actionPlay:');
      expect(idx, greaterThan(0));
      final end = screen.indexOf('case AppConstants.actionPause:', idx);
      final body = stripComments(screen.substring(idx, end));
      expect(body, contains("message['position']"));
      expect(body, contains('_player.seek('));
      // seek 必须在设置 playing 之前
      expect(body.indexOf('_player.seek('), lessThan(body.indexOf('AdapterPlaybackState.playing')));
    });
  });

  group('③ 观众退出：必须先发 leave 再退订/登出', () {
    test('退出流程包含 sendJoinLeave(leave)', () {
      final body = stripComments(bodyOf(screen, 'void dispose() {'));
      expect(body, contains("action: 'leave'"));
      expect(body, contains('sendJoinLeave'));
    });

    test('leave 在 unsubscribe 之前，并留 300ms 投递时间', () {
      final body = stripComments(bodyOf(screen, 'void dispose() {'));
      final leaveIdx = body.indexOf("action: 'leave'");
      // 640：变量名改为捕获的 `channelLeave`（不再在 dispose 末尾读 ref）。
      final unsubIdx = body.indexOf('unsubscribe(channelLeave)');
      expect(leaveIdx, greaterThan(0));
      expect(unsubIdx, greaterThan(0));
      expect(leaveIdx, lessThan(unsubIdx), reason: '必须先广播 leave');
      expect(body, contains('milliseconds: 300'));
    });

    test('仍会 logout（不能因加了 leave 而漏掉）', () {
      final body = stripComments(bodyOf(screen, 'void dispose() {'));
      expect(body, contains('logout()'));
    });
  });

  group('④ Windows 默认输出（策略层已在 mpv_output_policy_test 覆盖）', () {
    test('639：Windows 已回退 texture（637 的 Surface 会灰屏）', () {
      // 637 曾让 Windows 默认 Surface，但真机灰屏（HWND 被 Flutter 不透明
      // 窗口遮挡）。637 的崩溃（libmpv-2.dll + 0xc0000005）已在 638 通过
      // 换掉自建 libmpv 解决，与渲染模式无关，故 639 回退 texture。
      final policy = File(
        'plugins/himi_mpv_core/lib/src/mpv_output_policy.dart',
      ).readAsStringSync();
      expect(
        stripComments(policy),
        contains('if (windows && !userSet) return texture;'),
      );
    });
  });
}
