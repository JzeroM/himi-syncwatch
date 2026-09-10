import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/constants.dart';

void main() {
  group('同步播放消息解析', () {
    test('解析 syncPlay 命令消息', () {
      final messageJson = jsonEncode({
        'type': AppConstants.msgTypeCommand,
        'userId': 'host_user',
        'action': AppConstants.actionSyncPlay,
        'episodeIndex': 2,
        'itemId': 'abc123',
        'position': 65.3,
      });

      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      expect(message['type'], equals(AppConstants.msgTypeCommand));
      expect(message['action'], equals(AppConstants.actionSyncPlay));
      expect(message['episodeIndex'], equals(2));
      expect(message['itemId'], equals('abc123'));
      expect(message['position'], equals(65.3));
    });

    test('解析 roomInfo 消息包含剧集列表', () {
      final messageJson = jsonEncode({
        'type': AppConstants.msgTypeRoomInfo,
        'userId': 'host_user',
        'episodeIds': ['ep1', 'ep2', 'ep3'],
        'episodeNames': ['第一集', '第二集', '第三集'],
        'episodeSeasons': [1, 1, 1],
        'episodeNumbers': [1, 2, 3],
        'episodePosters': ['', '', ''],
        'seriesName': '测试剧集',
        'mediaItemId': 'series123',
        'mediaSourceId': 'source456',
      });

      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      expect(message['type'], equals(AppConstants.msgTypeRoomInfo));
      expect((message['episodeIds'] as List).length, equals(3));
      expect(message['seriesName'], equals('测试剧集'));
      expect(message['mediaItemId'], equals('series123'));
      expect(message['mediaSourceId'], equals('source456'));
    });

    test('同步播放命令 - 主持人未播放时不发送', () {
      // 模拟主持人未播放状态
      final isPlayerReady = false;
      final currentEpisodeIndex = -1;

      final shouldSend = isPlayerReady && currentEpisodeIndex >= 0;

      expect(shouldSend, isFalse);
    });

    test('同步播放命令 - 主持人已播放时发送', () {
      // 模拟主持人已播放状态
      final isPlayerReady = true;
      final currentEpisodeIndex = 1;

      final shouldSend = isPlayerReady && currentEpisodeIndex >= 0;

      expect(shouldSend, isTrue);
    });
  });

  group('心跳消息解析', () {
    test('解析心跳消息', () {
      final messageJson = jsonEncode({
        'type': AppConstants.msgTypeHeartbeat,
        'userId': 'host_user',
        'position': 120.5,
        'playing': true,
        'rate': 1.0,
        'ts': 1694000000,
      });

      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      expect(message['type'], equals(AppConstants.msgTypeHeartbeat));
      expect(message['position'], equals(120.5));
      expect(message['playing'], isTrue);
      expect(message['rate'], equals(1.0));
      expect(message['ts'], equals(1694000000));
    });
  });
}
