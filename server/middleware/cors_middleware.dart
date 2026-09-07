import 'package:shelf/shelf.dart';

class CorsMiddleware {
  Handler call(Handler innerHandler) {
    return (Request request) async {
      // 处理预检请求
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Emby-Token',
          'Access-Control-Max-Age': '86400',
        });
      }

      // 处理其他请求
      final response = await innerHandler(request);

      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Emby-Token',
      });
    };
  }
}
