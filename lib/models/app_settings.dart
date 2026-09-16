class AppSettings {
  final String decodeMode; // 'auto', 'hw', 'sw'
  final int bufferSizeMB;
  final bool showSyncDebug;

  const AppSettings({
    this.decodeMode = 'auto',
    this.bufferSizeMB = 64,
    this.showSyncDebug = false,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({String? decodeMode, int? bufferSizeMB, bool? showSyncDebug}) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      bufferSizeMB: bufferSizeMB ?? this.bufferSizeMB,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'bufferSizeMB': bufferSizeMB,
        'showSyncDebug': showSyncDebug,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // 兼容旧版 bool hardwareDecoding 和 hw+
    final raw = json['decodeMode'];
    String mode;
    if (raw is String && ['auto', 'hw', 'sw'].contains(raw)) {
      mode = raw;
    } else if (raw == 'hw+') {
      // hw+ 已废弃，迁移到 auto
      mode = 'auto';
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
    );
  }

  static const decodeModeLabels = {
    'auto': '智能',
    'hw': '硬解',
    'sw': '软解',
  };
}
