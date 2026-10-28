import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// 原生播放器（全屏原生 UI + 原生 Surface）启用门控。
///
/// 满足全部条件才打开原生 UI，否则保持现有 Flutter 播放界面：
/// - 引擎 == mpv；
/// - 实际输出路径 == surface（不是请求值——原生回退到 Texture 时不启用）；
/// - 平台 == Android 或 HarmonyOS；
/// - 用户设置未关闭「原生播放器」。
class NativePlayerGating {
  const NativePlayerGating._();

  /// 支持原生 UI 的平台名（`defaultTargetPlatform.name`）。
  static const Set<String> supportedPlatforms = <String>{'android', 'ohos'};

  /// 设置项默认值：开启。
  static const bool defaultSettingEnabled = true;

  static bool isPlatformSupported(String platformName) =>
      supportedPlatforms.contains(platformName);

  /// 是否应启用原生 UI。
  ///
  /// [engine] 播放引擎名（'mpv'）；[actualVideoOutput] 实际输出路径
  /// （'surface'/'texture'，必须用实际值而非请求值）；[platformName]
  /// 为 `defaultTargetPlatform.name`。
  static bool shouldUse({
    required String engine,
    required String actualVideoOutput,
    required String platformName,
    bool settingEnabled = defaultSettingEnabled,
  }) =>
      engine == 'mpv' &&
      actualVideoOutput == 'surface' &&
      isPlatformSupported(platformName) &&
      settingEnabled;

  /// 便捷重载：直接从 `defaultTargetPlatform` 取平台（测试可注入）。
  static bool shouldUseCurrent({
    required String engine,
    required String actualVideoOutput,
    bool settingEnabled = defaultSettingEnabled,
    TargetPlatform? platform,
  }) =>
      shouldUse(
        engine: engine,
        actualVideoOutput: actualVideoOutput,
        platformName: (platform ?? defaultTargetPlatform).name,
        settingEnabled: settingEnabled,
      );

  /// 返回不满足的具体原因（用于日志诊断）；满足时返回 null。
  static String? denyReason({
    required String engine,
    required String actualVideoOutput,
    required String platformName,
    bool settingEnabled = defaultSettingEnabled,
  }) {
    if (engine != 'mpv') return 'engine=$engine 非 mpv';
    if (actualVideoOutput != 'surface') {
      return 'actualOutput=$actualVideoOutput 非 surface';
    }
    if (!isPlatformSupported(platformName)) {
      return 'platform=$platformName 不支持原生 UI';
    }
    if (!settingEnabled) return '用户设置已关闭原生播放器';
    return null;
  }
}
