import 'package:flutter/widgets.dart';

/// 回前台/亮屏后应执行的视频输出恢复动作。
enum PlayerResumeAction {
  /// 无需处理（SurfaceView 档由 platform view 自愈）。
  none,

  /// 纹理/直通档：熄屏/切后台后 mdk 的解码/渲染管线已停死，仅重建
  /// external texture 无法重启它（实测：纹理换新但仍无 缓冲/解码器 事件）。
  /// 需按当前进度**重载当前流**重建整条管线。
  reprime,
}

/// 播放器应用生命周期策略（纯 Dart，便于单测）。
///
/// 熄屏与切后台走同一条 `inactive → paused → resumed` 事件链。纹理/直通档
/// （Android Skia 的 SurfaceTexture、iOS 纹理）在后台时 mdk 原生管线停死，
/// 回前台必须重载当前流才能恢复；SurfaceView 档由 platform view 的
/// surfaceDestroyed/surfaceCreated 自愈。
class PlayerLifecyclePolicy {
  const PlayerLifecyclePolicy._();

  /// 进入后台/熄屏（需在回前台时恢复输出）。
  ///
  /// 仅取 `paused`/`hidden`：`inactive` 会因系统弹窗、通知栏下拉、
  /// 分屏失焦等**瞬时**原因触发（此时管线未停死），若也在此时重载会
  /// 造成不必要的闪烁；而熄屏与切后台必定到达 `paused`。
  static bool enterBackground(AppLifecycleState state) =>
      state == AppLifecycleState.paused || state == AppLifecycleState.hidden;

  /// 回前台（resumed）后应执行的视频输出恢复动作。
  static PlayerResumeAction resumeAction(String output) =>
      (output == 'surfaceView' || output == 'surfaceViewDirect')
          ? PlayerResumeAction.none
          : PlayerResumeAction.reprime;
}
