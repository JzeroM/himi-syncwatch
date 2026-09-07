class EmbyServerConfig {
  final String serverUrl;
  final String username;
  final String? accessToken;
  final String? userId;

  EmbyServerConfig({
    required this.serverUrl,
    required this.username,
    this.accessToken,
    this.userId,
  });

  EmbyServerConfig copyWith({
    String? serverUrl,
    String? username,
    String? accessToken,
    String? userId,
  }) {
    return EmbyServerConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      userId: userId ?? this.userId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'accessToken': accessToken,
      'userId': userId,
    };
  }

  factory EmbyServerConfig.fromJson(Map<String, dynamic> json) {
    return EmbyServerConfig(
      serverUrl: json['serverUrl'] ?? '',
      username: json['username'] ?? '',
      accessToken: json['accessToken'],
      userId: json['userId'],
    );
  }

  bool get isAuthenticated => accessToken != null && userId != null;
}
