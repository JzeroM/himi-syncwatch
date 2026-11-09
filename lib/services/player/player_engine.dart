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
  /// 对齐 NipaPlay 平台矩阵（HIMI 现有平台）：
  /// - Android / Android TV：MDK、Erika、MPV（mediaKit/libmpv 引擎选项已移除：
  ///   它只是 media_kit 的纹理路径，与原生 MPV 共用同一份 libmpv.so 与驱动，
  ///   去掉选项不影响原生 MPV 的编译与运行）
  /// - iOS：Erika
  /// - **Windows：MDK、media_kit、Erika（media_kit 为默认，MPV 已移除）**
  ///
  /// 【641 真机回归：Windows 移除 MPV】
  /// Windows 上 MPV 两条渲染路径都不可用：
  /// - texture：从播放页返回时崩在 `flutter_windows.dll`
  ///   （0xc0000005，`ValueListenableBuilder` 与 textureId notifier 的
  ///   生命周期竞态）；
  /// - surface：原生子 HWND 被 Flutter 不透明窗口遮挡 → 灰屏（有声音无画面）。
  /// 故 Windows 改用 media_kit（走 Flutter 纹理，长期验证稳定），
  /// MDK 保留为备选。旧存档选过 mpv 的由 [resolveSelectedEngine]
  /// 自动回退到新的平台默认。
  static List<PlayerEngine> supportedEngines() {
    if (isOhos) return const <PlayerEngine>[PlayerEngine.mpv];
    if (kIsWeb) return const <PlayerEngine>[PlayerEngine.mdk];
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.erika,
          PlayerEngine.mpv,
        ];
      case TargetPlatform.iOS:
        return const <PlayerEngine>[PlayerEngine.erika];
      case TargetPlatform.windows:
        // 646.1：加回 MPV，移除 media_kit。
        //
        // 【真机证据链】
        // - v1.5.3 默认 MDK → 正常；手动切 media_kit → 闪退
        // - 1.5.59/1.5.60 用 MPV texture → 闪退（flutter_windows.dll 0x1551f）
        // - 641 移除 MPV 后，Windows 只剩 media_kit（必崩）+ MDK
        // - 646 实现了原生顶层窗口（HDR 直出），但原生 UI 门控要求
        //   `engine == 'mpv'`，而列表里没有 MPV → 永远不启用
        //   （真机截图右上角显示 `libmpv` 即为证据）
        //
        // 故加回 MPV 作为**默认**（走原生顶层窗口 + vo=gpu-next HDR 直出），
        // MDK 保留为备选（Flutter 纹理，不崩但 SDR tone map）。
        return const <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.mpv,
          PlayerEngine.erika,
        ];
      default:
        return const <PlayerEngine>[PlayerEngine.mdk];
    }
  }

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
  static PlayerEngine resolveSelectedEngine(String? id) {
    final selected = PlayerEngine.fromId(id);
    return supportedEngines().contains(selected) ? selected : defaultEngine();
  }

  /// 引擎在指定平台是否可用（用于设置页 tab / 校验）。
  static bool isSupported(PlayerEngine engine) =>
      supportedEngines().contains(engine);
}
