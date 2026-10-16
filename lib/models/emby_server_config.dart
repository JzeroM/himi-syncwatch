import 'server_route.dart';

class EmbyServerConfig {
  final String id;
  final String serverUrl;
  final String serverName;
  final String serverId;
  final String username;
  final String? accessToken;
  final String? userId;

  /// 备用线路（有序；不含主线路，主线路恒为 [serverUrl]）。
  final List<ServerRoute> routes;

  /// 当前激活线路 URL；null = 使用主线路 [serverUrl]。
  final String? activeRouteUrl;

  /// 自动故障转移：当前线路 API 连续失败时自动切到延迟最低的可达线路。
  final bool autoFailover;

  /// STRM 直链播放：开启后优先使用服务器返回的直链地址（DirectStreamUrl /
  /// .strm 内容 URL）作为播放地址，服务器不兼容时回退代理取流。
  final bool strmDirectPlay;

  EmbyServerConfig({
    required this.id,
    required this.serverUrl,
    required this.serverName,
    required this.serverId,
    required this.username,
    this.accessToken,
    this.userId,
    this.routes = const [],
    this.activeRouteUrl,
    this.autoFailover = true,
    this.strmDirectPlay = false,
  });

  EmbyServerConfig copyWith({
    String? serverUrl,
    String? serverName,
    String? serverId,
    String? username,
    String? accessToken,
    String? userId,
    List<ServerRoute>? routes,
    String? activeRouteUrl,
    bool clearActiveRoute = false,
    bool? autoFailover,
    bool? strmDirectPlay,
  }) {
    return EmbyServerConfig(
      id: id,
      serverUrl: serverUrl ?? this.serverUrl,
      serverName: serverName ?? this.serverName,
      serverId: serverId ?? this.serverId,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      routes: routes ?? this.routes,
      activeRouteUrl:
          clearActiveRoute ? null : (activeRouteUrl ?? this.activeRouteUrl),
      autoFailover: autoFailover ?? this.autoFailover,
      strmDirectPlay: strmDirectPlay ?? this.strmDirectPlay,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverUrl': serverUrl,
        'serverName': serverName,
        'serverId': serverId,
        'username': username,
        'accessToken': accessToken,
        'userId': userId,
        'routes': routes.map((r) => r.toJson()).toList(),
        'activeRouteUrl': activeRouteUrl,
        'autoFailover': autoFailover,
        'strmDirectPlay': strmDirectPlay,
      };

  factory EmbyServerConfig.fromJson(Map<String, dynamic> json) {
    return EmbyServerConfig(
      id: json['id'] ?? '',
      serverUrl: json['serverUrl'] ?? '',
      serverName: json['serverName'] ?? '',
      serverId: json['serverId'] ?? '',
      username: json['username'] ?? '',
      accessToken: json['accessToken'],
      userId: json['userId'],
      routes: (json['routes'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ServerRoute.fromJson)
              .toList() ??
          const [],
      activeRouteUrl: json['activeRouteUrl'] as String?,
      autoFailover: json['autoFailover'] as bool? ?? true,
      strmDirectPlay: json['strmDirectPlay'] as bool? ?? false,
    );
  }

  bool get isAuthenticated => accessToken != null && userId != null;

  String get label => serverName.isNotEmpty ? serverName : serverUrl;

  /// API 基地址：激活线路 URL，未激活时主线路。
  String get effectiveUrl => activeRouteUrl ?? serverUrl;

  /// 激活的备用线路；未激活/激活的是主线路时 null。
  ServerRoute? get activeRoute {
    final u = activeRouteUrl;
    if (u == null) return null;
    for (final r in routes) {
      if (r.url == u) return r;
    }
    return null;
  }

  /// 媒体基地址（取流/字幕/图片）：激活线路是反代 → 直连主线路
  /// （省反代带宽）；直连线路或主线路 → 与 [effectiveUrl] 相同。
  String get mediaUrl {
    final route = activeRoute;
    if (route != null && route.isReverseProxy) return serverUrl;
    return effectiveUrl;
  }
}
