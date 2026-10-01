import 'package:flutter/foundation.dart';

class AppSettings {
  final String decodeMode; // 'auto', 'hw', 'sw'
  final bool showSyncDebug;
  final bool stereoDownmix;
  final String audioRenderer; // 'auto', 'aaudio', 'opensl', 'audiotrack'
  final bool deepDiagnostics; // 深度诊断：抓取 mdk 内部日志以获取实测帧率
  final bool glassUi; // 液态玻璃特效开关（低端设备可关闭）
  final int? themeColor; // 主题色 ARGB（首页/壳层背景），null = 跟随默认底色
  final bool tvMode; // TV 模式：遥控器 D-pad 操控适配（Android TV/盒子）

  /// 用户是否手动设置过 TV 开关（策略 A：设置过则自动识别不再覆盖）。
  final bool tvModeUserSet;

  /// 生效的音频后端：Windows 固定为自动（mdk 无 AudioTrack/OpenSL 等
  /// Android 专属后端），设置项在 Windows 上也不再展示；其余平台用用户设置。
  static String effectiveAudioRenderer(String setting) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return 'auto';
    }
    return setting;
  }

  /// copyWith/update 区分「未传」与「显式清空为 null」的占位值。
  static const Object unsetValue = Object();

  const AppSettings({
    this.decodeMode = 'auto',
    this.showSyncDebug = false,
    this.stereoDownmix = false,
    this.audioRenderer = 'AudioTrack',
    this.deepDiagnostics = false,
    this.glassUi = true,
    this.themeColor,
    this.tvMode = false,
    this.tvModeUserSet = false,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({
    String? decodeMode,
    bool? showSyncDebug,
    bool? stereoDownmix,
    String? audioRenderer,
    bool? deepDiagnostics,
    bool? glassUi,
    bool? tvMode,
    bool? tvModeUserSet,
    Object? themeColor = unsetValue,
  }) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
      stereoDownmix: stereoDownmix ?? this.stereoDownmix,
      audioRenderer: audioRenderer ?? this.audioRenderer,
      deepDiagnostics: deepDiagnostics ?? this.deepDiagnostics,
      glassUi: glassUi ?? this.glassUi,
      tvMode: tvMode ?? this.tvMode,
      tvModeUserSet: tvModeUserSet ?? this.tvModeUserSet,
      themeColor: identical(themeColor, unsetValue)
          ? this.themeColor
          : themeColor as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'showSyncDebug': showSyncDebug,
        'stereoDownmix': stereoDownmix,
        'audioRenderer': audioRenderer,
        'deepDiagnostics': deepDiagnostics,
        'glassUi': glassUi,
        'tvMode': tvMode,
        'tvModeUserSet': tvModeUserSet,
        if (themeColor != null) 'themeColor': themeColor,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final raw = json['decodeMode'];
    String mode;
    if (raw is String && ['auto', 'hw', 'sw'].contains(raw)) {
      mode = raw;
    } else if (raw == 'hw+') {
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
      audioRenderer: json['audioRenderer'] as String? ?? 'AudioTrack',
      deepDiagnostics: json['deepDiagnostics'] as bool? ?? false,
      glassUi: json['glassUi'] as bool? ?? true,
      tvMode: json['tvMode'] as bool? ?? false,
      // 旧数据无此字段：tvMode=true 说明用户当时手动开过 → 视为已设置，
      // 避免自动识别把用户手动关掉的 TV 模式重新打开。
      tvModeUserSet: json['tvModeUserSet'] as bool? ?? (json['tvMode'] == true),
      themeColor: json['themeColor'] as int?,
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
