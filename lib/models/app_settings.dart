import 'package:flutter/foundation.dart';

class AppSettings {
  final String decodeMode; // 'auto', 'hw', 'sw'
  final bool showSyncDebug;
  final bool stereoDownmix;
  final String audioRenderer; // 'auto', 'aaudio', 'opensl', 'audiotrack'
  /// 用户是否手动设置过音频后端（用于把旧版落盘默认值 'AudioTrack'
  /// 迁移为新默认 'auto'，同时保护用户主动选择的 AudioTrack）。
  final bool audioRendererUserSet;
  final bool deepDiagnostics; // 深度诊断：抓取 mdk 内部日志以获取实测帧率
  final bool glassUi; // 液态玻璃特效开关（低端设备可关闭）
  final int? themeColor; // 主题色 ARGB（首页/壳层背景），null = 跟随默认底色
  final bool tvMode; // TV 模式：遥控器 D-pad 操控适配（Android TV/盒子）

  /// 用户是否手动设置过 TV 开关（策略 A：设置过则自动识别不再覆盖）。
  final bool tvModeUserSet;

  /// Android 视频输出通道：
  /// 'texture'      — Flutter 纹理（默认，mdk GL 渲染 → SurfaceTexture → Flutter 合成）
  /// 'tunnel'       — 纹理+直通（解码器直写 SurfaceTexture，绕过 mdk GL 渲染器）
  /// 'surfaceView'  — SurfaceView platform view（绕过 Flutter 合成，TV 全分辨率扫描输出）
  final String videoOutput;

  /// 用户是否手动设置过视频输出（设置过则 EGL 故障归一不再覆盖
  /// 手动选择，用于 texture 档对照实验与用户自主逃生）。
  final bool videoOutputUserSet;

  /// 渲染兼容模式（实验，Android）：以 mdk 全局选项启用
  /// `gl.yuv_sampler=1`（mdk wiki 注明 for android/rockchip 硬解渲染）
  /// 与 `surfacetexture.glcontext=1`（SurfaceTexture 无有效上下文时
  /// 创建 GL context），针对 RK3528 类设备视频全黑的渲染层 workaround。
  /// 全局选项仅启动时读取注入，**修改后需重启应用生效**。
  final bool renderCompatMode;

  /// EGL 故障已确认（跨重启持久化，H96_Max_RK3528 黑屏自愈）。
  ///
  /// 首次检测到 `EGL ERROR (3004)`/`No EGL config found` 时落盘 true；
  /// `_bootstrap` 启动时读取并置位 `eglFaultDetector` → 故障设备
  /// 从第二次启动起进片直接 SurfaceView 直写，全程不创建 texture GL，
  /// 根除「3004 两轮全败 → 自愈 stop 与 EGL 创建流程并发 → 偶发
  /// native crash（卡 00:00 后闪退回桌面）」。
  final bool eglFaultSeen;

  /// 生效的音频后端：AAudio/OpenSL/AudioTrack 均为 Android 专属后端
  /// （fvp 文档明确 "on android"），iOS/macOS/Linux/Windows 上设置会
  /// 导致 mdk 找不到音频渲染器（iOS 无声根因），故仅 Android 放行
  /// 用户设置，其余平台固定自动；设置项也只在 Android 展示。
  static String effectiveAudioRenderer(String setting) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return setting;
    }
    return 'auto';
  }

  /// copyWith/update 区分「未传」与「显式清空为 null」的占位值。
  static const Object unsetValue = Object();

  const AppSettings({
    this.decodeMode = 'auto',
    this.showSyncDebug = false,
    this.stereoDownmix = false,
    this.audioRenderer = 'auto',
    this.audioRendererUserSet = false,
    this.deepDiagnostics = false,
    this.glassUi = true,
    this.themeColor,
    this.tvMode = false,
    this.tvModeUserSet = false,
    this.videoOutput = 'texture',
    this.videoOutputUserSet = false,
    this.renderCompatMode = false,
    this.eglFaultSeen = false,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({
    String? decodeMode,
    bool? showSyncDebug,
    bool? stereoDownmix,
    String? audioRenderer,
    bool? audioRendererUserSet,
    bool? deepDiagnostics,
    bool? glassUi,
    bool? tvMode,
    bool? tvModeUserSet,
    String? videoOutput,
    bool? videoOutputUserSet,
    bool? renderCompatMode,
    bool? eglFaultSeen,
    Object? themeColor = unsetValue,
  }) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
      stereoDownmix: stereoDownmix ?? this.stereoDownmix,
      audioRenderer: audioRenderer ?? this.audioRenderer,
      audioRendererUserSet: audioRendererUserSet ?? this.audioRendererUserSet,
      deepDiagnostics: deepDiagnostics ?? this.deepDiagnostics,
      glassUi: glassUi ?? this.glassUi,
      tvMode: tvMode ?? this.tvMode,
      tvModeUserSet: tvModeUserSet ?? this.tvModeUserSet,
      videoOutput: videoOutput ?? this.videoOutput,
      videoOutputUserSet: videoOutputUserSet ?? this.videoOutputUserSet,
      renderCompatMode: renderCompatMode ?? this.renderCompatMode,
      eglFaultSeen: eglFaultSeen ?? this.eglFaultSeen,
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
        'audioRendererUserSet': audioRendererUserSet,
        'deepDiagnostics': deepDiagnostics,
        'glassUi': glassUi,
        'tvMode': tvMode,
        'tvModeUserSet': tvModeUserSet,
        'videoOutput': videoOutput,
        'videoOutputUserSet': videoOutputUserSet,
        'renderCompatMode': renderCompatMode,
        'eglFaultSeen': eglFaultSeen,
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
    final rawRenderer = json['audioRenderer'] as String?;
    final rendererUserSet = json['audioRendererUserSet'] as bool? ?? false;
    // 旧版默认值迁移：存盘值为 'AudioTrack' 且用户从未手动设置过
    // → 新默认 'auto'（AudioTrack ERROR 是 Android 卡顿诱因之一）。
    // 用户主动选过 AudioTrack（audioRendererUserSet=true）则保留。
    String renderer = rawRenderer ?? 'auto';
    if (!rendererUserSet && renderer == 'AudioTrack') {
      renderer = 'auto';
    }
    return AppSettings(
      decodeMode: mode,
      showSyncDebug: json['showSyncDebug'] as bool? ?? false,
      stereoDownmix: json['stereoDownmix'] as bool? ?? false,
      audioRenderer: renderer,
      audioRendererUserSet: rendererUserSet,
      deepDiagnostics: json['deepDiagnostics'] as bool? ?? false,
      glassUi: json['glassUi'] as bool? ?? true,
      tvMode: json['tvMode'] as bool? ?? false,
      // 旧数据无此字段：tvMode=true 说明用户当时手动开过 → 视为已设置，
      // 避免自动识别把用户手动关掉的 TV 模式重新打开。
      tvModeUserSet: json['tvModeUserSet'] as bool? ?? (json['tvMode'] == true),
      themeColor: json['themeColor'] as int?,
      // 旧数据无此字段 / 非法值 → 默认纹理通道
      videoOutput: const ['texture', 'tunnel', 'surfaceView']
              .contains(json['videoOutput'])
          ? json['videoOutput'] as String
          : 'texture',
      // 旧数据无此字段 → 默认 false（未手动设置）
      videoOutputUserSet: json['videoOutputUserSet'] as bool? ?? false,
      renderCompatMode: json['renderCompatMode'] as bool? ?? false,
      // 旧数据无此字段 → 默认 false（未确认故障）
      eglFaultSeen: json['eglFaultSeen'] as bool? ?? false,
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

  static const videoOutputLabels = {
    'texture': '纹理（默认）',
    'tunnel': '纹理+直通',
    'surfaceView': 'SurfaceView',
  };

  /// 生效的视频输出通道：tunnel（AMediaCodec sideband）与 SurfaceView
  /// 均为 Android 专属能力，其余平台固定纹理通道；设置项也只在
  /// Android 展示。
  static String effectiveVideoOutput(String setting) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return setting;
    }
    return 'texture';
  }

  /// EGL 故障感知的生效输出通道：设备 EGL 损坏（`eglChooseConfig`
  /// 3004，进程级持久）后纹理/直通档必走坏 GL → 黑屏，强制归一为
  /// SurfaceView 直写；**用户手动改过输出（[userSet]=true）时尊重
  /// 手动选择**（哪怕 texture 黑也由用户自行负责，可随时切回），
  /// 用于 texture 档对照实验与自主逃生；无故障时按 [setting] 归一
  /// （非 Android 固定纹理，故障分支经同一归一避免返回不存在的通道）。
  static String eglAwareVideoOutput(
    String setting, {
    required bool eglFault,
    bool userSet = false,
  }) {
    if (eglFault && !userSet) return effectiveVideoOutput('surfaceView');
    return effectiveVideoOutput(setting);
  }

  /// 是否走 fvp/video-view platform view（SurfaceView）通道。
  bool get usesSurfaceView =>
      effectiveVideoOutput(videoOutput) == 'surfaceView';

  /// 纹理通道是否启用解码器直通（tunnel）。
  bool get textureTunnel => effectiveVideoOutput(videoOutput) == 'tunnel';

  /// 渲染兼容模式生效值：相关 mdk 全局选项均为 Android/rockchip 能力，
  /// 其余平台固定关闭；设置项也只在 Android 展示。
  static bool effectiveRenderCompatMode(bool setting) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return setting;
    }
    return false;
  }
}
