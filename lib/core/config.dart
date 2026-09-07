// 声网配置（中国区）
// 请在声网控制台 (https://console.shengwang.cn) 创建项目并获取 App ID
class AgoraConfig {
  // 声网 App ID
  static const String appId = '6b74433cd9ad4213bea0b184242a92b0';

  // 声网 App Certificate（用于生成 Token）
  static const String appCertificate = 'd8cf9745d5a54bcb9886aeb6f5b3ad60';

  // Token 有效期（秒），默认 24 小时
  static const int tokenExpiration = 86400;

  // 频道 Token 有效期（秒），默认 24 小时
  static const int channelExpiration = 86400;
}

// Emby 配置
class EmbyConfig {
  // Emby API Key（可选，用于服务器端）
  static const String apiKey = String.fromEnvironment(
    'EMBY_API_KEY',
    defaultValue: '',
  );
}

// 后端服务配置
class BackendConfig {
  // 后端服务地址
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:8080',
  );
}
