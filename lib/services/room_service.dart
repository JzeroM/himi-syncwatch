import 'package:dio/dio.dart';
import 'package:himi_syncwatch/core/config.dart';
import 'package:himi_syncwatch/models/room.dart';

class RoomService {
  final Dio _dio;

  RoomService() : _dio = Dio() {
    _dio.options.baseUrl = BackendConfig.baseUrl;
  }

  void configure({required String backendUrl, String? token}) {
    _dio.options.baseUrl = backendUrl;
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<Room?> createRoom({
    required String mediaItemId,
    required String mediaItemName,
    String? mediaItemPosterUrl,
    String? hostId,
    String? hostName,
  }) async {
    try {
      final response = await _dio.post('/api/rooms', data: {
        'mediaItemId': mediaItemId,
        'mediaItemName': mediaItemName,
        'mediaItemPosterUrl': mediaItemPosterUrl,
        'hostId': hostId ?? 'anonymous',
        'hostName': hostName ?? '匿名用户',
      });
      return Room.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<Room?> getRoom(String roomId) async {
    try {
      final response = await _dio.get('/api/rooms/$roomId');
      return Room.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<Room?> joinRoom({
    required String roomId,
    required String userId,
    required String userName,
  }) async {
    try {
      final response = await _dio.post('/api/rooms/$roomId/join', data: {
        'userId': userId,
        'userName': userName,
      });
      return Room.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<bool> leaveRoom({
    required String roomId,
    required String userId,
  }) async {
    try {
      await _dio.post('/api/rooms/$roomId/leave', data: {
        'userId': userId,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteRoom(String roomId) async {
    try {
      await _dio.delete('/api/rooms/$roomId');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAgoraToken({
    required String channelName,
    required String userId,
  }) async {
    try {
      final response = await _dio.post('/api/auth/agora', data: {
        'channelName': channelName,
        'userId': userId,
      });
      return response.data;
    } catch (e) {
      return null;
    }
  }
}
