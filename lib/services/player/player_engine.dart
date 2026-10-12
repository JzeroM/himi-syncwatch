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
/// - erika：非 TV 且非 Linux 平台（手机真 HDR10 + 原生位图字幕/弹幕）
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

  /// 当前平台支持的引擎列表。
  ///
  /// - TV 模式：仅 MDK
  /// - 非 TV：MDK + Erika（Erika 非 web、非 Linux）；Windows 额外含 media_kit
  static List<PlayerEngine> supportedEngines({required bool tvMode}) {
    if (tvMode) return const [PlayerEngine.mdk];
    final engines = <PlayerEngine>[PlayerEngine.mdk];
    if (!kIsWeb) {
      if (defaultTargetPlatform != TargetPlatform.linux) {
        engines.add(PlayerEngine.erika);
      }
      if (defaultTargetPlatform == TargetPlatform.windows) {
        engines.add(PlayerEngine.mediaKit);
      }
    }
    return engines;
  }

  /// 引擎在指定平台是否可用（用于设置页 tab / 校验）。
  static bool isSupported(PlayerEngine engine, {required bool tvMode}) =>
      supportedEngines(tvMode: tvMode).contains(engine);
}
