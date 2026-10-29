/// Surface 事件 → 会话动作的纯决策逻辑（无 Flutter/Android 依赖，可 JVM 单测）。
///
/// Android 上有两个 SurfaceView 会向同一个 `himi_mpv_android/surface`
/// 通道发事件：Flutter 平台视图（`src=platform`）与原生播放器 UI（Dialog，
/// `src=native`）。两类事件都没有归属信息时会出现两条故障链：
/// - 垂死平台视图的 `surfaceChanged` 把绑定抢回即将销毁的 handle，
///   随后销毁事件（可能根本不发） → mpv 永久搁浅在死 surface → 黑屏；
/// - 旧宿主的 `surfaceDestroyed` 拆掉新 surface 上的播放器 → 黑屏。
///
/// 因此仲裁分两层：
/// 1. **来源过滤**（[accept]）：原生 UI 接管中只认 `native`，未接管只认
///    `platform`，过期来源的事件直接丢弃；
/// 2. **handle 仲裁**（[plan]/[onDestroyed]）：同来源内按 handle 决定
///    首绑 / 换绑 / 忽略销毁。
enum SurfaceAction {
  /// 无动作（重复事件 / 忽略的销毁 / 过期来源）。
  none,

  /// 首次绑定：用事件里的 handle 建播放器。
  ensurePlayer,

  /// 换绑：销毁旧播放器，用新 handle 重建（记住当前播放点）。
  rebind,

  /// 解绑：当前 surface 销毁，销毁播放器等待新 surface。
  detach,
}

/// 事件来源（与 Kotlin `HimiMpvSurfaceView.source` 逐字一致）。
abstract final class SurfaceSrc {
  static const String platform = 'platform';
  static const String nativeUi = 'native';
}

class SurfaceRebindPolicy {
  const SurfaceRebindPolicy();

  /// 来源过滤：[nativeUiActive] 原生播放器 UI 是否接管中；[eventSrc] 事件
  /// 来源（老包无 `src` 字段时为 null，无法仲裁 → 按当前状态放行）。
  bool accept({required bool nativeUiActive, required String? eventSrc}) {
    if (eventSrc == null) return true;
    return eventSrc ==
        (nativeUiActive ? SurfaceSrc.nativeUi : SurfaceSrc.platform);
  }

  /// 新 surface 事件到达（已通过 [accept]）。
  ///
  /// [currentHandle] 当前会话绑定的 handle（0 = 无）；[newHandle] 事件里的
  /// handle；[playerAlive] 播放器是否已创建。
  SurfaceAction plan({
    required int currentHandle,
    required int newHandle,
    required bool playerAlive,
  }) {
    if (newHandle <= 0) return SurfaceAction.none;
    if (currentHandle == newHandle) {
      // 同一 surface 的重复事件（surfaceChanged 也会 emit）。
      return SurfaceAction.none;
    }
    if (!playerAlive) {
      // 播放器还没建（首绑）或已销毁（等待新 surface）。
      return SurfaceAction.ensurePlayer;
    }
    // 播放器存在且换了 surface → 必须重建到新 handle。
    return SurfaceAction.rebind;
  }

  /// `surfaceDestroyed` 事件到达（已通过 [accept]）。
  ///
  /// [destroyedHandle] 被销毁的 handle（老包可能发 0 = 未知）；老包的 0
  /// 无法仲裁，保守按当前 surface 处理（兼容旧行为）。
  SurfaceAction onDestroyed({
    required int currentHandle,
    required int destroyedHandle,
    required bool playerAlive,
  }) {
    if (destroyedHandle > 0 && currentHandle > 0 &&
        destroyedHandle != currentHandle) {
      // 销毁的是别的宿主（旧 SurfaceView），当前 surface 仍然有效。
      return SurfaceAction.none;
    }
    if (!playerAlive && currentHandle == 0) return SurfaceAction.none;
    return SurfaceAction.detach;
  }
}
