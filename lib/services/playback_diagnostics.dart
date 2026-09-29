/// 播放卡顿诊断：时间线采样 + 卡顿事件统计 + 文本导出。
///
/// 纯 Dart 实现，不依赖 mdk / Flutter，便于单元测试。
/// 所有状态在 [reset] 时清空；切集、seek 回退、重新加载时自动重置。
library;

/// 单个采样点。
class DiagSample {
  /// 距离本次会话开始的毫秒数
  final int t;
  /// 播放位置（ms）
  final int pos;
  /// 播放头前方的已缓冲时长（ms），约等于 fvp `Player.buffered()` 的返回值。
  /// 接近 0 表示即将欠载；fvp 返回的是时长而非绝对缓冲终点，
  /// 因此不可再减去 [pos]。
  final int ahead;
  /// 播放状态文本
  final String state;
  /// 媒体状态文本
  final String status;
  /// 实测帧率，未开启深度诊断时为 null
  final double? fps;

  const DiagSample({
    required this.t,
    required this.pos,
    required this.ahead,
    required this.state,
    required this.status,
    this.fps,
  });
}

/// 一次卡顿（缓冲中断）事件。
class StallEvent {
  /// 事件开始时距离会话开始的毫秒数
  final int t;
  /// 持续时长（ms）
  final int durationMs;
  /// 类型：buffering / underflow / seek
  final String type;

  const StallEvent({
    required this.t,
    required this.durationMs,
    required this.type,
  });
}

class PlaybackDiagnostics {
  /// 采样点容量：250ms × 2400 ≈ 10 分钟
  static const int maxSamples = 2400;
  /// 卡顿事件容量
  static const int maxStalls = 300;
  /// mdk 事件原文保留条数
  static const int maxEvents = 200;
  /// 计入卡顿的最小持续时长（ms），低于此值视为正常 seek / 切轨抖动
  static const int stallThresholdMs = 150;
  /// 位置回退超过此值（ms）判定为 seek，自动重置
  static const int seekResetThresholdMs = 1000;
  /// 导出时间线的最大行数
  static const int exportMaxRows = 240;
  /// 降采样时保留的首行数
  static const int exportHeadRows = 30;
  /// 降采样时保留的尾行数
  static const int exportTailRows = 60;

  final DateTime Function() _clock;

  final List<DiagSample> _samples = <DiagSample>[];
  final List<StallEvent> _stalls = <StallEvent>[];
  final List<String> _events = <String>[];

  DateTime? _sessionStart;
  int? _stallStartT;
  String? _stallType;
  int _minAhead = 1 << 30;
  int _minAheadT = 0;
  double? _latestFps;
  final List<String> _notes = <String>[];

  PlaybackDiagnostics({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  int get sampleCount => _samples.length;
  int get stallCount => _stalls.length;
  int get stallTotalMs => _stalls.fold(0, (s, e) => s + e.durationMs);
  int get stallMaxMs =>
      _stalls.isEmpty ? 0 : _stalls.map((e) => e.durationMs).reduce((a, b) => a > b ? a : b);
  /// 播放头前方的最小缓冲余量（ms），无采样时为 null。
  int? get minAheadMs => _samples.isEmpty ? null : _minAhead;
  int get minAheadAtMs => _minAheadT;
  double? get latestFps => _latestFps;
  List<StallEvent> get stalls => List.unmodifiable(_stalls);
  List<String> get notes => List.unmodifiable(_notes);

  /// 距离会话开始的毫秒数，未开始时为 0。
  int get elapsedMs {
    final start = _sessionStart;
    if (start == null) return 0;
    return _clock().difference(start).inMilliseconds;
  }

  void reset() {
    _samples.clear();
    _stalls.clear();
    _events.clear();
    _notes.clear();
    _sessionStart = null;
    _stallStartT = null;
    _stallType = null;
    _minAhead = 1 << 30;
    _minAheadT = 0;
    _latestFps = null;
  }

  /// 记录一个采样点。
  ///
  /// [reloading] 由调用方根据 mdk 状态计算，表示当前正在卸载/加载媒体。
  /// 检测到 seek 回退或重新加载时自动重置整个会话，避免跨集污染数据。
  void addSample({
    required int pos,
    required int buffered,
    required String state,
    required String status,
    bool reloading = false,
  }) {
    if (_sessionStart == null) _sessionStart = _clock();

    if (_samples.isNotEmpty) {
      final last = _samples.last;
      final seekedBack = pos < last.pos - seekResetThresholdMs;
      if (seekedBack || reloading) {
        reset();
        _sessionStart = _clock();
      }
    }

    // fvp 的 buffered() 返回"播放头前方的已缓冲时长"，
    // 已是从当前位置算起的余量，不可再减 pos（曾导致 -257000ms 之类假值）。
    final ahead = buffered < 0 ? 0 : buffered;
    if (_samples.isEmpty || ahead < _minAhead) {
      _minAhead = ahead;
      _minAheadT = elapsedMs;
    }

    _samples.add(DiagSample(
      t: elapsedMs,
      pos: pos,
      ahead: ahead,
      state: state,
      status: status,
      fps: _latestFps,
    ));
    if (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// 记录一次卡顿开始（幂等：已在计时中时忽略）。
  void onStallStart(String type) {
    if (_stallStartT != null) return;
    _stallStartT = elapsedMs;
    _stallType = type;
  }

  /// 结束计时，达标则记入卡顿列表。
  void onStallEnd() {
    final startT = _stallStartT;
    if (startT == null) return;
    final dur = elapsedMs - startT;
    final type = _stallType ?? 'buffering';
    _stallStartT = null;
    _stallType = null;
    if (dur < stallThresholdMs) return;
    _stalls.add(StallEvent(t: startT, durationMs: dur, type: type));
    if (_stalls.length > maxStalls) _stalls.removeAt(0);
  }

  /// 当前是否正在卡顿计时中。
  bool get isStalling => _stallStartT != null;

  /// 卡顿计时超过该时长（ms）视为状态上报丢失，强制结算，避免一直挂着。
  static const int stallStaleGuardMs = 5000;

  /// 若卡顿计时已超时则强制结算。由采样循环调用，
  /// 兜底 onMediaStatus 边沿丢失的情况（如状态位未翻转）。
  void reapStaleStall() {
    if (_stallStartT == null) return;
    if (currentStallMs >= stallStaleGuardMs) {
      onStallEnd();
    }
  }

  /// 记录当前正在进行的卡顿已持续多久（未卡顿时为 0）。
  int get currentStallMs {
    final startT = _stallStartT;
    if (startT == null) return 0;
    return elapsedMs - startT;
  }

  /// 更新实测帧率（来自深度诊断日志）。
  void updateFps(double? fps) {
    if (fps == null || fps <= 0) return;
    _latestFps = fps;
  }

  /// 附加一条诊断说明（例如解码线程重启、解码错误），最多保留 50 条。
  void note(String message) {
    final t = elapsedMs;
    _notes.add('t=${(t / 1000).toStringAsFixed(0)}s $message');
    if (_notes.length > 50) _notes.removeAt(0);
  }

  /// 记录一条 mdk 运行时事件原文（category/detail/error）。
  /// 事件语义官方未完整文档化，保留原文以便真机确认，保留最近 [maxEvents] 条。
  void addEvent(String category, String detail, int error) {
    _events.add('t=${(elapsedMs / 1000).toStringAsFixed(0)}s '
        '$category | $detail | $error');
    if (_events.length > maxEvents) _events.removeAt(0);
  }

  /// 导出 mdk 事件原文。
  String exportEvents() {
    if (_events.isEmpty) return '(无 mdk 事件)\n';
    return '${_events.join('\n')}\n';
  }

  /// 汇总摘要（用于面板展示与导出）。
  String summary() {
    final sb = StringBuffer()
      ..writeln('卡顿次数: $stallCount')
      ..writeln('累计卡顿: ${stallTotalMs}ms')
      ..writeln('最长卡顿: ${stallMaxMs}ms')
      ..writeln('最小缓冲余量: ${minAheadMs == null ? '-' : '${minAheadMs}ms @ ${(minAheadAtMs / 1000).toStringAsFixed(0)}s'}')
      ..writeln('采样点: $sampleCount (每 250ms)')
      ..writeln('已播放: ${(elapsedMs / 1000).toStringAsFixed(0)}s');
    if (isStalling) {
      sb.writeln('当前卡顿中: ${currentStallMs}ms');
    }
    if (_latestFps != null) {
      sb.writeln('实测帧率: ${_latestFps!.toStringAsFixed(1)}');
    } else {
      sb.writeln('实测帧率: - (需开启深度诊断)');
    }
    return sb.toString();
  }

  /// 导出时间线表格。样本过多时降采样，保留首尾细节。
  String exportTimeline({int maxRows = exportMaxRows}) {
    if (_samples.isEmpty) return 't(s)  ahead(ms)  state  status  fps\n(无采样数据)\n';
    final rows = _downsample(_samples, maxRows);
    final sb = StringBuffer()
      ..writeln('t(s)  ahead(ms)  state  status  fps');
    for (final s in rows) {
      sb.writeln('${(s.t / 1000).toStringAsFixed(0).padLeft(4)}  '
          '${s.ahead.toString().padLeft(8)}  '
          '${s.state.padRight(9)} '
          '${s.status.padRight(14)} '
          '${s.fps?.toStringAsFixed(1) ?? '-'}');
    }
    return sb.toString();
  }

  /// 导出卡顿事件列表。
  String exportStalls() {
    if (_stalls.isEmpty) return '(无卡顿记录)\n';
    final sb = StringBuffer()..writeln('t(s)  时长(ms)  类型');
    for (final e in _stalls) {
      sb.writeln('${(e.t / 1000).toStringAsFixed(0).padLeft(4)}  '
          '${e.durationMs.toString().padLeft(8)}  ${e.type}');
    }
    return sb.toString();
  }

  /// 导出诊断备注。
  String exportNotes() {
    if (_notes.isEmpty) return '(无诊断事件)\n';
    return '${_notes.join('\n')}\n';
  }

  /// 降采样：保留前 [exportHeadRows] 行、后 [exportTailRows] 行，
  /// 中间按预算等间隔抽取。
  static List<DiagSample> _downsample(List<DiagSample> src, int maxRows) {
    if (src.length <= maxRows) return src;

    var head = exportHeadRows;
    if (head > maxRows) head = maxRows;
    var tail = exportTailRows;
    if (head + tail >= maxRows) tail = maxRows - head;

    // 首尾窗口不能重叠覆盖整个样本集
    if (head + tail > src.length) {
      head = src.length ~/ 2;
      tail = src.length - head;
    }

    final midBudget = maxRows - head - tail;
    final midEnd = src.length - tail;
    final result = <DiagSample>[];
    for (var i = 0; i < head; i++) {
      result.add(src[i]);
    }
    if (midBudget > 0 && midEnd > head) {
      final span = midEnd - head;
      for (var i = 0; i < midBudget; i++) {
        result.add(src[head + (i * span) ~/ midBudget]);
      }
    }
    for (var i = midEnd; i < src.length; i++) {
      result.add(src[i]);
    }
    return result;
  }
}
