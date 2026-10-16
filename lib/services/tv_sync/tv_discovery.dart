import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:himi_syncwatch/models/tv_device.dart';
import 'package:himi_syncwatch/services/tv_sync/multicast_lock.dart';

/// 发现协议包：`{"v":1,"t":"tv"|"discover",...}`。
/// - TV 周期广播 `t=tv`（含 deviceId/name/httpPort）
/// - 手机广播 `t=discover` 查询；TV 收到后单播回 `t=tv` 包
class TvDiscoveryProtocol {
  static const port = 17893;
  static const broadcastAddress = '255.255.255.255';

  /// 广播目标集合：受限广播 + 各本机 IPv4 的 /24 网段定向广播。
  ///
  /// 部分 AP/ROM 会丢弃 `255.255.255.255` 受限广播，但转发指向本网段的
  /// 定向广播（如 `192.168.1.255`）。dart:io 不暴露子网掩码，故按家庭
  /// 局域网最常见的 /24 推导定向地址（`a.b.c.0/24` → `a.b.c.255`）。
  static Set<String> broadcastTargets(Iterable<String> localIps) {
    final targets = <String>{broadcastAddress};
    for (final ip in localIps) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
      }
    }
    return targets;
  }

  /// 枚举本机非回环 IPv4 地址（定向广播地址推导用）。
  static Future<List<String>> localIPv4s() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final ni in interfaces)
          for (final a in ni.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> tvAnnounce({
    required String deviceId,
    required String name,
    required int httpPort,
  }) =>
      {'v': 1, 't': 'tv', 'deviceId': deviceId, 'name': name, 'httpPort': httpPort};

  static const Map<String, dynamic> discoverQuery = {'v': 1, 't': 'discover'};

  /// 解析收到的包；非本协议/自身返回 null。
  static Map<String, dynamic>? tryDecode(Datagram dg) {
    try {
      final decoded = jsonDecode(utf8.decode(dg.data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['v'] != 1) return null;
      final t = decoded['t'];
      if (t != 'tv' && t != 'discover') return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}

/// TV 端：周期广播「我在」包 + 响应手机查询（单播回包）。
///
/// 生命周期与 [TvSyncServer] 一致（tvMode 常驻）。
class TvDiscoveryBroadcaster {
  TvDiscoveryBroadcaster({
    required this.deviceId,
    required this.deviceName,
    required this.httpPort,
    this.interval = const Duration(seconds: 3),
    this.port = TvDiscoveryProtocol.port,
    this.broadcastAddress = TvDiscoveryProtocol.broadcastAddress,
    this.multicastLock = const MulticastLockService(),
  });

  final String deviceId;
  final String deviceName;
  final int httpPort;
  final Duration interval;

  /// 目标发现端口 / 广播地址（测试可注入环回地址与随机端口）。
  final int port;
  final String broadcastAddress;

  /// 组播锁（Android 保活 WiFi 接收；其余平台 no-op）。
  final MulticastLockService multicastLock;

  RawDatagramSocket? _socket;
  Timer? _timer;
  List<InternetAddress> _targets = const [];

  bool get isRunning => _socket != null;

  /// 实际绑定端口（[port] 传 0 时为系统分配，测试用）。
  int? get boundPort => _socket?.port;

  Future<void> start() async {
    if (isRunning) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port == 0 ? 0 : port,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    _socket = socket;
    await multicastLock.acquire();
    _targets = _resolveTargets(await TvDiscoveryProtocol.localIPv4s());
    socket.listen(_onEvent, onError: (_) {}, cancelOnError: false);
    _timer = Timer.periodic(interval, (_) => _broadcast());
    _broadcast();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final socket = _socket;
    _socket = null;
    socket?.close();
    await multicastLock.release();
  }

  List<InternetAddress> _resolveTargets(List<String> localIps) {
    final set = TvDiscoveryProtocol.broadcastTargets(localIps)
      ..add(broadcastAddress);
    return [for (final a in set) InternetAddress(a)];
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    final dg = socket.receive();
    if (dg == null) return;
    final packet = TvDiscoveryProtocol.tryDecode(dg);
    if (packet == null || packet['t'] != 'discover') return;
    // 单播回包（手机 sendQuery 时可直达，不用等下一周期广播）
    try {
      socket.send(
        utf8.encode(jsonEncode(_announcePacket())),
        dg.address,
        dg.port,
      );
    } catch (_) {}
  }

  Map<String, dynamic> _announcePacket() => TvDiscoveryProtocol.tvAnnounce(
        deviceId: deviceId,
        name: deviceName,
        httpPort: httpPort,
      );

  void _broadcast() {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(_announcePacket()));
    final targets = _targets.isEmpty
        ? [InternetAddress(broadcastAddress)]
        : _targets;
    for (final target in targets) {
      try {
        socket.send(data, target, socket.port);
      } catch (_) {}
    }
  }
}

/// 手机端：收听 TV 广播维护设备表 + 主动查询。
///
/// 设备表 10s 无广播过期剔除（[expireStale] 由 stream tick 驱动，
/// 或上层周期调用）。
class TvDiscoveryListener {
  TvDiscoveryListener({
    this.staleAfter = const Duration(seconds: 10),
    this.port = TvDiscoveryProtocol.port,
    this.queryInterval = const Duration(seconds: 2),
    this.multicastLock = const MulticastLockService(),
    this.queryTargets,
    this.queryPort,
  });

  final Duration staleAfter;

  /// 发现监听端口（测试可注入随机端口）。
  final int port;

  /// 主动查询重发周期（覆盖 TV 慢启动；0 表示不周期重发，测试可关）。
  final Duration queryInterval;

  /// 组播锁（Android 保活 WiFi 接收；其余平台 no-op）。
  final MulticastLockService multicastLock;

  /// 查询目标地址覆盖（测试注入环回地址）。
  final Set<String>? queryTargets;

  /// 查询目标端口覆盖（默认用 [port]，测试注入）。
  final int? queryPort;

  final _controller = StreamController<Map<String, TvDeviceInfo>>.broadcast();
  final Map<String, TvDeviceInfo> _devices = {};

  RawDatagramSocket? _socket;
  Timer? _expireTimer;
  Timer? _queryTimer;
  List<InternetAddress> _targets = const [];

  bool get isRunning => _socket != null;

  /// 实际绑定端口（[port] 传 0 时为系统分配，测试用）。
  int? get boundPort => _socket?.port;

  /// socket 是否已具备广播发送能力（回归断言用）。
  bool get broadcastEnabled => _socket?.broadcastEnabled ?? false;

  /// 设备表快照流（每次变化/过期剔除时推送）。
  Stream<Map<String, TvDeviceInfo>> get devicesStream => _controller.stream;

  Map<String, TvDeviceInfo> get devices => Map.unmodifiable(_devices);

  Future<void> start() async {
    if (isRunning) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    // 关键：不开启则 sendQuery() 向广播地址发送会抛异常、查询静默失效。
    socket.broadcastEnabled = true;
    _socket = socket;
    await multicastLock.acquire();
    _targets = _resolveTargets(await TvDiscoveryProtocol.localIPv4s());
    socket.listen(_onEvent, onError: (_) {}, cancelOnError: false);
    _expireTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => expireStale());
    if (queryInterval > Duration.zero) {
      _queryTimer = Timer.periodic(queryInterval, (_) => sendQuery());
    }
  }

  Future<void> stop() async {
    _expireTimer?.cancel();
    _expireTimer = null;
    _queryTimer?.cancel();
    _queryTimer = null;
    final socket = _socket;
    _socket = null;
    socket?.close();
    _devices.clear();
    await multicastLock.release();
  }

  List<InternetAddress> _resolveTargets(List<String> localIps) {
    final set = queryTargets ?? TvDiscoveryProtocol.broadcastTargets(localIps);
    return [for (final a in set) InternetAddress(a)];
  }

  /// 广播查询包（TV 单播回包即时入表，不用等周期广播）。
  void sendQuery() {
    final socket = _socket;
    if (socket == null) return;
    final data = utf8.encode(jsonEncode(TvDiscoveryProtocol.discoverQuery));
    final targets = _targets.isEmpty
        ? [InternetAddress(TvDiscoveryProtocol.broadcastAddress)]
        : _targets;
    final targetPort = queryPort ?? port;
    for (final target in targets) {
      try {
        socket.send(data, target, targetPort);
      } catch (_) {}
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    final dg = socket.receive();
    if (dg == null) return;
    final packet = TvDiscoveryProtocol.tryDecode(dg);
    if (packet == null || packet['t'] != 'tv') return;
    final info = TvDeviceInfo.fromJson(packet);
    // ip 以数据报来源为准，包内 ip 字段可缺省（tvAnnounce 不含 ip）
    if (info.deviceId.isEmpty || info.httpPort <= 0) return;
    info.ip = dg.address.address;
    info.lastSeen = DateTime.now();
    final isNew = !_devices.containsKey(info.deviceId) ||
        _devices[info.deviceId]!.ip != info.ip ||
        _devices[info.deviceId]!.httpPort != info.httpPort;
    _devices[info.deviceId] = info;
    if (isNew) _emit();
  }

  /// 剔除超时未广播的设备（网络切换/TV 退出后残留）。
  void expireStale() {
    final now = DateTime.now();
    final before = _devices.length;
    _devices.removeWhere(
        (_, d) => now.difference(d.lastSeen) > staleAfter);
    if (_devices.length != before) _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(Map.unmodifiable(_devices));
  }

  void dispose() {
    _controller.close();
  }
}
