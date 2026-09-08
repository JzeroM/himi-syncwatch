class AgoraConfigModel {
  final String appId;
  final String appCertificate;

  const AgoraConfigModel({
    required this.appId,
    required this.appCertificate,
  });

  bool get isConfigured => appId.isNotEmpty && appCertificate.isNotEmpty;

  AgoraConfigModel copyWith({
    String? appId,
    String? appCertificate,
  }) {
    return AgoraConfigModel(
      appId: appId ?? this.appId,
      appCertificate: appCertificate ?? this.appCertificate,
    );
  }

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'appCertificate': appCertificate,
      };

  factory AgoraConfigModel.fromJson(Map<String, dynamic> json) {
    return AgoraConfigModel(
      appId: json['appId'] ?? '',
      appCertificate: json['appCertificate'] ?? '',
    );
  }
}
