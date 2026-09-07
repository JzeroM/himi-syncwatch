import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../config/env_config.dart';
import '../services/token_service.dart';

class AgoraHandler {
  static final _config = EnvConfig();
  static final _tokenService = TokenService(_config);

  /// 生成声网 Token
  static Future<Response> generateToken(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);

      final channelName = data['channelName'] as String?;
      final userId = data['userId'] as String?;

      if (channelName == null || userId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少频道名或用户 ID'}),
        );
      }

      if (!_config.isAgoraConfigured) {
        return Response.internalServerError(
          body: jsonEncode({'error': '声网配置未设置'}),
        );
      }

      final token = _tokenService.generateAgoraToken(
        channelName: channelName,
        userId: userId,
      );

      return Response.ok(
        jsonEncode({
          'token': token,
          'appId': _config.agoraAppId,
          'channelName': channelName,
          'userId': userId,
          'expiration': _config.channelTokenExpiration,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
