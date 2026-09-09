class AppConstants {
  // Emby API
  static const String embyApiKeyHeader = 'X-Emby-Authorization';
  static const String embyTokenHeader = 'X-Emby-Token';

  // 声网 RTM
  static const int rtmHeartbeatIntervalMs = 2500;
  static const double syncThresholdMicro = 0.3;
  static const double syncThresholdMedium = 1.0;

  // 消息类型
  static const String msgTypeHeartbeat = 'heartbeat';
  static const String msgTypeCommand = 'command';
  static const String msgTypeJoin = 'join';
  static const String msgTypeLeave = 'leave';
  static const String msgTypePlayInfo = 'playInfo';
  static const String msgTypeTokenRequest = 'tokenRequest';
  static const String msgTypeTokenResponse = 'tokenResponse';
  static const String msgTypeRoomInfo = 'roomInfo';

  // 指令动作
  static const String actionPlay = 'play';
  static const String actionPause = 'pause';
  static const String actionSeek = 'seek';
  static const String actionRate = 'rate';
  static const String actionSwitchEpisode = 'switchEpisode';
  static const String actionRemoveEpisode = 'removeEpisode';
  static const String actionRequestRoomInfo = 'requestRoomInfo';
}
