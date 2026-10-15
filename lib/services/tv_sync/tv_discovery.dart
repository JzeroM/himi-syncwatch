import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:himi_syncwatch/models/tv_device.dart';

/// 发现协议包：`{"v":1,"t":"tv"|"discover",...}`。
/// - TV 周期广播 `t=tv`（含 deviceId/name/httpPort）
/// - 手机广播 `t=discover` 查询；TV 收到后单播回 `t=tv` 包
class TvDiscoveryProtocol {
  static const port = 17893;
  static const broadcastAddress = '255.255.255.255';

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
  });

  final String deviceId;
  final String deviceName;
  final int httpPort;
  final Duration interval;

  /// 目标发现端口 / 广播地址（测试可注入环回地址与随机端口）。
  final int port;
  final String broadcastAddress;

  RawDatagramSocket? _socket;
  Timer? _timer;

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
    try {
      socket.send(
        utf8.encode(jsonEncode(_announcePacket())),
        InternetAddress(broadcastAddress),
        socket.port,
      );
    } catch (_) {}
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
  });

  final Duration staleAfter;

  /// 发现监听端口（测试可注入随机端口）。
  final int port;

  final _controller = StreamController<Map<String, TvDeviceInfo>>.broadcast();
  final Map<String, TvDeviceInfo> _devices = {};

  RawDatagramSocket? _socket;
  Timer? _expireTimer;

  bool get isRunning => _socket != null;

  /// 实际绑定端口（[port] 传 0 时为系统分配，测试用）。
  int? get boundPort => _socket?.port;

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
    _socket = socket;
    socket.listen(_onEvent, onError: (_) {}, cancelOnError: false);
    _expireTimer = Timer.periodic(const Duration(seconds: 2), (_) => expireStale());
  }

  Future<void> stop() async {
    _expireTimer?.cancel();
    _expireTimer = null;
    final socket = _socket;
    _socket = null;
    socket?.close();
    _devices.clear();
  }

  /// 广播查询包（TV 单播回包即时入表，不用等周期广播）。
  void sendQuery() {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(
        utf8.encode(jsonEncode(TvDiscoveryProtocol.discoverQuery)),
        InternetAddress(TvDiscoveryProtocol.broadcastAddress),
        port,
      );
    } catch (_) {}
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
