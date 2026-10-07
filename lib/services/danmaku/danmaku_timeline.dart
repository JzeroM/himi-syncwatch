import 'danmaku_comment.dart';

/// 时间轴配置（纯数据；配置变化由调用方重建 [DanmakuTimeline]）。
class DanmakuTimelineConfig {
  /// 滚动弹幕行数（1~10）。
  final int scrollRows;

  /// 顶部弹幕行数（1~10）。
  final int topRows;

  /// 底部弹幕行数（1~10）。
  final int bottomRows;

  /// 屏蔽顶部/底部弹幕。
  final bool blockTop;
  final bool blockBottom;

  /// 屏蔽词（子串匹配，空串忽略）。
  final List<String> blockWords;

  /// 数量上限（null = 不限制；超限时按时间均匀采样保留）。
  final int? maxCount;

  const DanmakuTimelineConfig({
    this.scrollRows = 4,
    this.topRows = 4,
    this.bottomRows = 4,
    this.blockTop = false,
    this.blockBottom = false,
    this.blockWords = const [],
    this.maxCount,
  });

  @override
  bool operator ==(Object other) =>
      other is DanmakuTimelineConfig &&
      other.scrollRows == scrollRows &&
      other.topRows == topRows &&
      other.bottomRows == bottomRows &&
      other.blockTop == blockTop &&
      other.blockBottom == blockBottom &&
      other.maxCount == maxCount &&
      _listEquals(other.blockWords, blockWords);

  @override
  int get hashCode => Object.hash(
        scrollRows,
        topRows,
        bottomRows,
        blockTop,
        blockBottom,
        maxCount,
        Object.hashAll(blockWords),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 某时刻活跃的一条弹幕（渲染层直接消费）。
class ActiveDanmaku {
  final DanmakuComment comment;

  /// 轨道序号：滚动 0..scrollRows-1；顶部/底部各自独立轨道。
  final int row;

  /// 生命周期进度 0..1：0 = 刚出现，1 = 刚消失。
  /// 滚动弹幕 x 位置 = `screenW - progress * (screenW + textW)`。
  final double progress;

  const ActiveDanmaku({
    required this.comment,
    required this.row,
    required this.progress,
  });
}

/// 弹幕时间轴：过滤 → 排序 → 轨道预分配 → 按位置查询（纯 Dart，可测）。
///
/// 轨道表在构造时一次性预计算（与当前位置无关），因此 **seek 前后
/// `activeAt` 结果由位置唯一决定**，无需显式重置：回退到过去只会
/// 重新显示当时的弹幕，快进则直接跳到目标时刻的活跃集合。
///
/// 冲突模型（同速不追尾）：滚动弹幕占用轨道直到「完全进入屏幕」
/// （前沿越过左缘）+ 0.15s 间隙；估算宽度按 CJK/ASCII 混排近似。
class DanmakuTimeline {
  /// 滚动穿屏基准时长（秒）；实际 = 基准 ÷ speed。
  static const double scrollBaseSeconds = 8;

  /// 顶部/底部固定弹幕展示时长（秒，不受速度影响）。
  static const double fixedSeconds = 4;

  /// 同轨道相邻弹幕间隙（秒）。
  static const double trackGapSeconds = 0.15;

  final DanmakuTimelineConfig config;
  final double screenWidth;
  final double fontSize;
  final double speed;

  /// 过滤+排序后的弹幕及各自轨道（构造时预计算）。
  late final List<_Assignment> _assignments;

  /// 过滤后总数（测试/统计用）。
  int get totalCount => _assignments.length;

  /// 过滤后弹幕列表（按时间升序）。
  List<DanmakuComment> get filtered =>
      [for (final a in _assignments) a.comment];

  DanmakuTimeline({
    required List<DanmakuComment> comments,
    required this.config,
    required this.screenWidth,
    this.fontSize = 25,
    this.speed = 1.0,
  }) {
    final kept = _filter(comments, config);
    final scrollAvail = List<double>.filled(config.scrollRows, 0);
    final topAvail = List<double>.filled(config.topRows, 0);
    final bottomAvail = List<double>.filled(config.bottomRows, 0);
    final assignments = <_Assignment>[];

    for (final comment in kept) {
      final row = switch (comment.mode) {
        DanmakuMode.scroll =>
          _pickRow(scrollAvail, comment.time, _occupancySeconds(comment)),
        DanmakuMode.top =>
          _pickRow(topAvail, comment.time, fixedSeconds + trackGapSeconds),
        DanmakuMode.bottom =>
          _pickRow(bottomAvail, comment.time, fixedSeconds + trackGapSeconds),
      };
      if (row < 0) continue; // 轨道满 → 丢弃
      assignments.add(_Assignment(comment, row));
    }
    _assignments = assignments;
  }

  /// 过滤链：顶底屏蔽 → 屏蔽词 → 数量均匀采样 → 按时间升序。
  static List<DanmakuComment> _filter(
    List<DanmakuComment> comments,
    DanmakuTimelineConfig config,
  ) {
    var list = comments.where((c) {
      if (config.blockTop && c.mode == DanmakuMode.top) return false;
      if (config.blockBottom && c.mode == DanmakuMode.bottom) return false;
      for (final word in config.blockWords) {
        if (word.isNotEmpty && c.text.contains(word)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    final maxCount = config.maxCount;
    if (maxCount != null && maxCount > 0 && list.length > maxCount) {
      list = _sampleEvenly(list, maxCount);
    }
    return list;
  }

  /// 按索引等间隔采样保留 [keep] 条（确定性，保留首条）。
  static List<DanmakuComment> _sampleEvenly(
    List<DanmakuComment> list,
    int keep,
  ) {
    final total = list.length;
    final out = <DanmakuComment>[];
    for (var i = 0; i < keep; i++) {
      out.add(list[(i * total) ~/ keep]);
    }
    return out;
  }

  /// 在 [avail] 轨道表中挑一条在 [time] 时已空闲的轨道；
  /// 无可用轨道返回 -1（该弹幕被丢弃）。占用到 `time + occupancy`。
  static int _pickRow(List<double> avail, double time, double occupancy) {
    for (var row = 0; row < avail.length; row++) {
      if (avail[row] <= time) {
        avail[row] = time + occupancy;
        return row;
      }
    }
    return -1;
  }

  /// 滚动弹幕轨道占用时长：直到完全进入屏幕（前沿越过左缘）+ 间隙。
  double _occupancySeconds(DanmakuComment comment) {
    final duration = scrollBaseSeconds / speed;
    final textW = estimateTextWidth(comment.text, fontSize);
    final fullyEnteredProgress =
        textW <= 0 ? 0.0 : textW / (screenWidth + textW);
    return duration * fullyEnteredProgress + trackGapSeconds;
  }

  /// 滚动弹幕穿屏时长（秒）= 基准 ÷ speed。
  double get scrollDurationSeconds => scrollBaseSeconds / speed;

  /// [position] 时刻活跃的弹幕集合（含轨道与进度）。
  List<ActiveDanmaku> activeAt(Duration position) {
    final posSec = position.inMicroseconds / 1e6;
    final scrollDur = scrollDurationSeconds;
    final out = <ActiveDanmaku>[];
    for (final a in _assignments) {
      final comment = a.comment;
      final duration =
          comment.mode == DanmakuMode.scroll ? scrollDur : fixedSeconds;
      final delta = posSec - comment.time;
      if (delta < 0 || delta >= duration) continue;
      out.add(ActiveDanmaku(
        comment: comment,
        row: a.row,
        progress: delta / duration,
      ));
    }
    return out;
  }

  /// 估算文本宽度（逻辑 px）：CJK/全角按 1.0×字号，其余按 0.55×。
  static double estimateTextWidth(String text, double fontSize) {
    var units = 0.0;
    for (final rune in text.runes) {
      final isWide = rune >= 0x1100 &&
          (rune <= 0x115F ||
              rune == 0x2329 ||
              rune == 0x232A ||
              (rune >= 0x2E80 && rune <= 0xA4CF && rune != 0x303F) ||
              (rune >= 0xAC00 && rune <= 0xD7A3) ||
              (rune >= 0xF900 && rune <= 0xFAFF) ||
              (rune >= 0xFE30 && rune <= 0xFE4F) ||
              (rune >= 0xFF00 && rune <= 0xFF60) ||
              (rune >= 0xFFE0 && rune <= 0xFFE6));
      units += isWide ? 1.0 : 0.55;
    }
    return units * fontSize;
  }
}

/// 内部：弹幕 + 预分配轨道。
class _Assignment {
  final DanmakuComment comment;
  final int row;
  const _Assignment(this.comment, this.row);
}
