import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../config/env_config.dart';
import '../services/emby_service.dart';

class EmbyHandler {
  static final _config = EnvConfig();
  static final _embyService = EmbyService(_config);

  /// 代理 Emby 认证
  static Future<Response> authenticate(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);

      final username = data['username'] as String?;
      final password = data['password'] as String?;
      final serverUrl = data['serverUrl'] as String?;

      if (username == null || password == null) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少用户名或密码'}),
        );
      }

      final result = await _embyService.authenticate(
        username: username,
        password: password,
        serverUrl: serverUrl,
      );

      if (result == null) {
        return Response.unauthorized(
          jsonEncode({'error': '认证失败'}),
        );
      }

      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 获取媒体列表
  static Future<Response> getItems(Request request) async {
    try {
      final parentId = request.url.queryParameters['parentId'];
      final includeItemTypes = request.url.queryParameters['includeItemTypes'];
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '20');
      final startIndex = int.tryParse(request.url.queryParameters['startIndex'] ?? '0');

      final items = await _embyService.getItems(
        parentId: parentId,
        includeItemTypes: includeItemTypes,
        limit: limit,
        startIndex: startIndex,
      );

      return Response.ok(
        jsonEncode({'Items': items}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 搜索媒体
  static Future<Response> search(Request request) async {
    try {
      final query = request.url.queryParameters['query'];
      if (query == null || query.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少搜索关键词'}),
        );
      }

      final items = await _embyService.search(query: query);

      return Response.ok(
        jsonEncode({'SearchHints': items}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 获取媒体详情
  static Future<Response> getItemDetails(Request request) async {
    try {
      // 从 URL 路径中提取 ID
      final pathSegments = request.url.pathSegments;
      final id = pathSegments.isNotEmpty ? pathSegments.last : null;
      if (id == null || id.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少媒体 ID'}),
        );
      }

      final item = await _embyService.getItemDetails(id: id);

      if (item == null) {
        return Response.notFound(
          jsonEncode({'error': '未找到媒体'}),
        );
      }

      return Response.ok(
        jsonEncode(item),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
