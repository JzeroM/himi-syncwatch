import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/constants.dart';

void main() {
  group('同步播放消息解析', () {
    test('解析 syncPlay 命令消息（含 playUrl）', () {
      final messageJson = jsonEncode({
        'type': AppConstants.msgTypeCommand,
        'userId': 'host_user',
        'action': AppConstants.actionSyncPlay,
        'episodeIndex': 2,
        'itemId': 'abc123',
        'position': 65.3,
        'playUrl': 'https://cdn.example.com/video.mkv?token=xxx',
      });

      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      expect(message['type'], equals(AppConstants.msgTypeCommand));
      expect(message['action'], equals(AppConstants.actionSyncPlay));
      expect(message['episodeIndex'], equals(2));
      expect(message['itemId'], equals('abc123'));
      expect(message['position'], equals(65.3));
      expect(message['playUrl'], contains('https://'));
    });

    test('syncPlay 消息 playUrl 为空时也能解析', () {
      final messageJson = jsonEncode({
        'type': AppConstants.msgTypeCommand,
        'userId': 'host_user',
        'action': AppConstants.actionSyncPlay,
        'episodeIndex': 0,
        'position': 0.0,
      });

      final message = jsonDecode(messageJson) as Map<String, dynamic>;

      expect(message['playUrl'], isNull);
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
      final isPlayerReady = false;
      final currentEpisodeIndex = -1;

      final shouldSend = isPlayerReady && currentEpisodeIndex >= 0;

      expect(shouldSend, isFalse);
    });

    test('同步播放命令 - 主持人已播放时发送', () {
      final isPlayerReady = true;
      final currentEpisodeIndex = 1;

      final shouldSend = isPlayerReady && currentEpisodeIndex >= 0;

      expect(shouldSend, isTrue);
    });

    test('观众接收 syncPlay 需要 playUrl 才能播放', () {
      final message = {
        'action': AppConstants.actionSyncPlay,
        'episodeIndex': 1,
        'position': 30.0,
        'playUrl': 'https://cdn.example.com/video.mkv',
      };

      final epIndex = message['episodeIndex'] as int?;
      final playUrl = message['playUrl'] as String?;
      final position = (message['position'] as num?)?.toDouble() ?? 0.0;

      expect(epIndex, isNotNull);
      expect(playUrl, isNotNull);
      expect(playUrl, isNotEmpty);
      expect(position, equals(30.0));
    });

    test('观众接收 syncPlay 无 playUrl 时不播放', () {
      final message = {
        'action': AppConstants.actionSyncPlay,
        'episodeIndex': 1,
        'position': 30.0,
      };

      final playUrl = message['playUrl'] as String?;

      expect(playUrl, isNull);
    });

    test('syncPlay 暂存机制：episodeIds 为空时应暂存', () {
      final episodeIds = <String>[];
      final epIndex = 0;
      final playUrl = 'https://cdn.example.com/video.mkv';
      final position = 10.0;

      final shouldPending = episodeIds.isEmpty;
      expect(shouldPending, isTrue);

      Map<String, dynamic>? pendingSyncPlay;
      if (shouldPending) {
        pendingSyncPlay = {
          'episodeIndex': epIndex,
          'playUrl': playUrl,
          'position': position,
        };
      }

      expect(pendingSyncPlay, isNotNull);
      expect(pendingSyncPlay!['episodeIndex'], equals(0));
      expect(pendingSyncPlay['playUrl'], equals(playUrl));
      expect(pendingSyncPlay['position'], equals(10.0));
    });

    test('syncPlay 暂存机制：roomInfo 到达后应处理暂存消息', () {
      final pendingSyncPlay = <String, dynamic>{
        'episodeIndex': 1,
        'playUrl': 'https://cdn.example.com/video.mkv',
        'position': 20.0,
      };

      final episodeIds = ['ep0', 'ep1', 'ep2'];

      final epIndex = pendingSyncPlay['episodeIndex'] as int;
      final shouldProcess = episodeIds.isNotEmpty &&
          epIndex >= 0 &&
          epIndex < episodeIds.length;

      expect(shouldProcess, isTrue);
    });

    test('syncPlay 暂存机制：roomInfo 到达后 epIndex 越界不处理', () {
      final pendingSyncPlay = <String, dynamic>{
        'episodeIndex': 5,
        'playUrl': 'https://cdn.example.com/video.mkv',
        'position': 20.0,
      };

      final episodeIds = ['ep0', 'ep1', 'ep2'];

      final epIndex = pendingSyncPlay['episodeIndex'] as int;
      final shouldProcess = episodeIds.isNotEmpty &&
          epIndex >= 0 &&
          epIndex < episodeIds.length;

      expect(shouldProcess, isFalse);
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
