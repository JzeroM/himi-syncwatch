class AppSettings {
  final String decodeMode; // 'auto', 'hw', 'sw'
  final bool showSyncDebug;
  final bool stereoDownmix;
  final String audioRenderer; // 'auto', 'aaudio', 'opensl', 'audiotrack'

  const AppSettings({
    this.decodeMode = 'auto',
    this.showSyncDebug = false,
    this.stereoDownmix = false,
    this.audioRenderer = 'OpenSL',
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({
    String? decodeMode,
    bool? showSyncDebug,
    bool? stereoDownmix,
    String? audioRenderer,
  }) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
      stereoDownmix: stereoDownmix ?? this.stereoDownmix,
      audioRenderer: audioRenderer ?? this.audioRenderer,
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'showSyncDebug': showSyncDebug,
        'stereoDownmix': stereoDownmix,
        'audioRenderer': audioRenderer,
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
      showSyncDebug: json['showSyncDebug'] as bool? ?? false,
      stereoDownmix: json['stereoDownmix'] as bool? ?? false,
      audioRenderer: json['audioRenderer'] as String? ?? 'auto',
    );
  }

  static const decodeModeLabels = {
    'auto': '智能',
    'hw': '硬解',
    'sw': '软解',
  };

  static const audioRendererLabels = {
    'auto': '自动',
    'AAudio': 'AAudio',
    'OpenSL': 'OpenSL',
    'AudioTrack': 'AudioTrack',
  };
}
