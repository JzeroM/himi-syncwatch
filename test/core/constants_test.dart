import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/constants.dart';

void main() {
  group('AppConstants - 同步播放命令', () {
    test('actionSyncPlay 常量值正确', () {
      expect(AppConstants.actionSyncPlay, equals('syncPlay'));
    });

    test('所有消息类型常量定义完整', () {
      expect(AppConstants.msgTypeHeartbeat, isNotEmpty);
      expect(AppConstants.msgTypeCommand, isNotEmpty);
      expect(AppConstants.msgTypeRoomInfo, isNotEmpty);
      expect(AppConstants.msgTypePlayInfo, isNotEmpty);
    });

    test('所有指令动作常量定义完整', () {
      expect(AppConstants.actionPlay, equals('play'));
      expect(AppConstants.actionPause, equals('pause'));
      expect(AppConstants.actionSeek, equals('seek'));
      expect(AppConstants.actionRate, equals('rate'));
      expect(AppConstants.actionSwitchEpisode, equals('switchEpisode'));
      expect(AppConstants.actionRemoveEpisode, equals('removeEpisode'));
      expect(AppConstants.actionRequestRoomInfo, equals('requestRoomInfo'));
      expect(AppConstants.actionSyncPlay, equals('syncPlay'));
    });

    test('syncPlay 命令消息格式正确', () {
      final message = {
        'type': AppConstants.msgTypeCommand,
        'userId': 'user_123',
        'action': AppConstants.actionSyncPlay,
        'episodeIndex': 0,
        'itemId': 'test_item_id',
        'position': 120.5,
      };

      expect(message['action'], equals(AppConstants.actionSyncPlay));
      expect(message['episodeIndex'], equals(0));
      expect(message['itemId'], equals('test_item_id'));
      expect(message['position'], equals(120.5));
    });
  });

  group('AppConstants - 同步阈值', () {
    test('同步阈值配置正确', () {
      expect(AppConstants.syncThresholdMicro, equals(0.3));
      expect(AppConstants.syncThresholdMedium, equals(1.0));
      expect(AppConstants.rtmHeartbeatIntervalMs, equals(2500));
    });
  });
}
