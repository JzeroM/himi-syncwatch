class AppSettings {
  final bool hardwareDecoding;
  final int bufferSizeMB;

  const AppSettings({
    this.hardwareDecoding = true,
    this.bufferSizeMB = 32,
  });

  AppSettings copyWith({bool? hardwareDecoding, int? bufferSizeMB}) {
    return AppSettings(
      hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
      bufferSizeMB: bufferSizeMB ?? this.bufferSizeMB,
    );
  }

  Map<String, dynamic> toJson() => {
        'hardwareDecoding': hardwareDecoding,
        'bufferSizeMB': bufferSizeMB,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      hardwareDecoding: json['hardwareDecoding'] as bool? ?? true,
      bufferSizeMB: json['bufferSizeMB'] as int? ?? 64,
    );
  }
}
