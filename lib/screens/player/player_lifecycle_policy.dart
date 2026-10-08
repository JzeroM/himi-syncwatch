import 'package:flutter/widgets.dart';

/// 回前台/亮屏后应执行的视频输出恢复动作。
enum PlayerResumeAction {
  /// 无需处理。
  none,

  /// 纹理/直通档：引擎 EGL 上下文重建后旧 external texture 失效，
  /// 释放并按当前档位重建纹理（重新 nativeSetSurface 绑定）。
  recreateTexture,

  /// SurfaceView 档：platform view 自行 surfaceCreated 重绑，仅补一帧。
  pulseSurface,
}

/// 播放器应用生命周期策略（纯 Dart，便于单测）。
///
/// 熄屏与切后台走同一条 `inactive → paused → resumed` 事件链：引擎销毁
/// 并重建 EGL/Surface 上下文。纹理档（Android Skia 的 SurfaceTexture、
/// iOS 纹理）没有 fvp 的 surface 生命周期回调，旧 SurfaceTexture 失效后
/// mdk 仍渲染到已 detach 的 Surface → 画面定格；暂停态最后一帧丢失且无
/// 新帧 → 黑屏。故回前台时按输出档位决定恢复动作。
class PlayerLifecyclePolicy {
  const PlayerLifecyclePolicy._();

  /// 进入后台/熄屏（需在回前台时恢复输出）。
  ///
  /// 仅取 `paused`/`hidden`：`inactive` 会因系统弹窗、通知栏下拉、
  /// 分屏失焦等**瞬时**原因触发（此时 EGL/Surface 未销毁），若也在此时
  /// 重建纹理会造成不必要的闪烁；而熄屏与切后台必定到达 `paused`。
  static bool enterBackground(AppLifecycleState state) =>
      state == AppLifecycleState.paused || state == AppLifecycleState.hidden;

  /// 回前台（resumed）后应执行的视频输出恢复动作。
  static PlayerResumeAction resumeAction(String output) =>
      output == 'surfaceView'
          ? PlayerResumeAction.pulseSurface
          : PlayerResumeAction.recreateTexture;
}
