import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../config/env_config.dart';
import '../services/token_service.dart';

class AuthMiddleware {
  final EnvConfig _config;
  late final TokenService _tokenService;

  // 不需要认证的路径前缀
  static final _publicPathPrefixes = [
    '/',
    '/health',
    '/api/auth',
    '/api/emby',
    '/api/rooms',
  ];

  AuthMiddleware() : _config = EnvConfig() {
    _tokenService = TokenService(_config);
  }

  Handler call(Handler innerHandler) {
    return (Request request) async {
      // 构建完整路径
      final path = '/${request.url.path}';

      // 检查是否为公开路径
      final isPublic = _publicPathPrefixes.any((p) => path.startsWith(p));
      if (isPublic) {
        return innerHandler(request);
      }

      // 检查 Authorization header
      final authHeader = request.headers['Authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response.unauthorized(
          jsonEncode({'error': '缺少认证令牌'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 验证 JWT Token
      final token = authHeader.substring(7);
      final payload = _tokenService.verifyJwtToken(token);

      if (payload == null) {
        return Response.unauthorized(
          jsonEncode({'error': '无效的认证令牌'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 将用户信息添加到 request context
      final updatedRequest = request.change(context: {
        'userId': payload['userId'],
        'username': payload['username'],
      });

      return innerHandler(updatedRequest);
    };
  }
}
