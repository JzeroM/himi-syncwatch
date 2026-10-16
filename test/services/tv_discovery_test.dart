import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_discovery.dart';

/// 发一个原始 UDP 包到 [port]。
Future<void> _sendPacket(int port, Map<String, dynamic> packet) async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  s.send(utf8.encode(jsonEncode(packet)), InternetAddress.loopbackIPv4, port);
  // 等发送 flush 后关闭
  await Future<void>.delayed(Duration.zero);
  s.close();
}

void main() {
  test('协议解析：合法 tv 包解出、垃圾/版本不符返回 null', () {
    Datagram make(List<int> bytes) =>
        Datagram(Uint8List.fromList(bytes), InternetAddress.loopbackIPv4, 0);

    final ok = TvDiscoveryProtocol.tryDecode(make(
      utf8.encode(jsonEncode(TvDiscoveryProtocol.tvAnnounce(
        deviceId: 'tv_1',
        name: '客厅电视',
        httpPort: 17894,
      ))),
    ));
    expect(ok, isNotNull);
    expect(ok!['deviceId'], 'tv_1');

    expect(TvDiscoveryProtocol.tryDecode(make(utf8.encode('not json'))), isNull);
    expect(
      TvDiscoveryProtocol.tryDecode(make(utf8.encode('{"v":2,"t":"tv"}'))),
      isNull,
    );
    expect(
      TvDiscoveryProtocol.tryDecode(make(utf8.encode('{"v":1,"t":"other"}'))),
      isNull,
    );
    expect(
      TvDiscoveryProtocol.tryDecode(make(utf8.encode(jsonEncode([1, 2])))),
      isNull,
    );
  });

  test('Listener 收到 announce 包入表，ip 以数据报来源为准', () async {
    final listener = TvDiscoveryListener(port: 0);
    final emissions = <Map<String, dynamic>>[];
    final sub = listener.devicesStream.listen(emissions.add);
    addTearDown(() async {
      await listener.stop();
      listener.dispose();
      await sub.cancel();
    });

    await listener.start();
    final port = listener.boundPort!;
    await _sendPacket(port, {
      'v': 1,
      't': 'tv',
      'deviceId': 'tv_loop',
      'name': '测试TV',
      'httpPort': 12345,
      // 包内 ip 故意写错，验证以来源地址为准
      'ip': '10.255.255.255',
    });

    // 等 UDP 异步投递
    for (var i = 0; i < 50 && listener.devices.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(listener.devices, contains('tv_loop'));
    final device = listener.devices['tv_loop']!;
    expect(device.name, '测试TV');
    expect(device.httpPort, 12345);
    expect(device.ip, InternetAddress.loopbackIPv4.address);
    expect(device.baseUrl, 'http://127.0.0.1:12345');
    expect(emissions, isNotEmpty);
  });

  test('Listener 忽略非协议包', () async {
    final listener = TvDiscoveryListener(port: 0);
    addTearDown(() async {
      await listener.stop();
      listener.dispose();
    });
    await listener.start();
    final port = listener.boundPort!;

    await _sendPacket(port, {'hello': 'world'});
    await _sendPacket(port, {'v': 1, 't': 'tv', 'deviceId': ''});

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(listener.devices, isEmpty);
  });

  test('broadcastTargets 含受限广播 + 各本机 /24 定向广播', () {
    final t = TvDiscoveryProtocol.broadcastTargets(
      ['192.168.1.23', '10.0.0.5'],
    );
    expect(t, contains('255.255.255.255'));
    expect(t, contains('192.168.1.255'));
    expect(t, contains('10.0.0.255'));
  });

  test('Listener 开启广播发送且 sendQuery 可直达对端（回归：查询静默失效）',
      () async {
    // 对端接收 socket（模拟 TV 发现端口）
    final receiver =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(receiver.close);

    final listener = TvDiscoveryListener(
      port: 0,
      queryInterval: Duration.zero, // 关周期查询，手动触发
      queryTargets: {InternetAddress.loopbackIPv4.address},
      queryPort: receiver.port,
    );
    addTearDown(() async {
      await listener.stop();
      listener.dispose();
    });
    await listener.start();

    // 核心回归：start 后必须已开启 broadcastEnabled，否则 sendQuery 抛异常
    expect(listener.broadcastEnabled, isTrue,
        reason: '未开启广播能力时向广播地址发送会抛异常 → 查询静默失效');

    listener.sendQuery();

    Datagram? got;
    for (var i = 0; i < 50 && got == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      got = receiver.receive();
    }
    expect(got, isNotNull, reason: 'sendQuery 应发出 discover 包');
    final decoded = jsonDecode(utf8.decode(got!.data));
    expect(decoded['t'], 'discover');
  });

  test('expireStale 剔除超时设备并推送新表', () async {
    final listener = TvDiscoveryListener(port: 0);
    final emissions = <Map<String, dynamic>>[];
    final sub = listener.devicesStream.listen(emissions.add);
    addTearDown(() async {
      await listener.stop();
      listener.dispose();
      await sub.cancel();
    });
    await listener.start();

    await _sendPacket(listener.boundPort!, {
      'v': 1,
      't': 'tv',
      'deviceId': 'tv_stale',
      'name': '旧TV',
      'httpPort': 1,
    });
    for (var i = 0; i < 50 && listener.devices.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(listener.devices, contains('tv_stale'));

    // 把 lastSeen 拨回过期窗口外 → expireStale 应剔除
    listener.devices['tv_stale']!.lastSeen =
        DateTime.now().subtract(const Duration(minutes: 1));
    listener.expireStale();
    expect(listener.devices, isEmpty);
    // stream 投递异步：等事件循环后再断言最后一次推送是空表
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last, isEmpty);
  });

  test('Broadcaster 收到 discover 查询单播回 announce 包', () async {
    final broadcaster = TvDiscoveryBroadcaster(
      deviceId: 'tv_b',
      deviceName: '广播TV',
      httpPort: 17999,
      port: 0,
      broadcastAddress: InternetAddress.loopbackIPv4.address,
    );
    addTearDown(broadcaster.stop);
    await broadcaster.start();

    // 手机侧：独立 socket 发查询并等回包
    final phone = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(phone.close);
    phone.send(
      utf8.encode(jsonEncode(TvDiscoveryProtocol.discoverQuery)),
      InternetAddress.loopbackIPv4,
      broadcaster.boundPort!,
    );

    Datagram? reply;
    for (var i = 0; i < 50 && reply == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      reply = phone.receive();
    }
    expect(reply, isNotNull);
    final packet = TvDiscoveryProtocol.tryDecode(reply!);
    expect(packet, isNotNull);
    expect(packet!['t'], 'tv');
    expect(packet['deviceId'], 'tv_b');
    expect(packet['name'], '广播TV');
    expect(packet['httpPort'], 17999);
  });

  test('start/stop 幂等，stop 后 isRunning=false', () async {
    final broadcaster = TvDiscoveryBroadcaster(
      deviceId: 'tv_x',
      deviceName: 'X',
      httpPort: 1,
      port: 0,
      broadcastAddress: InternetAddress.loopbackIPv4.address,
    );
    await broadcaster.start();
    await broadcaster.start(); // 幂等不抛
    expect(broadcaster.isRunning, isTrue);
    await broadcaster.stop();
    await broadcaster.stop(); // 幂等不抛
    expect(broadcaster.isRunning, isFalse);
  });
}
