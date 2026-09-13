class AppSettings {
  final String decodeMode; // 'auto', 'hw+', 'hw', 'sw'
  final int bufferSizeMB;

  const AppSettings({
    this.decodeMode = 'auto',
    this.bufferSizeMB = 64,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({String? decodeMode, int? bufferSizeMB}) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      bufferSizeMB: bufferSizeMB ?? this.bufferSizeMB,
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'bufferSizeMB': bufferSizeMB,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // 兼容旧版 bool hardwareDecoding
    final raw = json['decodeMode'];
    String mode;
    if (raw is String && ['auto', 'hw+', 'hw', 'sw'].contains(raw)) {
      mode = raw;
    } else if (raw == true || json['hardwareDecoding'] == true) {
      mode = 'auto';
    } else if (raw == false || json['hardwareDecoding'] == false) {
      mode = 'sw';
    } else {
      mode = 'auto';
    }
    return AppSettings(
      decodeMode: mode,
      bufferSizeMB: json['bufferSizeMB'] as int? ?? 64,
    );
  }

  static const decodeModeLabels = {
    'auto': 'Auto',
    'hw+': 'HW+',
    'hw': 'HW',
    'sw': 'SW',
  };
}
