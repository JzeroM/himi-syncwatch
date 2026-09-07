class EmbyServerConfig {
  final String id;
  final String serverUrl;
  final String serverName;
  final String serverId;
  final String username;
  final String? accessToken;
  final String? userId;

  EmbyServerConfig({
    required this.id,
    required this.serverUrl,
    required this.serverName,
    required this.serverId,
    required this.username,
    this.accessToken,
    this.userId,
  });

  EmbyServerConfig copyWith({
    String? serverUrl,
    String? serverName,
    String? serverId,
    String? username,
    String? accessToken,
    String? userId,
  }) {
    return EmbyServerConfig(
      id: id,
      serverUrl: serverUrl ?? this.serverUrl,
      serverName: serverName ?? this.serverName,
      serverId: serverId ?? this.serverId,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
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
    );
  }

  bool get isAuthenticated => accessToken != null && userId != null;

  String get label => serverName.isNotEmpty ? serverName : serverUrl;
}
