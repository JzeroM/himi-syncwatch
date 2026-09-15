class AppSettings {
  final String decodeMode; // 'auto', 'hw+', 'hw', 'sw'
  final int bufferSizeMB;
  final bool showSyncDebug;
  final bool dvHwDecode; // 杜比视界硬件解码开关（仅限 P7/P8，P5 始终 SW）
  final bool gpuNext; // gpu-next 渲染器（仅 P5 生效，配合软解修正杜比颜色，默认开启）

  const AppSettings({
    this.decodeMode = 'auto',
    this.bufferSizeMB = 64,
    this.showSyncDebug = false,
    this.dvHwDecode = false,
    this.gpuNext = true,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({String? decodeMode, int? bufferSizeMB, bool? showSyncDebug, bool? dvHwDecode, bool? gpuNext}) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      bufferSizeMB: bufferSizeMB ?? this.bufferSizeMB,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
      dvHwDecode: dvHwDecode ?? this.dvHwDecode,
      gpuNext: gpuNext ?? this.gpuNext,
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'bufferSizeMB': bufferSizeMB,
        'showSyncDebug': showSyncDebug,
        'dvHwDecode': dvHwDecode,
        'gpuNext': gpuNext,
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
      gpuNext: json['gpuNext'] as bool? ?? true,
    );
  }

  static const decodeModeLabels = {
    'auto': 'Auto',
    'hw+': 'HW+',
    'hw': 'HW',
    'sw': 'SW',
  };
}
