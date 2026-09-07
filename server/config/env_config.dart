import 'dart:io';

class EnvConfig {
  // Emby 服务器配置
  late final String embyServerUrl;
  late final String embyApiKey;

  // 声网配置（中国区）
  late final String agoraAppId;
  late final String agoraAppCertificate;

  // 服务配置
  late final int port;
  late final String jwtSecret;

  // Token 有效期
  late final int tokenExpiration;
  late final int channelTokenExpiration;

  EnvConfig() {
    // 从环境变量读取，或使用默认值
    embyServerUrl = Platform.environment['EMBY_SERVER_URL'] ?? 'http://localhost:8096';
    embyApiKey = Platform.environment['EMBY_API_KEY'] ?? '';

    agoraAppId = Platform.environment['AGORA_APP_ID'] ?? '';
    agoraAppCertificate = Platform.environment['AGORA_APP_CERTIFICATE'] ?? '';

    port = int.parse(Platform.environment['PORT'] ?? '8080');
    jwtSecret = Platform.environment['JWT_SECRET'] ?? 'himi-syncwatch-secret-key';

    tokenExpiration = int.parse(Platform.environment['TOKEN_EXPIRATION'] ?? '86400');
    channelTokenExpiration = int.parse(Platform.environment['CHANNEL_TOKEN_EXPIRATION'] ?? '86400');
  }

  bool get isEmbyConfigured => embyServerUrl.isNotEmpty;
  bool get isAgoraConfigured => agoraAppId.isNotEmpty && agoraAppCertificate.isNotEmpty;
}
