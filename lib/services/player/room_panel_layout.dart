import 'dart:ui' show Rect, Size;

/// 677：Windows 房间模式的「双窗并排」几何契约（**纯函数，可单测**）。
///
/// 【布局约定】
/// ```
/// ┌───────────────────────────┬──────────────┐
/// │  Qt 播放窗（视频 + 控件）  │ Flutter 面板  │
/// │      占满左侧剩余区域      │  固定 ~380   │
/// └───────────────────────────┴──────────────┘
/// ```
/// Qt 只播视频、Flutter 只渲染房间面板（资源列表/播报/头部）。
///
/// 【运行时由谁算】实际运行时**由 Qt 计算**（`MpvWindow::requestSplitLayout`
/// 用 `QScreen::availableGeometry()`）——`window_manager` 不暴露屏幕工作区，
/// 多屏/DPI 在 Dart 侧只能靠猜。Qt 算完通过 `splitLayout` 帧回传，Dart 只
/// 负责应用面板侧尺寸。
///
/// 【那这里的 `compute` 做什么】它是同一套规则的**Dart 侧契约实现**：
///   - 单测可直接验证「面板贴右 / 视频占左 / 窄屏夹紧 / 放不下放弃」
///   - Qt 侧 `requestSplitLayout` 与本文件保持同一组常量与判据，
///     任一侧改规则时另一侧的测试会立刻发现不一致
/// 因此它不是死代码，是**跨语言契约的可执行文档**。
class RoomPanelLayout {
  const RoomPanelLayout._();

  /// 面板固定宽度（逻辑像素）。320 太窄放不下「季-集」两级缩进，
  /// 420 以上又会把 Qt 视频区压得没地方，380 是实测平衡点。
  static const double panelWidth = 380;

  /// Qt 视频区最小宽度（逻辑像素）。低于此值控件会被挤爆
  /// （底栏进度条 + 音量胶囊 + 右组图标）。
  static const double minVideoWidth = 480;

  /// 房间面板窗最小宽度（逻辑像素）——与 Qt 侧 `kMinPanelWidth` 必须一致。
  ///
  /// 【为什么需要】不限制时用户能把面板拖到极窄，Qt 侧可用宽不足
  /// `minVideoWidth` → 要么堆叠要么不跟随（真机截图：面板压在视频上）。
  /// 320 + 480 = 800 是并排的最小总宽。
  static const double minPanelWidth = 320;

  /// 房间面板窗最小高度（逻辑像素）——低于此值播报板 + 资源列表都放不下。
  static const double minPanelHeight = 500;

  /// 计算房间并排布局。
  ///
  /// [workArea] 屏幕可用区域（已排除任务栏），逻辑像素。
  /// [currentBounds] Flutter 主窗当前 bounds（用于判断贴左/贴右/最大化）。
  ///
  /// 返回 `null` 表示**工作区放不下两个窗口**（例如超窄屏），
  /// 调用方应放弃并排、退回「Qt 全屏 + 面板浮层」或单窗模式。
  static RoomSplitLayout? compute({
    required Rect workArea,
    required Rect currentBounds,
  }) {
    if (workArea.width <= 0 || workArea.height <= 0) return null;

    // 总宽不超屏：视频区 + 面板宽必须塞得进工作区。
    // 只有**放不下**时才压缩面板（不低于 minPanelWidth）；放得下就用标准宽度。
    var panel = panelWidth;
    if (panel + minVideoWidth > workArea.width) {
      panel = workArea.width - minVideoWidth;
    }
    if (panel < minPanelWidth) return null;

    final videoWidth = workArea.width - panel;
    if (videoWidth < minVideoWidth) return null;

    // 面板贴工作区右侧，纵向占满（房间面板是列表，越高越好用）。
    final panelRect = Rect.fromLTWH(
      workArea.left + videoWidth,
      workArea.top,
      panel,
      workArea.height,
    );
    final videoRect = Rect.fromLTWH(
      workArea.left,
      workArea.top,
      videoWidth,
      workArea.height,
    );
    return RoomSplitLayout(
      panelBounds: panelRect,
      videoRect: videoRect,
      // 主窗进入并排前的 bounds 需要被记住，退房时恢复。
      restoreBounds: currentBounds,
    );
  }

  /// 房间并排期间主窗的**最大尺寸**（防止用户最大化占满屏把 Qt 挤掉）。
  ///
  /// 【为什么用最大尺寸而不是禁止最大化】用户仍可放大到「刚好够用」的
  /// 宽度，只是无法越过 Qt 的最小宽度。`window_manager.setMaximumSize`
  /// 写的是 `WM_GETMINMAXINFO.ptMaxTrackSize`，连最大化按钮一起受限。
  static Size maxPanelWindowSize(Rect workArea) {
    final panel = panelWidth;
    final maxW = workArea.width - minVideoWidth;
    return Size(
      maxW < panel ? panel : maxW,
      workArea.height,
    );
  }
}

/// 房间并排布局结果。
class RoomSplitLayout {
  const RoomSplitLayout({
    required this.panelBounds,
    required this.videoRect,
    required this.restoreBounds,
  });

  /// Flutter 主窗（房间面板）应处的 bounds。
  final Rect panelBounds;

  /// Qt 播放窗应处的矩形。
  final Rect videoRect;

  /// 进房前的 Flutter 主窗 bounds（退房恢复）。
  final Rect restoreBounds;

  @override
  String toString() => 'RoomSplitLayout(panel: $panelBounds, video: $videoRect)';
}
