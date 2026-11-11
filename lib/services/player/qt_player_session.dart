import 'dart:async';

import '../../services/decode_mode_service.dart';
import '../../services/log_service.dart';
import 'native/native_player_command.dart';
import 'qt_player_adapter.dart';

/// 664：Qt 播放器**常驻会话**（Qt 窗口出现后主窗口立即回详情页）。
///
/// 【为什么需要】用户要求「Qt 窗口一出现，主窗口就是详情页」——播放页
/// State 随 pop 销毁，原先挂在它身上的状态推送/命令桥会断供。本会话
/// 不随页面销毁，接管两件事：
///
///   1. **状态快照**：pop 前把 `NativePlayerState` 全量 JSON 存为模板，
///      attach 时推给 Qt（面板列表/标题/轨道等低频态）。播放态
///      （位置/暂停/时长）由 Qt 侧 mpv 事件在 main.cpp 本地补丁，
///      不需要 Flutter 循环推送。
///   2. **命令桥**：Qt 发来的切集/切版本经 [resolveEpisode]/
///      [resolveVersion]（pop 前由播放页注入**纯数据**解析闭包——
///      只捕获 EmbyService 实例与媒体列表拷贝，不碰已销毁的 State）
///      重新解析流地址并喂给 Qt；亮度写系统亮度。
///
/// 【播放控制不在这里】播放/暂停/进度/音量/倍速/切轨已由 Qt 侧
/// QML 直驱本地 mpv（mpvWindow.*），到这里的通知只是记账。
class QtPlayerSession {
  QtPlayerSession._(this.adapter, this._template);

  /// 当前活跃会话（Qt 窗口存活期间唯一）。
  static QtPlayerSession? active;

  final QtPlayerAdapter adapter;

  /// pop 前的状态快照模板（切集/切版本时打补丁后重推）。
  final Map<String, Object?> _template;

  /// 切集解析（纯数据闭包；返回 null = 无法解析，忽略命令）。
  Future<QtMediaTarget?> Function(int episodeIndex)? resolveEpisode;

  /// 切版本解析（同上）。
  Future<QtMediaTarget?> Function(int versionIndex)? resolveVersion;

  /// 亮度应用（写系统亮度）。
  Future<void> Function(double brightness)? applyBrightness;

  /// 671：切集后的轻量页面驱动（弹幕重拉 + 状态推送）——弹幕数据
  /// 不能随会话接管断供（Qt 弹幕不显示的根因）。
  Future<void> Function(int episodeIndex)? onEpisodeSwitched;

  /// 671：被新会话顶替时回调（旧的隐身播放页据此退场）。
  void Function()? onReplaced;

  /// 页面阶段的富处理兜底（`_handleNativeUiCommand`）：设置持久化等。
  /// pop 后其 mounted 守卫自动空转，可安全继续调用。
  Future<void> Function(NativePlayerCommand command)? fallback;

  /// 建立会话并接管 [adapter] 的命令桥；同时推一次状态快照。
  ///
  /// [onProcessExited]：Qt 进程退出时回调（播放页传入自己的退页逻辑，
  /// pop 后其 mounted 守卫自动幂等）。
  static QtPlayerSession attach({
    required QtPlayerAdapter adapter,
    required Map<String, Object?> template,
    void Function()? onProcessExited,
  }) {
    // 新会话前先收掉旧的（同进程只留一个 Qt 窗口语义）。
    final old = active;
    if (old != null) {
      if (!identical(old.adapter, adapter)) {
        old.adapter.dispose();
      }
      // 671：旧会话让位 → 旧的隐身播放页退场（调用方微任务判定自替换）
      old.onReplaced?.call();
    }
    final session = QtPlayerSession._(adapter, Map.of(template));
    active = session;
    adapter.onNativeUiCommand = session._handleCommand;
    adapter.onProcessExited = () {
      if (identical(active, session)) active = null;
      LogService().log('QtPlayerSession', 'Qt 窗口已关闭，会话清理');
      onProcessExited?.call();
    };
    // 快照一次推给 Qt（面板列表/标题等）。
    adapter.pushNativeState(Map.of(session._template));
    return session;
  }

  /// Qt 发来的命令（与安卓/鸿蒙原生 UI 同链路，播放控制类已被
  /// QtPlayerAdapter 就地消化，不会到这里）。
  ///
  /// 【分工】切集/切版本由会话重新起播（页面已销毁，走纯数据解析）；
  /// 显示调节/字幕样式/解码走 **headless 直驱 mpv 属性**（Qt 的 mpv
  /// 在本进程外，唯一通道是 adapter.setProperty / videoDecoders）；
  /// 其余交给 [fallback]（页面存活期的富处理，pop 后空转）。
  Future<void> _handleCommand(NativePlayerCommand command) async {
    switch (command) {
      case SelectEpisode(:final index):
        final target = await resolveEpisode?.call(index);
        if (target == null) {
          LogService().log('QtPlayerSession', '切集解析失败: $index');
          return;
        }
        await _load(target, episodeIndex: index);
        // 671：驱动页面管线（换集弹幕重拉 + 状态推送）
        await onEpisodeSwitched?.call(index);
      case SelectVersion(:final index):
        final target = await resolveVersion?.call(index);
        if (target == null) {
          LogService().log('QtPlayerSession', '切版本解析失败: $index');
          return;
        }
        await _load(target, versionIndex: index);
      case SetDecodeMode(:final mode):
        // 解码档位 → mpv hwdec（映射走 resolveWindowsHwdec 单一真相源）
        adapter.videoDecoders = DecodeModeService.resolveDecoders(mode);
        await fallback?.call(command);
      case SetSubtitleStyle(:final style):
        adapter.setProperty('sub-scale', (style.fontSize / 16.0).toString());
        await fallback?.call(command);
      case SetSubtitleDelay(:final delayMs):
        adapter.setProperty('sub-delay', (delayMs / 1000.0).toString());
        await fallback?.call(command);
      case AdjustDisplay(:final key, :final value):
        _applyAdjustHeadless(key, value);
        await fallback?.call(command);
      case ResetDisplay(:final scope):
        if (scope == 'subtitle') {
          adapter.setProperty('sub-scale', '1');
          adapter.setProperty('sub-pos', '89');
          adapter.setProperty('sub-delay', '0');
        }
        await fallback?.call(command);
      default:
        await fallback?.call(command);
    }
  }

  /// 显示调节六键的 headless 映射（键语义与 `_applyNativeAdjustDisplay`
  /// 一致；danmaku* 在 Qt 窗口暂无弹幕渲染层，忽略）。
  void _applyAdjustHeadless(String key, double value) {
    switch (key) {
      case 'subtitleScale':
        adapter.setProperty('sub-scale', value.clamp(0.5, 3.0).toString());
      case 'subtitleMarginY':
        // mpv `sub-pos`：0=底部 … 100=越高越靠上；Flutter marginY
        // 0~200px 越大越高 → 线性映射（marginY 22 → sub-pos 89）。
        adapter.setProperty(
          'sub-pos',
          (100 - value.clamp(0, 200) / 2).round().toString(),
        );
      case 'subtitleDelayMs':
        adapter.setProperty('sub-delay', (value / 1000.0).toString());
      default:
        break;
    }
  }

  Future<void> _load(
    QtMediaTarget target, {
    int episodeIndex = -1,
    int versionIndex = -1,
  }) async {
    adapter.media = target.url;
    adapter.setHttpHeaders(target.headers);
    await adapter.prepare(startMs: target.startMs);
    // 快照补丁：标题/选中项随切集/切版本更新
    _template['title'] = target.title;
    if (episodeIndex >= 0) _template['currentEpisodeIndex'] = episodeIndex;
    if (versionIndex >= 0) _template['currentVersionIndex'] = versionIndex;
    adapter.pushNativeState(Map.of(_template));
    LogService().log(
      'QtPlayerSession',
      '切流: ${target.title} (ep=$episodeIndex ver=$versionIndex)',
    );
  }

  /// 会话终止（Qt 窗口已关/被新会话替换时调用）。
  void shutdown() {
    if (identical(active, this)) active = null;
  }
}

/// 会话阶段的流目标（纯数据；由播放页 pop 前注入的解析闭包产出）。
class QtMediaTarget {
  const QtMediaTarget({
    required this.url,
    required this.headers,
    required this.title,
    this.startMs = 0,
  });

  final String url;
  final Map<String, String> headers;
  final String title;
  final int startMs;
}
