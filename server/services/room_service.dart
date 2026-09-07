import 'package:uuid/uuid.dart';
import '../models/room.dart';

class RoomService {
  final Map<String, Room> _rooms = {};
  final _uuid = Uuid();

  /// 创建房间
  Room createRoom({
    required String mediaItemId,
    required String mediaItemName,
    String? mediaItemPosterUrl,
    required String hostId,
    required String hostName,
  }) {
    final roomId = _uuid.v4().substring(0, 8).toUpperCase();
    final room = Room(
      id: roomId,
      mediaItemId: mediaItemId,
      mediaItemName: mediaItemName,
      mediaItemPosterUrl: mediaItemPosterUrl,
      hostId: hostId,
      hostName: hostName,
      members: [
        RoomMember(
          id: hostId,
          name: hostName,
          isHost: true,
        ),
      ],
    );

    _rooms[roomId] = room;
    return room;
  }

  /// 获取房间
  Room? getRoom(String roomId) {
    return _rooms[roomId.toUpperCase()];
  }

  /// 加入房间
  bool joinRoom({
    required String roomId,
    required String userId,
    required String userName,
  }) {
    final room = _rooms[roomId.toUpperCase()];
    if (room == null) return false;

    // 检查用户是否已在房间
    if (room.members.any((m) => m.id == userId)) return true;

    // 添加新成员
    room.members.add(RoomMember(
      id: userId,
      name: userName,
      isHost: false,
    ));

    return true;
  }

  /// 离开房间
  bool leaveRoom({
    required String roomId,
    required String userId,
  }) {
    final room = _rooms[roomId.toUpperCase()];
    if (room == null) return false;

    room.members.removeWhere((m) => m.id == userId);

    // 如果房间为空，删除房间
    if (room.members.isEmpty) {
      _rooms.remove(roomId.toUpperCase());
      return true;
    }

    // 如果房主离开，转移房主
    if (room.hostId == userId && room.members.isNotEmpty) {
      final newHost = room.members.first;
      room.members.removeAt(0);
      room.members.insert(0, RoomMember(
        id: newHost.id,
        name: newHost.name,
        isHost: true,
      ));
      room.hostId = newHost.id;
      room.hostName = newHost.name;
    }

    return true;
  }

  /// 删除房间
  bool deleteRoom(String roomId) {
    return _rooms.remove(roomId.toUpperCase()) != null;
  }

  /// 列出所有房间
  List<Room> listRooms() {
    return _rooms.values.toList();
  }

  /// 更新房间状态
  void updateRoomState({
    required String roomId,
    bool? isPlaying,
    double? position,
    double? playbackRate,
  }) {
    final room = _rooms[roomId.toUpperCase()];
    if (room == null) return;

    if (isPlaying != null) room.isPlaying = isPlaying;
    if (position != null) room.position = position;
    if (playbackRate != null) room.playbackRate = playbackRate;
  }
}
