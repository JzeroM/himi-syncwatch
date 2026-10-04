/// 渲染风暴检测器：统计 mdk renderer 连续丢帧的速率。
///
/// 签名行见 [MdkLogParser.isNotRenderedLine]——decoder 正常出帧但
/// renderer 全部丢弃（himi_logs_5：切集后新 EGL 上下文渲 1 帧即进入
/// 持续丢帧，画面定格在首帧、音频/进度正常，实测约 58 帧/秒）。
///
/// 行为：1 秒窗口内丢帧数达到 [threshold] 时产出一条摘要（每窗口至多
/// 一次），供调用方写入诊断日志/时间线。**只记日志不动作**——主动
/// 自愈（重挂 view）本身可能触发同一 mdk 缺陷，v1.1.82 定案不启用。
///
/// 注意：丢帧行为 FINE 级输出，仅在深度诊断（`log.status=2`）开启时
/// 可见；检测器本身纯 Dart、可单测。
library;

import 'mdk_log_parser.dart';

class RenderStormDetector {
  RenderStormDetector({this.threshold = 20});

  /// 1 秒窗口内达到该丢帧数即判定风暴。正常零星丢帧（av_sync 修正、
  /// seek flush）每秒 1~2 帧；24fps 片源整秒全丢也才 24 帧，风暴态
  /// 实测 58 帧/秒——20 阈值既灵敏又避开正常损耗。
  final int threshold;

  int _count = 0;
  DateTime? _windowStart;
  bool _reported = false;

  /// 喂一行 mdk 日志；返回非 null 时为应记录的风暴摘要行。
  String? feed(String line, {DateTime? now}) {
    if (!MdkLogParser.isNotRenderedLine(line)) return null;
    final t = now ?? DateTime.now();
    final start = _windowStart;
    if (start == null || t.difference(start) >= const Duration(seconds: 1)) {
      _windowStart = t;
      _count = 0;
      _reported = false;
    }
    _count++;
    if (_count >= threshold && !_reported) {
      _reported = true;
      return '渲染风暴: 1s 内丢帧 $_count 帧（renderer 持续丢弃 → 画面定格）';
    }
    return null;
  }

  /// 复位窗口（换集/停止时调用，避免跨媒体累计误报）。
  void reset() {
    _count = 0;
    _windowStart = null;
    _reported = false;
  }
}
