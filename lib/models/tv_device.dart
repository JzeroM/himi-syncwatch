/// 局域网发现的 TV 设备（UDP 广播包解析结果）。
class TvDeviceInfo {
  TvDeviceInfo({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.httpPort,
  });

  final String deviceId;
  final String name;

  /// IP 以数据报来源地址为准（广播包内 IP 可能是多网卡歧义值），可覆写。
  String ip;

  final int httpPort;

  /// 最后一次收到广播的时间（过期剔除用）。
  DateTime lastSeen = DateTime.now();

  /// `http://ip:port`（手机配对/推送基地址）。
  String get baseUrl => 'http://$ip:$httpPort';

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'ip': ip,
        'httpPort': httpPort,
      };

  factory TvDeviceInfo.fromJson(Map<String, dynamic> json) {
    return TvDeviceInfo(
      deviceId: json['deviceId'] as String? ?? '',
      name: json['name'] as String? ?? 'HIMI TV',
      ip: json['ip'] as String? ?? '',
      httpPort: json['httpPort'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TvDeviceInfo && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

/// 手机端已配对的 TV（secure storage 持久化；token 为 TV 端签发）。
class PairedTv {
  const PairedTv({
    required this.deviceId,
    required this.name,
    required this.ip,
    required this.port,
    required this.token,
  });

  final String deviceId;
  final String name;
  final String ip;
  final int port;
  final String token;

  String get baseUrl => 'http://$ip:$port';

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'ip': ip,
        'port': port,
        'token': token,
      };

  factory PairedTv.fromJson(Map<String, dynamic> json) {
    return PairedTv(
      deviceId: json['deviceId'] as String? ?? '',
      name: json['name'] as String? ?? 'HIMI TV',
      ip: json['ip'] as String? ?? '',
      port: json['port'] as int? ?? 0,
      token: json['token'] as String? ?? '',
    );
  }

  /// 从发现结果 + token 构造（配对成功落库用）。
  factory PairedTv.fromDevice(TvDeviceInfo device, String token) {
    return PairedTv(
      deviceId: device.deviceId,
      name: device.name,
      ip: device.ip,
      port: device.httpPort,
      token: token,
    );
  }
}
