import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/rtm/room_info_codec.dart';

void main() {
  group('RoomInfoCodec.normalizeMediaItemId', () {
    test('占位符 `_`(首页开空房间路由) 归一为 null', () {
      expect(RoomInfoCodec.normalizeMediaItemId('_'), isNull);
    });

    test('null 与空串归一为 null', () {
      expect(RoomInfoCodec.normalizeMediaItemId(null), isNull);
      expect(RoomInfoCodec.normalizeMediaItemId(''), isNull);
    });

    test('真实条目 ID 原样返回', () {
      expect(RoomInfoCodec.normalizeMediaItemId('abc123'), 'abc123');
      expect(RoomInfoCodec.normalizeMediaItemId('himi_x'), 'himi_x');
    });
  });

  group('RoomInfoCodec.acceptsMediaItemId', () {
    test('占位符与空值拒绝构建电影条目', () {
      expect(RoomInfoCodec.acceptsMediaItemId('_'), isFalse);
      expect(RoomInfoCodec.acceptsMediaItemId(null), isFalse);
      expect(RoomInfoCodec.acceptsMediaItemId(''), isFalse);
    });

    test('真实 ID 允许构建', () {
      expect(RoomInfoCodec.acceptsMediaItemId('abc123'), isTrue);
    });
  });
}
