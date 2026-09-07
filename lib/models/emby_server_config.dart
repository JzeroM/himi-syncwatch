class EmbyServerConfig {
  final String id;
  final String serverUrl;
  final String username;
  final String? accessToken;
  final String? userId;
  final String? displayName;

  EmbyServerConfig({
    required this.id,
    required this.serverUrl,
    required this.username,
    this.accessToken,
    this.userId,
    this.displayName,
  });

  EmbyServerConfig copyWith({
    String? serverUrl,
    String? username,
    String? accessToken,
    String? userId,
    String? displayName,
  }) {
    return EmbyServerConfig(
      id: id,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serverUrl': serverUrl,
      'username': username,
      'accessToken': accessToken,
      'userId': userId,
      'displayName': displayName,
    };
  }

  factory EmbyServerConfig.fromJson(Map<String, dynamic> json) {
    return EmbyServerConfig(
      id: json['id'] ?? '',
      serverUrl: json['serverUrl'] ?? '',
      username: json['username'] ?? '',
      accessToken: json['accessToken'],
      userId: json['userId'],
      displayName: json['displayName'],
    );
  }

  bool get isAuthenticated => accessToken != null && userId != null;

  String get label => displayName ?? serverUrl;
}
