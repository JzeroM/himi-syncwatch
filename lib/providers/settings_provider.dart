import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

const _storageKey = 'himi_app_settings';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  throw UnimplementedError();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  final _storage = const FlutterSecureStorage();

  /// 当前设置快照（bootstrap 在 runApp 前读取注入 fvp 全局选项，
  /// `state` 为 protected 成员，子类内访问合法）。
  AppSettings get snapshot => state;

  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw != null) {
      try {
        state = AppSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
  }

  Future<void> update({
    String? decodeMode,
    bool? showSyncDebug,
    bool? showNetworkSpeed,
    double? playbackSpeed,
    bool? stereoDownmix,
    String? audioRenderer,
    bool? deepDiagnostics,
    bool? glassUi,
    bool? tvMode,
    String? videoOutput,
    bool? renderCompatMode,
    bool? videoOutHdrAuto,
    bool? videoDecoderNoImage,
    bool? videoDecoderLowLatency,
    bool? renderDepth8,
    bool? forceSdrOutput,
    bool? renderClampHdrOnly,
    bool? eglFaultSeen,
    Object? themeColor = AppSettings.unsetValue,
    Object? appIcon = AppSettings.unsetValue,
    Object? categoryColumns = AppSettings.unsetValue,
    Object? glassBlur = AppSettings.unsetValue,
    Object? glassThickness = AppSettings.unsetValue,
    Object? glassEdgeZone = AppSettings.unsetValue,
    Object? glassSaturation = AppSettings.unsetValue,
    Object? glassChromatic = AppSettings.unsetValue,
    Object? glassLightIntensity = AppSettings.unsetValue,
    Object? glassRefractiveIndex = AppSettings.unsetValue,
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
  }) async {
    final wasTvMode = state.tvMode;
    state = state.copyWith(
      decodeMode: decodeMode,
      showSyncDebug: showSyncDebug,
      showNetworkSpeed: showNetworkSpeed,
      playbackSpeed: playbackSpeed,
      stereoDownmix: stereoDownmix,
      audioRenderer: audioRenderer,
      // 手动改动音频后端即标记「用户已设置」，旧默认值迁移不再覆盖
      audioRendererUserSet: audioRenderer != null ? true : null,
      deepDiagnostics: deepDiagnostics,
      glassUi: glassUi,
      tvMode: tvMode,
      // 手动改动 TV 开关即标记「用户已设置」，此后自动识别不再覆盖
      tvModeUserSet: tvMode != null ? true : null,
      videoOutput: videoOutput,
      // 手动改动视频输出即标记「用户已设置」，EGL 故障归一不再覆盖
      videoOutputUserSet: videoOutput != null ? true : null,
      renderCompatMode: renderCompatMode,
      videoOutHdrAuto: videoOutHdrAuto,
      videoDecoderNoImage: videoDecoderNoImage,
      videoDecoderLowLatency: videoDecoderLowLatency,
      renderDepth8: renderDepth8,
      forceSdrOutput: forceSdrOutput,
      renderClampHdrOnly: renderClampHdrOnly,
      eglFaultSeen: eglFaultSeen,
      themeColor: themeColor,
      appIcon: appIcon,
      categoryColumns: categoryColumns,
      glassBlur: glassBlur,
      glassThickness: glassThickness,
      glassEdgeZone: glassEdgeZone,
      glassSaturation: glassSaturation,
      glassChromatic: glassChromatic,
      glassLightIntensity: glassLightIntensity,
      glassRefractiveIndex: glassRefractiveIndex,
      danmakuDefaultOn: danmakuDefaultOn,
      danmakuApiUrl: danmakuApiUrl,
      danmakuScrollRows: danmakuScrollRows,
      danmakuTopRows: danmakuTopRows,
      danmakuBottomRows: danmakuBottomRows,
      danmakuBlockTop: danmakuBlockTop,
      danmakuBlockBottom: danmakuBlockBottom,
      danmakuBlockWords: danmakuBlockWords,
      danmakuLimitCount: danmakuLimitCount,
      danmakuMaxCount: danmakuMaxCount,
      danmakuSpeed: danmakuSpeed,
      danmakuFontSize: danmakuFontSize,
      danmakuOpacity: danmakuOpacity,
    );
    // 手动开启 TV 模式：立即应用 TV 专属默认（AudioTrack/SurfaceView，
    // 未手动设置过才改写）；关闭 TV 不回写（单向默认）。
    if (!wasTvMode && state.tvMode) {
      state = _applyTvDefaults(state);
    }
    await persist();
  }

  /// TV 模式专属默认（v1.1.176）：TV 模式开启时，用户从未手动设置过的
  /// 音频后端/视频输出落盘为 TV 实测更稳的组合（AudioTrack + SurfaceView）。
  /// 单向默认：关闭 TV 模式不回写（回改需手动设置）；手动设置一律优先。
  static AppSettings _applyTvDefaults(AppSettings s) {
    if (!s.tvMode) return s;
    var next = s;
    if (!next.audioRendererUserSet && next.audioRenderer != 'AudioTrack') {
      next = next.copyWith(audioRenderer: 'AudioTrack');
    }
    if (!next.videoOutputUserSet &&
        !AppSettings.isSurfaceViewMode(next.videoOutput)) {
      next = next.copyWith(videoOutput: 'surfaceView');
    }
    return next;
  }

  /// TV 自动识别（策略 A）+ TV 专属默认（v1.1.75 起 videoOutput、
  /// v1.1.176 增 audioRenderer，`tvMode` 键控）：
  /// - 检测为 TV 设备且用户从未手动设置过、当前未开启 → 静默开启 TV 模式；
  /// - TV 模式开启且用户从未手动选过音频后端/视频输出 → 落盘
  ///   AudioTrack + SurfaceView（RK3528 等盒子 texture 档 3004 全黑，
  ///   首播即出画，免黑屏自愈一轮）。走 copyWith+persist 而非 update()，
  ///   避免误标 [AppSettings.audioRendererUserSet]/[AppSettings.videoOutputUserSet]；
  ///   关闭 TV 模式不回写（单向默认，回改需手动设置）。
  ///
  /// 其余情况无任何副作用（手动设置一律优先）。
  Future<void> applyTvAutoDetection({required bool isTelevision}) async {
    var next = state;
    var changed = false;
    if (isTelevision && !next.tvModeUserSet && !next.tvMode) {
      next = next.copyWith(tvMode: true);
      changed = true;
    }
    final withDefaults = _applyTvDefaults(next);
    if (!identical(withDefaults, next)) {
      next = withDefaults;
      changed = true;
    }
    if (!changed) return;
    state = next;
    await persist();
  }

  /// 落盘当前设置（测试中可覆写以绕过平台通道）。
  Future<void> persist() async {
    await _storage.write(key: _storageKey, value: jsonEncode(state.toJson()));
  }
}
