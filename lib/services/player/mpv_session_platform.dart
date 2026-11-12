import 'dart:async' show unawaited;
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:himi_mpv_android/himi_mpv_android.dart';
import 'package:himi_mpv_ohos/himi_mpv_ohos.dart';
import 'package:himi_mpv_windows/himi_mpv_windows.dart';

import 'native/android_native_player.dart';
import 'qt_player_adapter.dart';

/// 三端 MPV 会话工厂。
///
/// Surface 模式：鸿蒙 XComponent、Android SurfaceView、Windows 子 HWND；
/// Texture 模式由各平台会话创建 Flutter 纹理。具体路径由 MPV 设置决定。
class MpvSessionPlatform {
  const MpvSessionPlatform._();

  static bool get isOhos => defaultTargetPlatform.name == 'ohos';

  static Future<MpvSession> create({
    required int width,
    required int height,
    required String hwdecMode,
    required bool nativeSurface,
    required bool hdr,
    required bool hlg,
    bool nativeUi = false,
    /// 655：Android Surface 路径的渲染器（'gpu-next' / 'gpu'），由设置决定。
    /// 其它平台忽略此参数（各自在插件内部固定）。
    String vo = 'gpu-next',
  }) {
    if (isOhos) {
      return HimiMpvPlayer.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
        nativeUi: nativeUi,
        hdr: hdr,
        hlg: hlg,
      );
    }
    if (Platform.isAndroid) {
      return HimiMpvAndroidSession.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
        nativeUi: nativeUi,
        hdr: hdr,
        hlg: hlg,
        vo: vo,
      );
    }
    if (Platform.isWindows) {
      // 646：Windows 也支持原生播放器 UI——走**顶层窗口**（WS_POPUP）+
      // MPV `vo=gpu-next` 直出，实现真 HDR。
      //
      // 旧注释「Windows 不支持原生播放器 UI」已过时：限制在于
      // **子 HWND 会被 Flutter 的 DirectComposition 不透明层遮挡**
      // （surface 灰屏根因），而非不能做原生 UI。改用顶层窗口后可行。
      return HimiMpvWindowsSession.create(
        width: width,
        height: height,
        hwdecMode: hwdecMode,
        nativeSurface: nativeSurface,
        nativeUi: nativeUi,
        hdr: hdr,
        hlg: hlg,
      );
    }
    throw UnsupportedError(
        'MPV native surface is not implemented on this platform');
  }

  static Future<MpvHdrCapabilities> queryHdrCapabilities() {
    if (isOhos) return HimiMpvPlayer.queryHdrCapabilities();
    if (Platform.isAndroid) return HimiMpvAndroidSession.queryHdrCapabilities();
    if (Platform.isWindows) return HimiMpvWindowsSession.queryHdrCapabilities();
    return Future<MpvHdrCapabilities>.value(MpvHdrCapabilities.unknown);
  }

  // ── 原生播放器 UI 宿主（鸿蒙子窗口 / Android Dialog / Windows 独立窗口）

  /// 656：Windows 是否启用 Qt 播放器窗口。
  ///
  /// 685：**Windows 恒启用**（设置页已移除「使用 Qt 播放器窗口」开关）。
  ///
  /// 【为什么硬编码】Qt 窗口是 Windows 上唯一完整的播放器（进度条 /
  /// 播放控制 / 音量 / 选集 / 音轨 / 字幕）。关掉会退化成「只有视频、
  /// 没有控件」的裸窗口，没有任何合理场景，反而让用户以为功能坏了。
  ///
  /// 【为什么保留 setter】播放页仍会写一次（值恒为 true），测试与
  /// 旧代码路径不受影响；写入 false 会被 [isQtPlayerEnabled] 忽略。
  static bool _qtPlayerEnabled = false;

  /// 656/685：Qt 播放器是否启用。
  ///
  /// Windows 恒为 true（硬编码）；其它平台恒为 false。
  static bool get qtPlayerEnabled =>
      Platform.isWindows ? true : _qtPlayerEnabled;

  /// 685：兼容旧调用点的 setter——**Windows 上写入会被忽略**。
  static set qtPlayerEnabled(bool value) => _qtPlayerEnabled = value;

  /// 656：Qt 播放器进程的 exe 路径（Windows）。
  ///
  /// Flutter 产物里 Qt 目录放在 `himi_qt_player\`（与主 exe 同级）。
  static String? qtPlayerExePath;

  /// 656：当前活跃的 Qt 适配器（同一时刻只允许一个播放窗口）。
  static QtPlayerAdapter? activeQtAdapter;

  /// 670：Qt 进程拉起**全局单飞**（启动预热与起播共用一次）。
  ///
  /// 【为什么全局】670 起应用启动即预热（隐藏待命），起播时复用；
  /// 单飞放播放页 State 里会与预热并发互杀（launchQtPlayer 先关旧窗）。
  static Future<QtPlayerAdapter?>? _qtLaunchFuture;

  /// 671 A1：单飞产物（存活校验用）——死适配器不得复用。
  static QtPlayerAdapter? _qtLaunched;

  /// 656/670：Qt 播放器 exe 的绝对路径（Windows）。
  ///
  /// 产物布局：`<主 exe 目录>\himi_qt_player\himi_qt_player.exe`
  ///（CI 把 Qt 目录整体放进 Windows zip）。
  static String? resolveQtPlayerExePath() {
    if (!Platform.isWindows) return null;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final path =
          '${exeDir.path}${Platform.pathSeparator}himi_qt_player'
          '${Platform.pathSeparator}himi_qt_player.exe';
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// 670：拉起 Qt 播放器进程（全局单飞）。
  ///
  /// [prewarm] 为 true 时进程**隐藏待命**（Qt 侧 `--prewarm`：初始化完
  /// 不显示窗口，收到 load 命令才弹出）——应用启动即调用，冷启动的
  /// 数秒被完全掩盖，起播窗口秒出。
  static Future<QtPlayerAdapter?> ensureQtPlayer({bool prewarm = false}) {
    // 671 A1：死适配器不得复用（进程已退出/管道已断时缓存作废重拉）
    // ——真机回归「播完返回再播 Qt 永不出现」：旧单飞永久缓存死适配器，
    // 命令写进已关管道静默丢失。
    final launched = _qtLaunched;
    if (launched != null && !launched.isAlive) {
      _qtLaunchFuture = null;
      _qtLaunched = null;
    }
    return _qtLaunchFuture ??= _doLaunchQtPlayer(prewarm: prewarm)
        .then((adapter) {
      _qtLaunched = adapter;
      if (adapter == null) {
        _qtLaunchFuture = null;  // 启动失败：清缓存，下次可重试
      }
      return adapter;
    });
  }

  static Future<QtPlayerAdapter?> _doLaunchQtPlayer({required bool prewarm}) async {
    final exePath = qtPlayerExePath ?? resolveQtPlayerExePath();
    if (exePath == null) return null;
    qtPlayerExePath = exePath;
    try {
      // 同一时刻只允许一个 Qt 播放窗口：先关旧的（launchQtPlayer 内）。
      final adapter = await launchQtPlayer(exePath: exePath, prewarm: prewarm);
      return adapter;
    } catch (e) {
      return null;
    }
  }

  /// 670/685：启动预热（Windows 恒启用，应用启动即调用）。
  ///
  /// 失败静默（起播时会再试/回退 646）；预热期进程意外退出则清理
  /// 死适配器（防起播误复用）。
  static Future<void> prewarmQtPlayer() async {
    if (!Platform.isWindows) return;
    final adapter = await ensureQtPlayer(prewarm: true);
    if (adapter == null) return;
    adapter.onProcessExited = () {
      unawaited(closeQtPlayer());
    };
  }

  /// 原生 UI 宿主平台名（'ohos' / 'android' / 'windows'）；不支持为 null。
  ///
  /// 【653 真机回归：Flutter 窗口同时显示详情页与播放控件】
  /// 旧实现 Windows 恒返回 null，于是
  /// `_openNativeUiIfNeeded()` 在 `if (platform == null) return;` 处直接
  /// 退出 → `nativeUiActive` **永不置 true** →
  /// `PlayerScreen` 的 `SizedBox.shrink()` 守卫不生效 →
  /// Flutter 窗口把详情页与播放页顶/底栏一起渲染出来
  /// （真机截图：左侧 Flutter 窗口叠着控制 UI，右侧是原生播放器）。
  ///
  /// Windows 自 646 起也走原生独立窗口（`WS_POPUP` + `vo=gpu-next`
  /// HDR 直出），窗口在 `HimiMpvWindowsSession._start()` 里就已创建，
  /// 因此 `openNativeUi()` 等配套方法在 Windows 上是空实现即可；
  /// 但**门控必须能通过**，否则播放页不会退场。
  static String? get nativeUiPlatformName {
    if (isOhos) return 'ohos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  /// 打开原生播放器 UI 宿主（幂等）。
  static Future<void> openNativeUi() {
    if (isOhos) return HimiMpvPlayer.openNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.open();
    // 656：Windows 的 Qt 播放器由 [launchQtPlayer] 单独拉起（需要
    // URL/HDR 等参数），这里保持空实现——646 的原生窗口已在会话
    // 创建时就建好了。
    return Future<void>.value();
  }

  /// 656：拉起 Qt 播放器窗口（Windows）。
  ///
  /// 返回适配器；失败返回 null（上层应回退到 646 路径）。
  /// [prewarm]：隐藏待命模式（670 预热，见 [ensureQtPlayer]）。
  static Future<QtPlayerAdapter?> launchQtPlayer({
    required String exePath,
    bool hdr = false,
    bool hlg = false,
    bool prewarm = false,
  }) async {
    if (!Platform.isWindows) return null;
    try {
      // 同一时刻只允许一个 Qt 播放窗口：先关旧的。
      await closeQtPlayer();
      final adapter = await QtPlayerAdapter.launch(
        exePath: exePath,
        hdr: hdr,
        hlg: hlg,
        prewarm: prewarm,
      );
      activeQtAdapter = adapter;
      return adapter;
    } catch (e) {
      return null;
    }
  }

  /// 656：关闭 Qt 播放器窗口（幂等）。
  static Future<void> closeQtPlayer() async {
    final adapter = activeQtAdapter;
    activeQtAdapter = null;
    // 671 A1：单飞缓存同步作废（死适配器不得被下次起播复用）
    _qtLaunchFuture = null;
    _qtLaunched = null;
    if (adapter == null) return;
    try {
      adapter.dispose();
    } catch (_) {}
  }

  /// 关闭原生播放器 UI 宿主（幂等）。
  static Future<void> closeNativeUi() {
    if (isOhos) return HimiMpvPlayer.closeNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.close();
    // 656：Windows 若启用了 Qt 播放器，关闭时同时结束那个进程。
    if (Platform.isWindows) return closeQtPlayer();
    return Future<void>.value();
  }

  /// 临时隐藏原生播放器 UI 宿主（**不销毁** session / surface 绑定，603）。
  ///
  /// 用于需要在 Flutter 层显示界面的场景（资源搜索页 / 离房确认框）：
  /// 原生窗口 z-order 在 Flutter 页面之上，不隐藏会盖住它们。
  static Future<void> suspendNativeUi() {
    if (isOhos) return HimiMpvPlayer.suspendNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.suspend();
    return Future<void>.value();
  }

  /// 恢复被 [suspendNativeUi] 隐藏的原生播放器 UI 宿主（幂等）。
  static Future<void> resumeNativeUi() {
    if (isOhos) return HimiMpvPlayer.resumeNativeUi();
    if (Platform.isAndroid) return AndroidNativePlayer.resume();
    return Future<void>.value();
  }

  /// 649：聚焦 Windows 原生独立窗口（详情页重复点播放时用）。
  ///
  /// 返回 true 表示窗口已存在并被置前；false 表示尚未创建。
  static Future<bool> focusHostWindow() {
    if (!Platform.isWindows) return Future<bool>.value(false);
    return HimiMpvWindowsSession.focusHostWindow();
  }

  /// Dart → 原生：推送权威状态 JSON 快照。
  static Future<void> pushNativeState(String stateJson) {
    if (isOhos) return HimiMpvPlayer.pushNativeState(stateJson);
    if (Platform.isAndroid)
      return AndroidNativePlayer.pushNativeState(stateJson);
    return Future<void>.value();
  }

  /// 原生 UI 命令流（原生 → Dart）。
  static Stream<Map<Object?, Object?>> nativeUiCommandStream() {
    if (isOhos) return HimiMpvPlayer.nativeUiCommandStream;
    if (Platform.isAndroid) return AndroidNativePlayer.commandStream;
    return const Stream<Map<Object?, Object?>>.empty();
  }
}
