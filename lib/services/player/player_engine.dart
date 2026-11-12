import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import '../../player_core/adapters/nipa_erika_adapter.dart';
import '../../player_core/player_data_models.dart'
    show PlayerErikaAndroidOutputMode;
import '../../player_core/adapters/nipa_mdk_adapter.dart';
import '../../player_core/adapters/nipa_media_kit_adapter.dart';
import '../../player_core/player_core_bridge.dart';
import 'mpv_player_adapter.dart';
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
      case PlayerEngine.mpv:
        return MpvPlayerAdapter();
    }
  }

  @visibleForTesting
  static bool? debugIsOhosOverride;

  static bool get isOhos =>
      debugIsOhosOverride ?? (!kIsWeb && defaultTargetPlatform.name == 'ohos');

  /// 当前平台支持的引擎列表。
  ///
  /// 【681：全平台引擎收敛】用户明确要求：
  /// - **安卓手机**：只保留 MPV（移除引擎切换控件）
  /// - **安卓 TV**：保留 MDK / Erika / MPV 三引擎（底栏仍可切换）
  /// - **鸿蒙**：只 MPV
  /// - **Windows**：只 MPV（646 起走 Qt 独立窗口 + vo=gpu-next HDR 直出）
  /// - **iOS**：只 Erika
  ///
  /// [tvMode] 决定安卓是否保留三引擎——TV 遥控场景用户仍需要按机型
  /// 挑内核（不同盒子硬解能力差异大），手机端则统一 MPV 避免歧义。
  static List<PlayerEngine> supportedEngines({bool tvMode = false}) {
    if (isOhos) return const <PlayerEngine>[PlayerEngine.mpv];
    if (kIsWeb) return const <PlayerEngine>[PlayerEngine.mdk];
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // 681：手机只 MPV；TV 保留三引擎（用户明确要求）
        return tvMode
            ? const <PlayerEngine>[
                PlayerEngine.mdk,
                PlayerEngine.erika,
                PlayerEngine.mpv,
              ]
            : const <PlayerEngine>[PlayerEngine.mpv];
      case TargetPlatform.iOS:
        return const <PlayerEngine>[PlayerEngine.erika];
      case TargetPlatform.windows:
        // 681：只 MPV。Qt 播放窗（646+）走原生顶层窗口 + HDR 直出，
        // 本进程 MPV 作为 Qt 启动失败时的回退，两条路都是 MPV。
        return const <PlayerEngine>[PlayerEngine.mpv];
      default:
        return const <PlayerEngine>[PlayerEngine.mdk];
    }
  }

  /// 是否只有一个引擎（决定播放器内是否显示切换控件）。
  ///
  /// 【681】单引擎平台（安卓手机/鸿蒙/Windows/iOS）不该再出现「内核胶囊」——
  /// 点开只有一个选项，纯属噪音。
  static bool isSingleEngine({bool tvMode = false}) =>
      supportedEngines(tvMode: tvMode).length <= 1;

  /// 平台默认引擎：Android / 鸿蒙为 MPV，**Windows 为 media_kit**，
  /// iOS 为 Erika。
  ///
  /// 2026-10 起 Android 默认改为 MPV（原 MDK）：原生 Surface + 原生播放器
  /// UI 是双端统一方案，MDK 仅作为设置里可切换的备选内核保留。
  /// 641：Windows 从 MPV 改为 media_kit（MPV 在 Windows 上 texture 返回崩溃、
  /// surface 灰屏，见 [supportedEngines] 注释）。
  static PlayerEngine defaultEngine() {
    if (isOhos) return PlayerEngine.mpv;
    if (kIsWeb) return PlayerEngine.mdk;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return PlayerEngine.erika;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlayerEngine.mpv;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // 646.1：media_kit → MPV。
      //
      // 646 已实现原生顶层窗口（WS_POPUP + vo=gpu-next HDR 直出），但原生
      // UI 门控要求 `engine == 'mpv'`；media_kit 不走该路径，仍用 Flutter
      // 纹理（真机截图右上角显示 `libmpv` 即为证据）。
      return PlayerEngine.mpv;
    }
    return PlayerEngine.mdk;
  }

  /// 解析落盘内核 id；不支持时回退平台默认。
  ///
  /// 【681】安卓手机老用户存档可能是 `mdk` / `erika`——收敛到仅 MPV 后
  /// 必须回退，否则会拿到一个当前平台不支持的引擎。
  static PlayerEngine resolveSelectedEngine(String? id, {bool tvMode = false}) {
    final selected = PlayerEngine.fromId(id);
    return supportedEngines(tvMode: tvMode).contains(selected)
        ? selected
        : defaultEngine();
  }

  /// 引擎在指定平台是否可用（用于设置页 tab / 校验）。
  static bool isSupported(PlayerEngine engine, {bool tvMode = false}) =>
      supportedEngines(tvMode: tvMode).contains(engine);
}
