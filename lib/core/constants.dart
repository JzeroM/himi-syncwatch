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

  // 指令动作
  static const String actionPlay = 'play';
  static const String actionPause = 'pause';
  static const String actionSeek = 'seek';
  static const String actionRate = 'rate';
}
