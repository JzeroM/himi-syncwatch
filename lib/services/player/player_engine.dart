import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import '../../player_core/adapters/nipa_erika_adapter.dart';
import '../../player_core/player_data_models.dart'
    show PlayerErikaAndroidOutputMode;
import '../../player_core/adapters/nipa_mdk_adapter.dart';
import '../../player_core/adapters/nipa_media_kit_adapter.dart';
import '../../player_core/player_core_bridge.dart';
import 'player_adapter.dart';

/// 播放器引擎工厂：根据 [PlayerEngine] 创建对应 [PlayerAdapter]。
///
/// 内核选择严格按平台能力 + 用户设置，不再按 HDR/DV 内容自动路由。
/// - Android / Android TV：MDK、Erika、MediaKit
/// - iOS：Erika
/// - Windows：MDK、Erika、MediaKit
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
  /// [erikaOutputMode] 仅 Erika 使用（由用户设置/调用方传入）。
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
        return PlayerCoreBridge(NipaMdkAdapter());
      case PlayerEngine.mediaKit:
        return PlayerCoreBridge(NipaMediaKitAdapter());
      case PlayerEngine.erika:
        return PlayerCoreBridge(NipaErikaAdapter(
          androidOutputMode: PlayerErikaAndroidOutputMode.sdr,
        ));
    }
  }

  /// 当前平台支持的引擎列表。
  ///
  /// 对齐 NipaPlay 平台矩阵（HIMI 现有平台）：
  /// - Android / Android TV：MDK、Erika、MediaKit
  /// - iOS：Erika
  /// - Windows：MDK、Erika、MediaKit
  static List<PlayerEngine> supportedEngines() {
    if (kIsWeb) return const <PlayerEngine>[PlayerEngine.mdk];
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.mediaKit,
          PlayerEngine.erika,
        ];
      case TargetPlatform.iOS:
        return const <PlayerEngine>[PlayerEngine.erika];
      case TargetPlatform.windows:
        return const <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.mediaKit,
          PlayerEngine.erika,
        ];
      default:
        return const <PlayerEngine>[PlayerEngine.mdk];
    }
  }

  /// 平台默认引擎：NipaPlay 代码默认 MDK；iOS 矩阵只开放 Erika。
  static PlayerEngine defaultEngine() {
    if (kIsWeb) return PlayerEngine.mdk;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return PlayerEngine.erika;
    }
    return PlayerEngine.mdk;
  }

  /// 解析落盘内核 id；不支持时回退平台默认。
  static PlayerEngine resolveSelectedEngine(String? id) {
    final selected = PlayerEngine.fromId(id);
    return supportedEngines().contains(selected) ? selected : defaultEngine();
  }

  /// 引擎在指定平台是否可用（用于设置页 tab / 校验）。
  static bool isSupported(PlayerEngine engine) =>
      supportedEngines().contains(engine);
}
