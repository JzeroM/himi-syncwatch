import 'player_adapter.dart';
import 'mdk_player_adapter.dart';

/// 播放器引擎工厂：根据 [PlayerEngine] 创建对应 [PlayerAdapter]。
///
/// Phase 2 将在此注册 MediaKitPlayerAdapter；当前仅 mdk 可用。
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
        // Phase 2 实现 MediaKitPlayerAdapter；当前回退 mdk
        return MdkPlayerAdapter();
    }
  }

  /// 当前平台支持的引擎列表（TV 模式下不含 media_kit）。
  static List<PlayerEngine> supportedEngines({required bool tvMode}) {
    if (tvMode) return const [PlayerEngine.mdk];
    return PlayerEngine.values;
  }
}
