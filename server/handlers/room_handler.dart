import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/room_service.dart';

class RoomHandler {
  static final _roomService = RoomService();

  /// 从 URL 路径中提取房间 ID
  static String? extractId(Request request) {
    final path = request.url.path;
    // 路径格式: api/rooms/<id> 或 api/rooms/<id>/join 等
    final segments = path.split('/');
    // 查找 'rooms' 后面的 ID
    final roomsIndex = segments.indexOf('rooms');
    if (roomsIndex >= 0 && roomsIndex + 1 < segments.length) {
      return segments[roomsIndex + 1];
    }
    return null;
  }

  /// 创建房间
  static Future<Response> createRoom(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);

      final mediaItemId = data['mediaItemId'] as String?;
      final mediaItemName = data['mediaItemName'] as String?;
      final mediaItemPosterUrl = data['mediaItemPosterUrl'] as String?;
      final hostId = data['hostId'] as String? ?? 'anonymous';
      final hostName = data['hostName'] as String? ?? '匿名用户';

      if (mediaItemId == null || mediaItemName == null) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少媒体信息'}),
        );
      }

      final room = _roomService.createRoom(
        mediaItemId: mediaItemId,
        mediaItemName: mediaItemName,
        mediaItemPosterUrl: mediaItemPosterUrl,
        hostId: hostId,
        hostName: hostName,
      );

      return Response.ok(
        jsonEncode(room.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 获取房间
  static Future<Response> getRoom(Request request) async {
    try {
      final roomId = extractId(request);
      if (roomId == null || roomId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少房间 ID'}),
        );
      }

      final room = _roomService.getRoom(roomId);
      if (room == null) {
        return Response.notFound(
          jsonEncode({'error': '房间不存在'}),
        );
      }

      return Response.ok(
        jsonEncode(room.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 加入房间
  static Future<Response> joinRoom(Request request) async {
    try {
      final roomId = extractId(request);
      if (roomId == null || roomId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少房间 ID'}),
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body);

      final userId = data['userId'] as String? ?? 'anonymous';
      final userName = data['userName'] as String? ?? '匿名用户';

      final success = _roomService.joinRoom(
        roomId: roomId,
        userId: userId,
        userName: userName,
      );

      if (!success) {
        return Response.notFound(
          jsonEncode({'error': '房间不存在'}),
        );
      }

      final room = _roomService.getRoom(roomId);

      return Response.ok(
        jsonEncode(room?.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 离开房间
  static Future<Response> leaveRoom(Request request) async {
    try {
      final roomId = extractId(request);
      if (roomId == null || roomId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少房间 ID'}),
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body);

      final userId = data['userId'] as String? ?? 'anonymous';

      final success = _roomService.leaveRoom(
        roomId: roomId,
        userId: userId,
      );

      if (!success) {
        return Response.notFound(
          jsonEncode({'error': '房间不存在'}),
        );
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 删除房间
  static Future<Response> deleteRoom(Request request) async {
    try {
      final roomId = extractId(request);
      if (roomId == null || roomId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': '缺少房间 ID'}),
        );
      }

      final success = _roomService.deleteRoom(roomId);

      if (!success) {
        return Response.notFound(
          jsonEncode({'error': '房间不存在'}),
        );
      }

      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// 列出所有房间
  static Future<Response> listRooms(Request request) async {
    try {
      final rooms = _roomService.listRooms();

      return Response.ok(
        jsonEncode({'rooms': rooms.map((r) => r.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }
}
