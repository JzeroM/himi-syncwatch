import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import 'player_adapter.dart';
import 'mdk_player_adapter.dart';
import 'media_kit_player_adapter.dart';
import 'erika_player_adapter.dart';

/// 播放器引擎工厂：根据 [PlayerEngine] 创建对应 [PlayerAdapter]。
///
/// 平台分布：
/// - mdk：全平台默认
/// - media_kit：仅 Windows（libmpv；其他平台收敛移除）
/// - erika：android/iOS/macOS（手机真 HDR10 + 原生位图字幕/弹幕）；
///   Windows/Linux 无（Linux 无预编译；Windows 收敛为 mdk+media_kit）
///
/// TV 与手机同一套平台规则（TV 不再恒 mdk）：HDR 路由由设备能力
/// 评估结果决定（见 [resolveEngineForContent]）。
class PlayerEngineFactory {
  PlayerEngineFactory._();

  /// 仅测试用工厂覆盖：非 null 时 [create] 直接返回其产物，避免 widget 级
  /// 生命周期测试实例化真实原生引擎（mdk/media_kit/erika）。生产恒为 null。
  @visibleForTesting
  static PlayerAdapter Function(
    PlayerEngine engine, {
    ErikaOutputMode erikaOutputMode,
  })? debugCreateOverride;

  /// 创建指定引擎的播放器适配器。
  ///
  /// [erikaOutputMode] 仅 Erika 使用（由内容路由结果传入）。
  static PlayerAdapter create(
    PlayerEngine engine, {
    ErikaOutputMode erikaOutputMode = ErikaOutputMode.sdr,
  }) {
    final override = debugCreateOverride;
    if (override != null) {
      return override(engine, erikaOutputMode: erikaOutputMode);
    }
    switch (engine) {
      case PlayerEngine.mdk:
        return MdkPlayerAdapter();
      case PlayerEngine.mediaKit:
        return MediaKitPlayerAdapter();
      case PlayerEngine.erika:
        return ErikaPlayerAdapter(outputMode: erikaOutputMode);
    }
  }

  /// 按内容+HDR 解析 Erika 输出模式（纯函数，便于单测）。
  ///
  /// - 非 HDR → SDR（TextureView，省电更顺）
  /// - HDR：Android 用 extended-linear scRGB（`auto` 在 Android 默认 SDR）；
  ///   Apple/其余交给引擎/平台协商 EDR/HDR10。
  static ErikaOutputMode resolveErikaOutputMode({
    required bool hdr,
    required TargetPlatform platform,
  }) {
    if (!hdr) return ErikaOutputMode.sdr;
    switch (platform) {
      case TargetPlatform.android:
        return ErikaOutputMode.extendedLinear;
      default:
        return ErikaOutputMode.auto;
    }
  }

  /// 按内容 HDR + 设备能力解析目标引擎（全自动路由，纯函数，便于单测）。
  ///
  /// 规则（TV 与手机统一，同一套）：
  /// - web：恒 mdk
  /// - 非 HDR：恒 mdk
  /// - HDR + Android/iOS（含 iPad）且 [erikaHdrCapable]（Android 需
  ///   Vulkan + HDR 显示，能力探针未命中时保持历史默认 true）：
  ///   erika（outputMode 由 [resolveErikaOutputMode] 继续按内容路由）
  /// - HDR + Windows：media_kit
  /// - 其余（HDR + 能力不足，如无 Vulkan 的盒子）：mdk 兜底——
  ///   直写/tunnel 档可透传 HDR10，由输出层路由继续判定 tone map。
  ///
  /// [platformOverride] 仅供单测注入平台；缺省取当前平台。
  static PlayerEngine resolveEngineForContent({
    required bool hdr,
    required bool erikaHdrCapable,
    TargetPlatform? platformOverride,
  }) {
    if (kIsWeb) return PlayerEngine.mdk;
    if (!hdr) return PlayerEngine.mdk;
    final platform = platformOverride ?? defaultTargetPlatform;
    switch (platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return erikaHdrCapable ? PlayerEngine.erika : PlayerEngine.mdk;
      case TargetPlatform.windows:
        return PlayerEngine.mediaKit;
      default:
        return PlayerEngine.mdk;
    }
  }

  /// 当前平台支持的引擎列表（TV 与手机一致）。
  ///
  /// MDK + Erika（Erika 仅 android/iOS/macOS）；Windows 额外含 media_kit。
  static List<PlayerEngine> supportedEngines() {
    final engines = <PlayerEngine>[PlayerEngine.mdk];
    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          engines.add(PlayerEngine.erika);
          break;
        case TargetPlatform.windows:
          engines.add(PlayerEngine.mediaKit);
          break;
        default:
          break;
      }
    }
    return engines;
  }

  /// 引擎在指定平台是否可用（用于设置页 tab / 校验）。
  static bool isSupported(PlayerEngine engine) =>
      supportedEngines().contains(engine);
}
