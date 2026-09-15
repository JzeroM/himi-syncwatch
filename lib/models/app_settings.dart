class AppSettings {
  final String decodeMode; // 'auto', 'hw+', 'hw', 'sw'
  final int bufferSizeMB;
  final bool showSyncDebug;
  final bool dvHwDecode; // 杜比视界硬件解码开关（默认关闭，安全优先）

  const AppSettings({
    this.decodeMode = 'auto',
    this.bufferSizeMB = 64,
    this.showSyncDebug = false,
    this.dvHwDecode = false,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({String? decodeMode, int? bufferSizeMB, bool? showSyncDebug, bool? dvHwDecode}) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      bufferSizeMB: bufferSizeMB ?? this.bufferSizeMB,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
      dvHwDecode: dvHwDecode ?? this.dvHwDecode,
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'bufferSizeMB': bufferSizeMB,
        'showSyncDebug': showSyncDebug,
        'dvHwDecode': dvHwDecode,
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
      showSyncDebug: json['showSyncDebug'] as bool? ?? false,
      dvHwDecode: json['dvHwDecode'] as bool? ?? false,
    );
  }

  static const decodeModeLabels = {
    'auto': 'Auto',
    'hw+': 'HW+',
    'hw': 'HW',
    'sw': 'SW',
  };
}
