import 'package:flutter/foundation.dart';

class AppSettings {
  /// 存档数值归一：缺失/非法回退 [fallback]，越界钳到 [min]/[max]。
  static int _clampInt(Object? raw, int fallback, int min, int max) {
    final value = raw is num ? raw.toInt() : fallback;
    return value < min ? min : (value > max ? max : value);
  }

  static double _clampDouble(
      Object? raw, double fallback, double min, double max) {
    final value = raw is num ? raw.toDouble() : fallback;
    return value < min ? min : (value > max ? max : value);
  }

  final String decodeMode; // 'auto', 'hw', 'sw'
  final bool showSyncDebug;

  /// 播放页顶栏显示网速（真实下载速度，MB/s）。
  final bool showNetworkSpeed;

  /// 播放倍速（0.5~3.0，跨会话持久化；房间联播时由房主节奏接管）。
  final double playbackSpeed;
  final bool stereoDownmix;
  final String audioRenderer; // 'auto', 'aaudio', 'opensl', 'audiotrack'
  /// 用户是否手动设置过音频后端（用于把旧版落盘默认值 'AudioTrack'
  /// 迁移为新默认 'auto'，同时保护用户主动选择的 AudioTrack）。
  final bool audioRendererUserSet;
  final bool deepDiagnostics; // 深度诊断：抓取 mdk 内部日志以获取实测帧率
  final bool glassUi; // 液态玻璃特效开关（低端设备可关闭）

  // ── 液态玻璃可调参数（v1.1.84，null = 使用 liquid_glass_widgets 默认）──
  /// 磨砂模糊强度（逻辑像素，包默认 5）。
  final double? glassBlur;

  /// 玻璃厚度/折射深度（包默认 20）。
  final double? glassThickness;

  /// 折射范围（shader edgeZone，逻辑 px；null = 应用默认 20，
  /// 滑杆 20~24，仅 Skia standard 路径生效）。
  final double? glassEdgeZone;

  /// 玻璃内饱和增强（1.0 = 关，包默认 1.5）。
  final double? glassSaturation;

  /// 色散强度（0 = 关，包默认 0.01）。
  final double? glassChromatic;

  /// 高光强度（0~1，包默认 0.5）。
  final double? glassLightIntensity;

  /// 折射率（standard 路径弱作用于 uData3.z，观感影响很小；保留字段兼容持久化）。
  final double? glassRefractiveIndex;
  final int? themeColor; // 主题色 ARGB（首页/壳层背景），null = 跟随默认底色

  /// 应用图标 id：null = 默认（default）；'artistic'/'glass'/'neon' = 备用图标。
  /// 仅 Android/iOS 生效；写入后由 AppIconService 应用到系统。
  final String? appIcon;

  /// 分类页网格每行海报数（全平台）：null = 自动跟随屏幕，
  /// 数字 = 指定列数（屏幕放不下时按最小列宽自动压回）。
  final int? categoryColumns;
  final bool tvMode; // TV 模式：遥控器 D-pad 操控适配（Android TV/盒子）

  /// 用户是否手动设置过 TV 开关（策略 A：设置过则自动识别不再覆盖）。
  final bool tvModeUserSet;

  /// Android 视频输出通道：
  /// 'texture'      — Flutter 纹理（默认，mdk GL 渲染 → SurfaceTexture → Flutter 合成）
  /// 'tunnel'       — 纹理+直通（解码器直写 SurfaceTexture，绕过 mdk GL 渲染器）
  /// 'surfaceView'  — SurfaceView platform view（绕过 Flutter 合成，TV 全分辨率扫描输出）
  /// 'surfaceViewDirect' — SurfaceView 直写（解码器直写 ANativeWindow，绕开
  ///                  mdk GL 与 Flutter 纹理，4K HDR 高负载下最省）
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

  // ── 弹幕（v1.1.134，自定义 danmu_api 源）──

  /// 播放器弹幕默认打开（每次起播的初始开关状态）。
  final bool danmakuDefaultOn;

  /// 弹幕 API 根地址（LogVar danmu_api，可含 token 路径，如
  /// `http://192.168.1.7:9321/TOKEN`；空 = 未配置）。
  final String danmakuApiUrl;

  /// 滚动 / 顶部 / 底部弹幕行数（[danmakuRowsMin]~[danmakuRowsMax]）。
  final int danmakuScrollRows;
  final int danmakuTopRows;
  final int danmakuBottomRows;

  /// 屏蔽顶部 / 底部固定弹幕。
  final bool danmakuBlockTop;
  final bool danmakuBlockBottom;

  /// 屏蔽词（英文逗号分隔，子串匹配）。
  final String danmakuBlockWords;

  /// 限制弹幕数量开关 + 上限（等间隔采样保留）。
  final bool danmakuLimitCount;
  final int danmakuMaxCount;

  /// 弹幕速度倍率（穿屏时长 = 8s ÷ speed）。
  final double danmakuSpeed;

  /// 弹幕字号倍率（基准 25px）。
  final double danmakuFontSize;

  /// 弹幕整体透明度。
  final double danmakuOpacity;

  /// 弹幕行数范围（滑杆/存档钳制共用）。
  /// 滚动行数为「最大行数上限」：实际按画面高度自动铺满，
  /// 不超过该上限；默认给到上限即默认铺满，下压可减少密度。
  static const int danmakuRowsMin = 1;
  static const int danmakuRowsMax = 30;

  /// 速度 / 字号 / 透明度范围。
  static const double danmakuSpeedMin = 0.5;
  static const double danmakuSpeedMax = 2.0;
  static const double danmakuFontSizeMin = 0.5;
  static const double danmakuFontSizeMax = 2.0;
  static const double danmakuOpacityMin = 0.1;
  static const double danmakuOpacityMax = 1.0;

  /// 数量上限范围。
  static const int danmakuMaxCountMin = 100;
  static const int danmakuMaxCountMax = 2000;

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
    this.showNetworkSpeed = true,
    this.playbackSpeed = 1.0,
    this.stereoDownmix = false,
    this.audioRenderer = 'auto',
    this.audioRendererUserSet = false,
    this.deepDiagnostics = false,
    this.glassUi = true,
    this.glassBlur,
    this.glassThickness,
    this.glassEdgeZone,
    this.glassSaturation,
    this.glassChromatic,
    this.glassLightIntensity,
    this.glassRefractiveIndex,
    this.themeColor,
    this.appIcon,
    this.categoryColumns,
    this.tvMode = false,
    this.tvModeUserSet = false,
    this.videoOutput = 'texture',
    this.videoOutputUserSet = false,
    this.renderCompatMode = false,
    this.eglFaultSeen = false,
    this.danmakuDefaultOn = true,
    this.danmakuApiUrl = '',
    this.danmakuScrollRows = 30,
    this.danmakuTopRows = 4,
    this.danmakuBottomRows = 4,
    this.danmakuBlockTop = false,
    this.danmakuBlockBottom = false,
    this.danmakuBlockWords = '',
    this.danmakuLimitCount = false,
    this.danmakuMaxCount = 500,
    this.danmakuSpeed = 1.0,
    this.danmakuFontSize = 0.5,
    this.danmakuOpacity = 0.6,
  });

  bool get hardwareDecoding => decodeMode != 'sw';

  AppSettings copyWith({
    String? decodeMode,
    bool? showSyncDebug,
    bool? showNetworkSpeed,
    double? playbackSpeed,
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
    bool? danmakuDefaultOn,
    String? danmakuApiUrl,
    int? danmakuScrollRows,
    int? danmakuTopRows,
    int? danmakuBottomRows,
    bool? danmakuBlockTop,
    bool? danmakuBlockBottom,
    String? danmakuBlockWords,
    bool? danmakuLimitCount,
    int? danmakuMaxCount,
    double? danmakuSpeed,
    double? danmakuFontSize,
    double? danmakuOpacity,
    Object? themeColor = unsetValue,
    Object? appIcon = unsetValue,
    Object? categoryColumns = unsetValue,
    Object? glassBlur = unsetValue,
    Object? glassThickness = unsetValue,
    Object? glassEdgeZone = unsetValue,
    Object? glassSaturation = unsetValue,
    Object? glassChromatic = unsetValue,
    Object? glassLightIntensity = unsetValue,
    Object? glassRefractiveIndex = unsetValue,
  }) {
    return AppSettings(
      decodeMode: decodeMode ?? this.decodeMode,
      showSyncDebug: showSyncDebug ?? this.showSyncDebug,
      showNetworkSpeed: showNetworkSpeed ?? this.showNetworkSpeed,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
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
      danmakuDefaultOn: danmakuDefaultOn ?? this.danmakuDefaultOn,
      danmakuApiUrl: danmakuApiUrl ?? this.danmakuApiUrl,
      danmakuScrollRows: danmakuScrollRows ?? this.danmakuScrollRows,
      danmakuTopRows: danmakuTopRows ?? this.danmakuTopRows,
      danmakuBottomRows: danmakuBottomRows ?? this.danmakuBottomRows,
      danmakuBlockTop: danmakuBlockTop ?? this.danmakuBlockTop,
      danmakuBlockBottom: danmakuBlockBottom ?? this.danmakuBlockBottom,
      danmakuBlockWords: danmakuBlockWords ?? this.danmakuBlockWords,
      danmakuLimitCount: danmakuLimitCount ?? this.danmakuLimitCount,
      danmakuMaxCount: danmakuMaxCount ?? this.danmakuMaxCount,
      danmakuSpeed: danmakuSpeed ?? this.danmakuSpeed,
      danmakuFontSize: danmakuFontSize ?? this.danmakuFontSize,
      danmakuOpacity: danmakuOpacity ?? this.danmakuOpacity,
      themeColor: identical(themeColor, unsetValue)
          ? this.themeColor
          : themeColor as int?,
      appIcon:
          identical(appIcon, unsetValue) ? this.appIcon : appIcon as String?,
      categoryColumns: identical(categoryColumns, unsetValue)
          ? this.categoryColumns
          : categoryColumns as int?,
      glassBlur: identical(glassBlur, unsetValue)
          ? this.glassBlur
          : (glassBlur as num?)?.toDouble(),
      glassThickness: identical(glassThickness, unsetValue)
          ? this.glassThickness
          : (glassThickness as num?)?.toDouble(),
      glassEdgeZone: identical(glassEdgeZone, unsetValue)
          ? this.glassEdgeZone
          : (glassEdgeZone as num?)?.toDouble(),
      glassSaturation: identical(glassSaturation, unsetValue)
          ? this.glassSaturation
          : (glassSaturation as num?)?.toDouble(),
      glassChromatic: identical(glassChromatic, unsetValue)
          ? this.glassChromatic
          : (glassChromatic as num?)?.toDouble(),
      glassLightIntensity: identical(glassLightIntensity, unsetValue)
          ? this.glassLightIntensity
          : (glassLightIntensity as num?)?.toDouble(),
      glassRefractiveIndex: identical(glassRefractiveIndex, unsetValue)
          ? this.glassRefractiveIndex
          : (glassRefractiveIndex as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'decodeMode': decodeMode,
        'showSyncDebug': showSyncDebug,
        'showNetworkSpeed': showNetworkSpeed,
        'playbackSpeed': playbackSpeed,
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
        'danmakuDefaultOn': danmakuDefaultOn,
        'danmakuApiUrl': danmakuApiUrl,
        'danmakuScrollRows': danmakuScrollRows,
        'danmakuTopRows': danmakuTopRows,
        'danmakuBottomRows': danmakuBottomRows,
        'danmakuBlockTop': danmakuBlockTop,
        'danmakuBlockBottom': danmakuBlockBottom,
        'danmakuBlockWords': danmakuBlockWords,
        'danmakuLimitCount': danmakuLimitCount,
        'danmakuMaxCount': danmakuMaxCount,
        'danmakuSpeed': danmakuSpeed,
        'danmakuFontSize': danmakuFontSize,
        'danmakuOpacity': danmakuOpacity,
        if (themeColor != null) 'themeColor': themeColor,
        if (appIcon != null) 'appIcon': appIcon,
        if (categoryColumns != null) 'categoryColumns': categoryColumns,
        if (glassBlur != null) 'glassBlur': glassBlur,
        if (glassThickness != null) 'glassThickness': glassThickness,
        if (glassEdgeZone != null) 'glassEdgeZone': glassEdgeZone,
        if (glassSaturation != null) 'glassSaturation': glassSaturation,
        if (glassChromatic != null) 'glassChromatic': glassChromatic,
        if (glassLightIntensity != null)
          'glassLightIntensity': glassLightIntensity,
        if (glassRefractiveIndex != null)
          'glassRefractiveIndex': glassRefractiveIndex,
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
      showNetworkSpeed: json['showNetworkSpeed'] as bool? ?? true,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
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
      appIcon: json['appIcon'] as String?,
      // 旧数据无此字段 / 非法值 → null（自动）；存盘 int 也可能被
      // 外部写成 double，统一转 int
      categoryColumns: (json['categoryColumns'] as num?)?.toInt(),
      // 旧数据无此字段 / 非法值 → 默认纹理通道
      videoOutput: const ['texture', 'tunnel', 'surfaceView', 'surfaceViewDirect']
              .contains(json['videoOutput'])
          ? json['videoOutput'] as String
          : 'texture',
      // 旧数据无此字段 → 默认 false（未手动设置）
      videoOutputUserSet: json['videoOutputUserSet'] as bool? ?? false,
      renderCompatMode: json['renderCompatMode'] as bool? ?? false,
      // 旧数据无此字段 → 默认 false（未确认故障）
      eglFaultSeen: json['eglFaultSeen'] as bool? ?? false,
      // ── 弹幕：旧数据缺字段全部回退默认；数值按范围钳制防脏数据 ──
      danmakuDefaultOn: json['danmakuDefaultOn'] as bool? ?? true,
      danmakuApiUrl: json['danmakuApiUrl'] as String? ?? '',
      danmakuScrollRows: _clampInt(
          json['danmakuScrollRows'], 30, danmakuRowsMin, danmakuRowsMax),
      danmakuTopRows:
          _clampInt(json['danmakuTopRows'], 4, danmakuRowsMin, danmakuRowsMax),
      danmakuBottomRows: _clampInt(
          json['danmakuBottomRows'], 4, danmakuRowsMin, danmakuRowsMax),
      danmakuBlockTop: json['danmakuBlockTop'] as bool? ?? false,
      danmakuBlockBottom: json['danmakuBlockBottom'] as bool? ?? false,
      danmakuBlockWords: json['danmakuBlockWords'] as String? ?? '',
      danmakuLimitCount: json['danmakuLimitCount'] as bool? ?? false,
      danmakuMaxCount: _clampInt(
        json['danmakuMaxCount'],
        500,
        danmakuMaxCountMin,
        danmakuMaxCountMax,
      ),
      danmakuSpeed: _clampDouble(
        json['danmakuSpeed'],
        1.0,
        danmakuSpeedMin,
        danmakuSpeedMax,
      ),
      danmakuFontSize: _clampDouble(
        json['danmakuFontSize'],
        0.5,
        danmakuFontSizeMin,
        danmakuFontSizeMax,
      ),
      danmakuOpacity: _clampDouble(
        json['danmakuOpacity'],
        0.6,
        danmakuOpacityMin,
        danmakuOpacityMax,
      ),
      // 玻璃可调参数：缺失/null = 走包默认；存盘可能为 int → num 归一
      glassBlur: (json['glassBlur'] as num?)?.toDouble(),
      glassThickness: (json['glassThickness'] as num?)?.toDouble(),
      glassEdgeZone: (json['glassEdgeZone'] as num?)?.toDouble(),
      glassSaturation: (json['glassSaturation'] as num?)?.toDouble(),
      glassChromatic: (json['glassChromatic'] as num?)?.toDouble(),
      glassLightIntensity: (json['glassLightIntensity'] as num?)?.toDouble(),
      glassRefractiveIndex: (json['glassRefractiveIndex'] as num?)?.toDouble(),
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
    'texture': '纹理',
    'tunnel': '纹理+直通',
    'surfaceView': 'SurfaceView',
    'surfaceViewDirect': 'SurfaceView 直写',
  };

  /// SurfaceView 系列档位（载体=SurfaceView）：普通档与直写档。
  static bool isSurfaceViewMode(String output) =>
      output == 'surfaceView' || output == 'surfaceViewDirect';

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

  /// EGL 故障触发时应写回的视频输出档位（null = 不改写设置值）。
  ///
  /// - 用户手动改过输出（[userSet]=true）→ null，尊重手动选择
  ///   （texture 档对照实验逃生口，v1.1.72：修掉老自愈无条件把
  ///   `videoOutput` 写回 surfaceView 覆盖手动设置的 bug）；
  /// - 未手动且当前非 SurfaceView → 'surfaceView'（老自愈行为）；
  /// - 非 Android → null（无 SurfaceView 通道，不写回无效值）。
  static String? eglFaultWriteBack(String current, {required bool userSet}) {
    if (userSet) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    return current != 'surfaceView' ? 'surfaceView' : null;
  }

  /// 是否走 fvp/video-view platform view（SurfaceView）通道。
  bool get usesSurfaceView => isSurfaceViewMode(effectiveVideoOutput(videoOutput));

  /// 是否强制解码器直写 SurfaceView（真·零 Flutter 纹理/零 GL）。仅在
  /// Android 生效（其余平台 effectiveVideoOutput 归一为 texture）。
  bool get surfaceViewDirect =>
      effectiveVideoOutput(videoOutput) == 'surfaceViewDirect';

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
