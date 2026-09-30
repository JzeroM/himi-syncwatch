import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/rtm/rtm_backend.dart';
import 'package:himi_syncwatch/services/rtm_service.dart';

class FakeRtmBackend implements RtmBackend {
  final StreamController<Map<String, dynamic>> messageController =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> presenceController =
      StreamController.broadcast();

  bool ready = true;
  bool supported = true;
  bool initialized = false;
  bool hangOnInitialize = false;
  bool loggedIn = false;
  bool loggedOut = false;
  int onlineCount = 3;
  List<String> onlineIds = const ['a', 'b', 'c'];
  String metadataDiag = 'ok,0keys';
  final Map<String, String> channelMetadata = {};
  final List<({String channel, String message})> published = [];
  String? lastInitializedAppId;
  String? lastInitializedUserId;

  @override
  bool get isSupported => supported;

  @override
  bool get isReady => ready;

  @override
  Stream<Map<String, dynamic>> get messageStream => messageController.stream;

  @override
  Stream<Map<String, dynamic>> get presenceStream =>
      presenceController.stream;

  @override
  Future<void> initialize({required String appId, required String userId}) async {
    if (hangOnInitialize) {
      // 模拟底层平台通道永久挂起
      await Completer<void>().future;
    }
    initialized = true;
    lastInitializedAppId = appId;
    lastInitializedUserId = userId;
  }

  @override
  Future<bool> login(String appId, {String? token}) async {
    loggedIn = true;
    return ready;
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  Future<bool> subscribe(String channel) async => ready;

  @override
  Future<void> unsubscribe(String channel) async {}

  @override
  Future<bool> publish(String channel, String message) async {
    published.add((channel: channel, message: message));
    return true;
  }

  @override
  Future<int> getOnlineCount(String channel) async => onlineCount;

  @override
  Future<List<String>> getOnlineIds(String channel) async => onlineIds;

  @override
  Future<String> setChannelMetadata({
    required String channelName,
    required Map<String, String> metadata,
  }) async {
    if (metadataDiag != 'ok,0keys') return metadataDiag;
    channelMetadata
      ..clear()
      ..addAll(metadata);
    return 'ok,${metadata.length}keys';
  }

  @override
  Future<(Map<String, String>, String)> getChannelMetadata(
      String channelName) async {
    return (
      Map<String, String>.from(channelMetadata),
      'ok,${channelMetadata.length}items,keys=${channelMetadata.keys.toList()}'
    );
  }

  @override
  Future<void> dispose() async {
    await messageController.close();
    await presenceController.close();
  }
}

void main() {
  late FakeRtmBackend backend;
  late RtmService service;

  setUp(() {
    backend = FakeRtmBackend();
    service = RtmService(backend: backend);
  });

  tearDown(() {
    service.dispose();
  });

  group('RtmService 门面', () {
    test('initialize/login/logout 透传给后端', () async {
      await service.initialize(appId: 'app', userId: 'u1');
      expect(backend.initialized, isTrue);
      expect(backend.lastInitializedAppId, 'app');
      expect(backend.lastInitializedUserId, 'u1');

      await service.login('app', token: 'tk');
      expect(backend.loggedIn, isTrue);

      await service.logout();
      expect(backend.loggedOut, isTrue);
    });

    test('isSupported/isConnected 透传', () {
      expect(service.isSupported, isTrue);
      expect(service.isConnected, isTrue);

      backend.supported = false;
      backend.ready = false;
      expect(service.isSupported, isFalse);
      expect(service.isConnected, isFalse);
    });

    test('后端原始消息 JSON 解码后进入 messageStream', () async {
      final received = <Map<String, dynamic>>[];
      final sub = service.messageStream.listen(received.add);

      final raw = jsonEncode({
        'type': 'heartbeat',
        'userId': 'host',
        'position': 12.5,
      });
      backend.messageController.add({'publisher': 'host', 'message': raw});
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first['type'], 'heartbeat');
      expect(received.first['position'], 12.5);

      // 非法 JSON 不进入流
      backend.messageController.add({'publisher': 'x', 'message': 'not-json'});
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));

      await sub.cancel();
    });

    test('presence 事件转发 type 与 publisher', () async {
      final received = <Map<String, dynamic>>[];
      final sub = service.presenceStream.listen(received.add);

      backend.presenceController
          .add({'type': 'remoteLeaveChannel', 'publisher': 'host'});
      await Future<void>.delayed(Duration.zero);

      expect(received.single['type'], 'remoteLeaveChannel');
      expect(received.single['publisher'], 'host');

      await sub.cancel();
    });

    test('未就绪时 sendX 全部不发布', () async {
      backend.ready = false;
      await service.sendHeartbeat(position: 1, playing: true, rate: 1);
      await service.sendCommand(action: 'play');
      await service.sendJoinLeave(action: 'join', userName: 'n');
      await service.sendRequestRoomInfo();
      expect(backend.published, isEmpty);
    });

    test('未订阅频道时 sendX 不发布', () async {
      await service.sendHeartbeat(position: 1, playing: true, rate: 1);
      expect(backend.published, isEmpty);
    });

    test('subscribe 成功后心跳按频道发布且协议字段正确', () async {
      final ok = await service.subscribe('ch1');
      expect(ok, isTrue);

      await service.sendHeartbeat(position: 63.5, playing: true, rate: 1.25);
      expect(backend.published, hasLength(1));
      expect(backend.published.single.channel, 'ch1');

      final msg = jsonDecode(backend.published.single.message)
          as Map<String, dynamic>;
      expect(msg['type'], 'heartbeat');
      expect(msg['position'], 63.5);
      expect(msg['playing'], isTrue);
      expect(msg['rate'], 1.25);
      expect(msg['ts'], isA<int>());
    });

    test('sendCommand 组装 action 与可选字段', () async {
      await service.subscribe('ch1');
      await service.sendCommand(
        action: 'seek',
        position: 99,
        episodeIndex: 2,
        itemId: 'item1',
      );

      final msg = jsonDecode(backend.published.single.message)
          as Map<String, dynamic>;
      expect(msg['type'], 'command');
      expect(msg['action'], 'seek');
      expect(msg['position'], 99);
      expect(msg['episodeIndex'], 2);
      expect(msg['itemId'], 'item1');
      expect(msg.containsKey('rate'), isFalse);
    });

    test('sendRoomInfo 发布 roomInfo 类型', () async {
      await service.sendRoomInfo(
        channelName: 'ch9',
        mediaItemId: 'm1',
        playUrl: 'http://x/play',
        episodeIds: const ['e1', 'e2'],
      );

      expect(backend.published.single.channel, 'ch9');
      final msg = jsonDecode(backend.published.single.message)
          as Map<String, dynamic>;
      expect(msg['type'], 'roomInfo');
      expect(msg['episodeIds'], ['e1', 'e2']);
    });

    test('在线人数与用户 ID 透传', () async {
      expect(await service.getOnlineUserCount('ch'), 3);
      expect(await service.getOnlineUserIds('ch'), ['a', 'b', 'c']);
    });

    test('testMetadata 通过写读返回自检结果', () async {
      final result = await service.testMetadata('ch');
      expect(result, contains('自检通过'));
    });

    test('initialize 挂起时超时兜底不永久卡死', () async {
      final hangBackend = FakeRtmBackend()
        ..hangOnInitialize = true
        ..ready = false;
      final hangService = RtmService(
        backend: hangBackend,
        initializeTimeout: const Duration(milliseconds: 50),
      );

      await hangService
          .initialize(appId: 'app', userId: 'u1')
          .timeout(const Duration(seconds: 2));

      // 超时后登录按未就绪快速失败，不会卡死
      expect(await hangService.login('app'), isFalse);

      hangService.dispose();
    });

    test('metadata 写入返回 unsupported 时 testMetadata 报写入失败', () async {
      backend.metadataDiag = 'unsupported';
      final result = await service.testMetadata('ch');
      expect(result, contains('写入失败'));
      expect(result, contains('unsupported'));
    });
  });
}
