import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

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
/// TV 模式仅 mdk。
class PlayerEngineFactory {
  PlayerEngineFactory._();

  /// 创建指定引擎的播放器适配器。
  ///
  /// [erikaOutputMode] 仅 Erika 使用（由内容路由结果传入）。
  static PlayerAdapter create(
    PlayerEngine engine, {
    ErikaOutputMode erikaOutputMode = ErikaOutputMode.sdr,
  }) {
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

  /// 按内容 HDR + 平台解析目标引擎（全自动路由，纯函数，便于单测）。
  ///
  /// 规则（v1.1.222）：
  /// - TV 模式：恒 mdk（不路由）
  /// - 非 HDR：恒 mdk
  /// - HDR + Android/iOS（含 iPad）：erika（outputMode 由
  ///   [resolveErikaOutputMode] 继续按内容路由）
  /// - HDR + Windows：media_kit
  /// - 其余（macOS/Linux/web HDR）：mdk 兜底
  ///
  /// [platformOverride] 仅供单测注入平台；缺省取当前平台。
  /// web 恒回 mdk（无 erika/media_kit）。
  static PlayerEngine resolveEngineForContent({
    required bool hdr,
    required bool tvMode,
    TargetPlatform? platformOverride,
  }) {
    if (tvMode || kIsWeb) return PlayerEngine.mdk;
    if (!hdr) return PlayerEngine.mdk;
    final platform = platformOverride ?? defaultTargetPlatform;
    switch (platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return PlayerEngine.erika;
      case TargetPlatform.windows:
        return PlayerEngine.mediaKit;
      default:
        return PlayerEngine.mdk;
    }
  }

  /// 当前平台支持的引擎列表。
  ///
  /// - TV 模式：仅 MDK
  /// - 非 TV：MDK + Erika（Erika 仅 android/iOS/macOS）；Windows 额外含 media_kit
  static List<PlayerEngine> supportedEngines({required bool tvMode}) {
    if (tvMode) return const [PlayerEngine.mdk];
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
  static bool isSupported(PlayerEngine engine, {required bool tvMode}) =>
      supportedEngines(tvMode: tvMode).contains(engine);
}
