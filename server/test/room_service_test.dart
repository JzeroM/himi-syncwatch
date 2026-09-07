import 'package:test/test.dart';
import '../services/room_service.dart';

void main() {
  group('RoomService', () {
    late RoomService roomService;

    setUp(() {
      roomService = RoomService();
    });

    test('创建房间', () {
      final room = roomService.createRoom(
        mediaItemId: 'movie-123',
        mediaItemName: '测试电影',
        mediaItemPosterUrl: 'http://example.com/poster.jpg',
        hostId: 'user-1',
        hostName: '房主用户',
      );

      expect(room.id, isNotEmpty);
      expect(room.mediaItemId, equals('movie-123'));
      expect(room.mediaItemName, equals('测试电影'));
      expect(room.hostId, equals('user-1'));
      expect(room.members.length, equals(1));
      expect(room.members.first.isHost, isTrue);
    });

    test('获取房间', () {
      final room = roomService.createRoom(
        mediaItemId: 'movie-123',
        mediaItemName: '测试电影',
        hostId: 'user-1',
        hostName: '房主用户',
      );

      final retrievedRoom = roomService.getRoom(room.id);
      expect(retrievedRoom, isNotNull);
      expect(retrievedRoom!.id, equals(room.id));
    });

    test('加入房间', () {
      final room = roomService.createRoom(
        mediaItemId: 'movie-123',
        mediaItemName: '测试电影',
        hostId: 'user-1',
        hostName: '房主用户',
      );

      final success = roomService.joinRoom(
        roomId: room.id,
        userId: 'user-2',
        userName: '观众用户',
      );

      expect(success, isTrue);

      final updatedRoom = roomService.getRoom(room.id);
      expect(updatedRoom!.members.length, equals(2));
      expect(updatedRoom.members.any((m) => m.id == 'user-2'), isTrue);
    });

    test('离开房间', () {
      final room = roomService.createRoom(
        mediaItemId: 'movie-123',
        mediaItemName: '测试电影',
        hostId: 'user-1',
        hostName: '房主用户',
      );

      roomService.joinRoom(
        roomId: room.id,
        userId: 'user-2',
        userName: '观众用户',
      );

      final success = roomService.leaveRoom(
        roomId: room.id,
        userId: 'user-2',
      );

      expect(success, isTrue);

      final updatedRoom = roomService.getRoom(room.id);
      expect(updatedRoom!.members.length, equals(1));
    });

    test('房主离开转移房主', () {
      final room = roomService.createRoom(
        mediaItemId: 'movie-123',
        mediaItemName: '测试电影',
        hostId: 'user-1',
        hostName: '房主用户',
      );

      roomService.joinRoom(
        roomId: room.id,
        userId: 'user-2',
        userName: '观众用户',
      );

      roomService.leaveRoom(
        roomId: room.id,
        userId: 'user-1',
      );

      final updatedRoom = roomService.getRoom(room.id);
      expect(updatedRoom, isNotNull);
      expect(updatedRoom!.hostId, equals('user-2'));
      expect(updatedRoom.members.first.isHost, isTrue);
    });

    test('删除房间', () {
      final room = roomService.createRoom(
        mediaItemId: 'movie-123',
        mediaItemName: '测试电影',
        hostId: 'user-1',
        hostName: '房主用户',
      );

      final success = roomService.deleteRoom(room.id);
      expect(success, isTrue);

      final deletedRoom = roomService.getRoom(room.id);
      expect(deletedRoom, isNull);
    });

    test('列出房间', () {
      roomService.createRoom(
        mediaItemId: 'movie-1',
        mediaItemName: '电影1',
        hostId: 'user-1',
        hostName: '用户1',
      );

      roomService.createRoom(
        mediaItemId: 'movie-2',
        mediaItemName: '电影2',
        hostId: 'user-2',
        hostName: '用户2',
      );

      final rooms = roomService.listRooms();
      expect(rooms.length, equals(2));
    });
  });
}
