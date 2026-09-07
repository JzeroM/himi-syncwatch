import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../config/env_config.dart';
import '../handlers/emby_handler.dart';
import '../handlers/room_handler.dart';
import '../handlers/agora_handler.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/cors_middleware.dart';

void main(List<String> args) async {
  final config = EnvConfig();
  final port = config.port;
  print('=== HimiSync 后端服务 ===');
  print('端口: $port');
  print('Emby 服务器: ${config.embyServerUrl}');
  print('声网 App ID: ${config.agoraAppId.isNotEmpty ? config.agoraAppId.substring(0, 8) + "..." : "未配置"}');

  final router = Router()
    ..get('/', _rootHandler)
    ..get('/health', _healthCheck)
    // Emby 相关
    ..post('/api/auth/emby', EmbyHandler.authenticate)
    ..get('/api/emby/items', EmbyHandler.getItems)
    ..get('/api/emby/search', EmbyHandler.search)
    ..get('/api/emby/item/<id>', EmbyHandler.getItemDetails)
    // 声网 Token
    ..post('/api/auth/agora', AgoraHandler.generateToken)
    // 房间管理
    ..post('/api/rooms', RoomHandler.createRoom)
    ..get('/api/rooms/<id>', RoomHandler.getRoom)
    ..post('/api/rooms/<id>/join', RoomHandler.joinRoom)
    ..post('/api/rooms/<id>/leave', RoomHandler.leaveRoom)
    ..delete('/api/rooms/<id>', RoomHandler.deleteRoom)
    ..get('/api/rooms', RoomHandler.listRooms);

  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(CorsMiddleware())
      .addMiddleware(AuthMiddleware())
      .addHandler(router.call);

  final server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  print('服务已启动: http://${server.address.host}:${server.port}');
}

Response _rootHandler(Request request) {
  return Response.ok(
    '{"service": "HimiSync Backend", "version": "1.0.0", "endpoints": ["/health", "/api/auth/emby", "/api/auth/agora", "/api/rooms"]}',
    headers: {'Content-Type': 'application/json'},
  );
}

Response _healthCheck(Request request) {
  return Response.ok('{"status": "ok", "service": "himi-syncwatch"}');
}
