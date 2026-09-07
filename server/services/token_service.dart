import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../config/env_config.dart';

class TokenService {
  final EnvConfig _config;
  final Random _random = Random.secure();

  TokenService(this._config);

  /// 生成声网 RTM Token
  String generateAgoraToken({
    required String channelName,
    required String userId,
    int? expiration,
  }) {
    if (!_config.isAgoraConfigured) {
      throw Exception('声网配置未设置');
    }

    final expireTime = expiration ?? _config.channelTokenExpiration;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tokenExpire = now + expireTime;

    // 生成随机盐值
    final salt = _random.nextInt(256);

    // 构建 token 内容
    final tokenData = {
      'appid': _config.agoraAppId,
      'channel': channelName,
      'uid': userId,
      'expired': tokenExpire,
      'salt': salt,
    };

    // 使用 HMAC-SHA256 签名
    final key = utf8.encode(_config.agoraAppCertificate);
    final bytes = utf8.encode(jsonEncode(tokenData));
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);

    // 构建 token 字符串
    final token = base64Encode(bytes) + '.' + digest.toString();

    return token;
  }

  /// 生成 JWT Token（用于客户端认证）
  String generateJwtToken({
    required String userId,
    required String username,
    int? expiration,
  }) {
    final expireTime = expiration ?? _config.tokenExpiration;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final jwt = JWT({
      'userId': userId,
      'username': username,
      'iat': now,
      'exp': now + expireTime,
    });

    return jwt.sign(SecretKey(_config.jwtSecret));
  }

  /// 验证 JWT Token
  Map<String, dynamic>? verifyJwtToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_config.jwtSecret));
      return jwt.payload as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }
}
