/// mdk EGL 渲染故障检测（视频黑屏自愈）。
///
/// 真机定案证据（H96_Max_RK3528 深诊日志）：
/// ```
/// [mdk] ret = eglChooseConfig(...) EGL ERROR (3004) @820 ensureConfig
/// [mdk] no config if surface type is set. try EGL_DONT_CARE
/// [mdk] ret = eglChooseConfig(...) EGL ERROR (3004) @831 ensureConfig
/// [mdk] ContextEGL ERROR! No EGL config found
/// ...
/// [mdk] release MediaCodec output buffer which was not rendered @0（持续刷屏）
/// ```
/// 该设备 EGL 驱动无法满足 mdk 的 config attrib（两轮含 EGL_DONT_CARE
/// 重试全败，EGL_BAD_MATCH=3004）→ GL presenter 无效 → 解码 buffer
/// 从不上屏 → 画面全黑（UI/音频正常，三档纹理路径全中）。
///
/// 检测到该故障时，唯一不依赖 GL/EGL 的输出通道是 tunnel 直通
/// （fvp 文档：no GL renderer, no EGLConfig），由播放器自动切换自愈。
///
/// 纯 Dart、无插件依赖，便于单测；全局实例供 bootstrap 与播放器的
/// mdk log handler 共享同一检测状态。
class EglFaultDetector {
  /// 判据刻意收窄到该故障签名，避免其他 EGL 场景误触发自动切档：
  /// - `No EGL config found`——mdk 的最终失败结论；
  /// - `EGL ERROR (3004)`——eglChooseConfig 返回 EGL_BAD_MATCH 的原始错误。
  static final _patterns = <RegExp>[
    RegExp(r'No EGL config found'),
    RegExp(r'EGL ERROR \(3004\)'),
  ];

  bool _fault = false;

  /// 是否已确认 EGL 故障（幂等置位）。
  bool get fault => _fault;

  /// 喂一行 mdk 日志；命中返回 true（仅首次为 true，供调用方做一次性
  /// 自愈动作），未命中或已置位返回 false。
  bool feed(String line) {
    if (_fault) return false;
    for (final p in _patterns) {
      if (p.hasMatch(line)) {
        _fault = true;
        return true;
      }
    }
    return false;
  }

  /// 测试用：重置状态。
  void reset() => _fault = false;
}

/// 进程级共享实例：`main._bootstrap` 的初始 log handler 与播放器的
/// 深度诊断/精简 handler 均向它 feed，任一入口命中即全局可见。
final eglFaultDetector = EglFaultDetector();

/// 等待进行中的媒体切换（`_isSwitchingMedia`）释放，最长 [timeout]。
///
/// EGL 自愈重建管线前必须等首播/切集完成，否则 stop/prepare 会与
/// 进行中的 `_loadStream`/`_playFromUrl` 交织。返回 true 表示可以
/// 安全重建；false 表示超时放弃。
Future<bool> waitForMediaSwitch(
  bool Function() isSwitching, {
  Duration timeout = const Duration(seconds: 8),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final sw = Stopwatch()..start();
  while (isSwitching() && sw.elapsed < timeout) {
    await Future<void>.delayed(step);
  }
  return !isSwitching();
}
