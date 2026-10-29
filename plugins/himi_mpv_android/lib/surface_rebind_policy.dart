/// Surface 事件 → 会话动作的纯决策逻辑（无 Flutter/Android 依赖，可 JVM 单测）。
///
/// Android 上有两个 SurfaceView 会向同一个 `himi_mpv_android/surface`
/// 通道发事件：Flutter 平台视图（视频区）与原生播放器 UI（Dialog）。
/// 两者的 surface 创建/销毁顺序不确定，若不做 id 仲裁，会出现：
/// - 旧宿主的 `surfaceDestroyed` 把新 surface 上的播放器拆掉 → 黑屏；
/// - 新 surface 到达但播放器绑在旧 handle 上 → 不重绑 → 黑屏。
enum SurfaceAction {
  /// 无动作（重复事件 / 忽略的销毁）。
  none,

  /// 首次绑定：用 [_SurfaceRebindPolicy.plan] 返回的 handle 建播放器。
  ensurePlayer,

  /// 换绑：销毁旧播放器，用新 handle 重建（记住当前播放点）。
  rebind,

  /// 解绑：当前 surface 销毁，销毁播放器等待新 surface。
  detach,
}

class SurfaceRebindPolicy {
  const SurfaceRebindPolicy();

  /// 新 surface 事件到达。
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

  /// `surfaceDestroyed` 事件到达。
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
