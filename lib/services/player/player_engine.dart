import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:himi_syncwatch/models/app_settings.dart';

import 'player_adapter.dart';
import 'mdk_player_adapter.dart';
import 'media_kit_player_adapter.dart';
import 'erika_player_adapter.dart';

/// 播放器引擎工厂：根据 [PlayerEngine] 创建对应 [PlayerAdapter]。
///
/// 平台分布：
/// - mdk：全平台默认
/// - media_kit：仅 Windows（libmpv；其他平台收敛移除）
/// - erika：非 TV 平台（手机真 HDR10 + 原生位图字幕/PGS）
/// TV 模式仅 mdk。
class PlayerEngineFactory {
  PlayerEngineFactory._();

  /// 创建指定引擎的播放器适配器。
  ///
  /// [engine] 为 null 时使用 mdk（默认引擎）。
  /// [settings] 供引擎构造期需要的设置（如 Erika 输出模式）。
  static PlayerAdapter create([PlayerEngine? engine, AppSettings? settings]) {
    switch (engine ?? PlayerEngine.mdk) {
      case PlayerEngine.mdk:
        return MdkPlayerAdapter();
      case PlayerEngine.mediaKit:
        return MediaKitPlayerAdapter();
      case PlayerEngine.erika:
        return ErikaPlayerAdapter(
          outputMode: _erikaOutputMode(settings?.erikaOutputMode),
        );
    }
  }

  static ErikaOutputMode _erikaOutputMode(String? id) {
    switch (id) {
      case 'sdr':
        return ErikaOutputMode.sdr;
      case 'extendedLinear':
        return ErikaOutputMode.extendedLinear;
      default:
        return ErikaOutputMode.auto;
    }
  }

  /// 当前平台支持的引擎列表。
  ///
  /// - TV 模式：仅 MDK
  /// - 非 TV：MDK + Erika（Erika 非 web）；Windows 额外含 media_kit
  static List<PlayerEngine> supportedEngines({required bool tvMode}) {
    if (tvMode) return const [PlayerEngine.mdk];
    final engines = <PlayerEngine>[PlayerEngine.mdk];
    if (!kIsWeb) {
      // Erika：Android/iOS/macOS/Windows（首版 Linux 无预编译，不支持）
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
