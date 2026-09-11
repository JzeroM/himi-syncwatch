class AppSettings {
  final bool hardwareDecoding;

  const AppSettings({this.hardwareDecoding = true});

  AppSettings copyWith({bool? hardwareDecoding}) {
    return AppSettings(
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
    );
  }

  Map<String, dynamic> toJson() => {
        'hardwareDecoding': hardwareDecoding,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      hardwareDecoding: json['hardwareDecoding'] as bool? ?? true,
    );
  }
}
