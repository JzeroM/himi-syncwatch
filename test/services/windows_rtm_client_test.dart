import 'package:agora_rtm/agora_rtm.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/rtm/windows_rtm_backend.dart';
import 'package:himi_windows_rtm/himi_windows_rtm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('himi_windows_rtm');
  const eventChannel = EventChannel('himi_windows_rtm/events');

  MockStreamHandlerEventSink? eventSink;
  var failNextWithPlatformException = false;

  Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() async {
    failNextWithPlatformException = false;
    // 重建静态事件订阅：setMockStreamHandler 的底层 controller 每个
    // 测试结束都会被 close，跨测试复用 sink 会抛 Bad state
    await WindowsRtmClient.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      if (failNextWithPlatformException) {
        throw PlatformException(code: 'channel_error', message: '通道错误');
      }
      switch (call.method) {
        case 'initialize':
          return true;
        case 'login':
          return {'rid': 42};
        case 'subscribe':
          return {'rid': 43};
        case 'getOnlineUsers':
          return {'rid': 77};
        case 'setChannelMetadata':
          return {'rid': 88};
        case 'getChannelMetadata':
          return {'rid': 89};
        case 'logout':
        case 'unsubscribe':
        case 'release':
          return true;
        case 'publish':
          return {'rid': 999};
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          eventSink = sink;
        },
        onCancel: (arguments) {
          eventSink = null;
        },
      ),
    );
  });

  group('WindowsRtmClient 通道协议', () {
    test('login 按 rid 关联 result 事件后返回 true', () async {
      final future = WindowsRtmClient.login(token: 'tk');
      await pumpEvents();
      expect(eventSink, isNotNull);
      eventSink!.success({
        'event': 'result',
        'requestId': 42,
        'method': 'login',
        'ok': true,
        'reason': 'ok',
      });
      expect(await future, isTrue);
    });

    test('result 事件 ok=false 时返回 false', () async {
      final future = WindowsRtmClient.login(token: 'tk');
      await pumpEvents();
      eventSink!.success({
        'event': 'result',
        'requestId': 42,
        'method': 'login',
        'ok': false,
        'reason': '错误码 1',
      });
      expect(await future, isFalse);
    });

    test('等待超时返回失败且带超时原因', () async {
      final result = await WindowsRtmClient.invokeForResult(
        'subscribe',
        {'channel': 'c'},
        const Duration(milliseconds: 50),
      );
      expect(result['ok'], isFalse);
      expect('${result['reason']}', contains('超时'));
    });

    test('通道抛 PlatformException 时返回失败', () async {
      failNextWithPlatformException = true;
      final result = await WindowsRtmClient.invokeForResult('login', {'token': ''});
      expect(result['ok'], isFalse);
      expect(result['reason'], '通道错误');
    });

    test('rid=0（客户端未就绪）直接失败', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'login') return {'rid': 0};
        return null;
      });
      final result = await WindowsRtmClient.invokeForResult('login', {'token': ''});
      expect(result['ok'], isFalse);
      expect(result['reason'], '客户端未就绪');
    });

    test('publish fire-and-forget 成功返回 true', () async {
      expect(await WindowsRtmClient.publish('ch', '{"type":"heartbeat"}'), isTrue);
    });
  });

  group('WindowsRtmBackend', () {
    test('presence 事件 int type 映射 RtmPresenceEventType 枚举', () async {
      final backend = WindowsRtmBackend();
      await backend.initialize(appId: 'app', userId: 'u1');
      expect(backend.isReady, isTrue);
      await pumpEvents();

      final received = <Map<String, dynamic>>[];
      final sub = backend.presenceStream.listen(received.add);
      eventSink!.success({
        'event': 'presence',
        'type': 4,
        'publisher': 'host',
      });
      await pumpEvents();

      expect(received, hasLength(1));
      expect(received.single['type'], RtmPresenceEventType.remoteLeaveChannel);
      expect(received.single['publisher'], 'host');

      await sub.cancel();
      await backend.dispose();
    });

    test('message 事件进入 messageStream', () async {
      final backend = WindowsRtmBackend();
      await backend.initialize(appId: 'app', userId: 'u1');
      await pumpEvents();

      final received = <Map<String, dynamic>>[];
      final sub = backend.messageStream.listen(received.add);
      eventSink!.success({
        'event': 'message',
        'publisher': 'host',
        'message': '{"type":"command","action":"play"}',
      });
      await pumpEvents();

      expect(received.single['publisher'], 'host');
      expect(received.single['message'], contains('command'));

      await sub.cancel();
      await backend.dispose();
    });

    test('在线人数经 getOnlineUsers 结果解析', () async {
      final backend = WindowsRtmBackend();
      await backend.initialize(appId: 'app', userId: 'u1');
      await pumpEvents();

      final future = backend.getOnlineCount('ch');
      await pumpEvents();
      eventSink!.success({
        'event': 'result',
        'requestId': 77,
        'method': 'getOnlineUsers',
        'ok': true,
        'reason': 'ok',
        'count': 5,
        'userIds': ['a', 'b'],
      });
      expect(await future, 5);

      await backend.dispose();
    });

    test('未就绪时各操作快速失败', () async {
      final backend = WindowsRtmBackend();
      expect(backend.isReady, isFalse);
      expect(await backend.login('app'), isFalse);
      expect(await backend.subscribe('ch'), isFalse);
      expect(await backend.getOnlineCount('ch'), 0);
      expect(await backend.publish('ch', 'x'), isFalse);
      await backend.dispose();
    });
  });
}
