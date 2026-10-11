import 'player_adapter.dart';
import 'mdk_player_adapter.dart';
import 'media_kit_player_adapter.dart';

/// 播放器引擎工厂：根据 [PlayerEngine] 创建对应 [PlayerAdapter]。
///
/// Phase 2 起支持 media_kit；TV 模式仅 mdk（media_kit 无 TV 验证）。
class PlayerEngineFactory {
  PlayerEngineFactory._();

  /// 创建指定引擎的播放器适配器。
  ///
  /// [engine] 为 null 时使用 mdk（默认引擎）。
  static PlayerAdapter create([PlayerEngine? engine]) {
    switch (engine ?? PlayerEngine.mdk) {
      case PlayerEngine.mdk:
        return MdkPlayerAdapter();
      case PlayerEngine.mediaKit:
        return MediaKitPlayerAdapter();
    }
  }

  /// 当前平台支持的引擎列表（TV 模式下不含 media_kit）。
  static List<PlayerEngine> supportedEngines({required bool tvMode}) {
    if (tvMode) return const [PlayerEngine.mdk];
    return PlayerEngine.values;
  }
}
