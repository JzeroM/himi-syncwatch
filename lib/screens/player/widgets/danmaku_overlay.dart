import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/danmaku/danmaku_clock.dart';
import '../../../services/danmaku/danmaku_comment.dart';
import '../../../services/danmaku/danmaku_timeline.dart';

/// 弹幕渲染层：Ticker 逐帧驱动，按播放位置查询 [DanmakuTimeline]
/// 活跃弹幕并绘制（纯参数 widget，不依赖 provider）。
///
/// - 挂载于播放器 Stack（视频层之上、控件之下），[IgnorePointer]
///   整层不参与命中测试，不抢视频手势；
/// - 位置源 [position]（进度轮询约 0.5s 一跳）由 Ticker 在两次跳变
///   间插值，seek（值突变）通过重建基准自动重对齐；
/// - 播放/暂停源 [playing]：暂停停走 Ticker（冻结），恢复重锚续滚；
/// - 时间轴在 comments/config/speed/宽度变化时才重建。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.comments,
    required this.config,
    required this.position,
    required this.playing,
    this.speed = 1.0,
    this.fontSizeScale = 1.0,
    this.opacity = 1.0,
    this.playbackRate = 1.0,
    this.colorMode = 'color',
    this.customColor = 0xFFFFFFFF,
    this.outlineWidth = 1.0,
    this.outlineColor = 0xFF000000,
  });

  /// 弹幕列表（解析后；空列表渲染空层）。
  final List<DanmakuComment> comments;

  /// 行数/屏蔽/上限配置（配置变化 → 时间轴重建）。
  final DanmakuTimelineConfig config;

  /// 播放位置源（seek 时值突变，overlay 自动重对齐）。
  final ValueListenable<Duration> position;

  /// 播放/暂停源：暂停时停走 Ticker（弹幕冻结），恢复时重锚续滚。
  final ValueListenable<bool> playing;

  /// 速度倍率（穿屏时长 = 8s ÷ speed）。
  final double speed;

  /// 字号倍率（基准 [baseFontSize]）。
  final double fontSizeScale;

  /// 整体不透明度 0~1。
  final double opacity;

  /// 播放速率（不是弹幕滚动速度）。投影必须乘它，否则非 1x 播放时
  /// 每来一次位置快照就会被拽前/拽后一下（真机表现为周期性抖动）。
  final double playbackRate;

  /// 颜色模式：`color`（源色）/ `white`（统一白）/ `custom`。
  final String colorMode;

  /// 自定义颜色（`0xAARRGGBB`，[colorMode] == custom 时生效）。
  final int customColor;

  /// 描边宽度（0~4，0 = 无描边）。
  final double outlineWidth;

  /// 描边颜色（`0xAARRGGBB`）。
  final int outlineColor;

  /// 弹幕基准字号（逻辑 px）。
  static const double baseFontSize = 25;

  /// 行间附加间距（逻辑 px）。
  static const double rowGap = 6;

  /// 顶/底安全边距（逻辑 px）。
  static const double edgePadding = 8;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// 播放时钟（锚点 + 单调时钟投影 + 死区/收敛，四端同构）。
  final DanmakuClock _clock = DanmakuClock();

  /// ticker 最近回调的经过时长（单调时钟，暂停时归零）。
  Duration _elapsed = Duration.zero;

  // 时间轴缓存（四元组变化才重建）
  List<DanmakuComment>? _tlComments;
  DanmakuTimelineConfig? _tlConfig;
  double? _tlSpeed;
  double? _tlWidth;
  DanmakuTimeline? _timeline;

  /// Text 测量缓存 `text|px → 宽度`。
  final Map<String, double> _measureCache = {};

  @override
  void initState() {
    super.initState();
    _clock.onAuthoritative(
      position: widget.position.value,
      monoUs: 0,
      paused: !widget.playing.value,
      baseRate: widget.playbackRate,
    );
    _ticker = createTicker((elapsed) {
      _elapsed = elapsed;
      setState(() {});
    });
    if (widget.playing.value) _ticker.start();
    widget.position.addListener(_onPositionChanged);
    widget.playing.addListener(_onPlayingChanged);
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.position, widget.position)) {
      old.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
      _onPositionChanged();
    }
    if (!identical(old.playing, widget.playing)) {
      old.playing.removeListener(_onPlayingChanged);
      widget.playing.addListener(_onPlayingChanged);
      _onPlayingChanged();
    }
    if (old.fontSizeScale != widget.fontSizeScale) {
      _measureCache.clear();
    }
    if (old.playbackRate != widget.playbackRate) {
      _clock.onAuthoritative(
        position: widget.position.value,
        monoUs: _elapsed.inMicroseconds,
        paused: !widget.playing.value,
        baseRate: widget.playbackRate,
      );
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPositionChanged);
    widget.playing.removeListener(_onPlayingChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    // 位置快照只是「权威值」；时钟自己决定是平滑收敛还是硬对齐。
    _clock.onAuthoritative(
      position: widget.position.value,
      monoUs: _elapsed.inMicroseconds,
      paused: !widget.playing.value,
      baseRate: widget.playbackRate,
    );
  }

  /// 播放/暂停切换：暂停停走 Ticker（冻结画面，位置不再推进）；恢复时
  /// 重锚到最新位置再启动——`Ticker.stop()` 会清 `_startTime`，重启后
  /// `elapsed` 从 0 计，故须同时归零 `_elapsed` 并让时钟按新基准重锚。
  void _onPlayingChanged() {
    final playing = widget.playing.value;
    if (playing) {
      if (!_ticker.isActive) {
        // Ticker 重启后 elapsed 从 0 计，时钟基准同步归零。
        _elapsed = Duration.zero;
        _ticker.start();
      }
      _clock.onAuthoritative(
        position: widget.position.value,
        monoUs: _elapsed.inMicroseconds,
        paused: false,
        baseRate: widget.playbackRate,
      );
      if (mounted) setState(() {});
    } else {
      _clock.onAuthoritative(
        position: widget.position.value,
        monoUs: _elapsed.inMicroseconds,
        paused: true,
        baseRate: widget.playbackRate,
      );
      if (_ticker.isActive) _ticker.stop();
    }
  }

  /// 当前播放位置 = 时钟投影（锚点 + 单调增量 × 速率，带死区/收敛）。
  Duration get _nowPosition => _clock.positionAt(_elapsed.inMicroseconds);

  DanmakuTimeline _timelineFor(double width, DanmakuTimelineConfig config) {
    final comments = widget.comments;
    final speed = widget.speed;
    if (_timeline != null &&
        identical(_tlComments, comments) &&
        _tlConfig == config &&
        _tlSpeed == speed &&
        _tlWidth == width) {
      return _timeline!;
    }
    _timeline = DanmakuTimeline(
      comments: comments,
      config: config,
      screenWidth: width,
      speed: speed,
    );
    _tlComments = comments;
    _tlConfig = config;
    _tlSpeed = speed;
    _tlWidth = width;
    return _timeline!;
  }

  double _textWidth(String text, double px) {
    final key = '$text|$px';
    final cached = _measureCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: px)),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    _measureCache[key] = width;
    return width;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (widget.comments.isEmpty || widget.opacity <= 0) {
            return const SizedBox.expand();
          }
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          if (!width.isFinite || !height.isFinite || width <= 0) {
            return const SizedBox.expand();
          }
          final px = DanmakuOverlay.baseFontSize * widget.fontSizeScale;
          final lineHeight = px + DanmakuOverlay.rowGap;
          // 方案 C：滚动弹幕按画面高度自动铺满，用户「滚动行数」为上限。
          final autoRows =
              ((height - DanmakuOverlay.edgePadding * 2) / lineHeight).floor();
          final effectiveScrollRows =
              autoRows.clamp(1, widget.config.scrollRows);
          final effectiveConfig =
              widget.config.copyWith(scrollRows: effectiveScrollRows);
          final active =
              _timelineFor(width, effectiveConfig).activeAt(_nowPosition);
          if (active.isEmpty) return const SizedBox.expand();

          final children = <Widget>[];
          for (final item in active) {
            final child = _buildItem(item, width, height, px, lineHeight);
            if (child != null) children.add(child);
          }
          return Stack(children: children);
        },
      ),
    );
  }

  Widget? _buildItem(
    ActiveDanmaku item,
    double width,
    double height,
    double px,
    double lineHeight,
  ) {
    final comment = item.comment;
    final textW = _textWidth(comment.text, px);
    double x;
    double y;
    double fade = 1.0;
    switch (comment.mode) {
      case DanmakuMode.scroll:
        // progress=0 前沿贴右缘外，progress=1 完全离开左缘
        x = width - item.progress * (width + textW);
        y = DanmakuOverlay.edgePadding + item.row * lineHeight;
      case DanmakuMode.top:
        x = (width - textW) / 2;
        y = DanmakuOverlay.edgePadding + item.row * lineHeight;
        fade = _fixedFade(item.progress);
      case DanmakuMode.bottom:
        x = (width - textW) / 2;
        y = height - DanmakuOverlay.edgePadding - (item.row + 1) * lineHeight;
        fade = _fixedFade(item.progress);
    }
    // 越界（行数超出画面高度）不绘制
    if (y < -px || y > height) return null;

    final baseAlpha = (widget.opacity.clamp(0.0, 1.0) * 255).round();
    final alpha = (baseAlpha * fade).round();
    if (alpha <= 0) return null;
    final int rgb = switch (widget.colorMode) {
      'white' => 0xFFFFFF,
      'custom' => widget.customColor & 0x00FFFFFF,
      _ => comment.color & 0x00FFFFFF,
    };
    final color = Color(rgb | (alpha << 24));
    final outlineAlpha =
        ((widget.outlineColor >> 24) & 0xFF) * (alpha / 255.0);
    final shadowColor = Color(
      (widget.outlineColor & 0x00FFFFFF) | (outlineAlpha.round() << 24),
    );
    return Positioned(
      left: x,
      top: y,
      child: Text(
        comment.text,
        maxLines: 1,
        style: TextStyle(
          fontSize: px,
          height: 1.2,
          color: color,
          fontWeight: FontWeight.w500,
          // 描边用多层阴影近似（Flutter 没有原生 stroke 文字）：
          // 宽度 0 → 无阴影；否则四向偏移 + 模糊，视觉上等同描边。
          shadows: widget.outlineWidth <= 0
              ? const []
              : [
                  Shadow(
                    color: shadowColor,
                    blurRadius: widget.outlineWidth * 1.5,
                    offset: Offset(widget.outlineWidth * 0.6, 0),
                  ),
                  Shadow(
                    color: shadowColor,
                    blurRadius: widget.outlineWidth * 1.5,
                    offset: Offset(-widget.outlineWidth * 0.6, 0),
                  ),
                  Shadow(
                    color: shadowColor,
                    blurRadius: widget.outlineWidth * 1.5,
                    offset: Offset(0, widget.outlineWidth * 0.6),
                  ),
                  Shadow(
                    color: shadowColor,
                    blurRadius: widget.outlineWidth * 1.5,
                    offset: Offset(0, -widget.outlineWidth * 0.6),
                  ),
                ],
        ),
      ),
    );
  }

  /// 固定弹幕淡入淡出（首尾各 10% 生命周期）。
  static double _fixedFade(double progress) {
    if (progress < 0.1) return progress / 0.1;
    if (progress > 0.9) return (1.0 - progress) / 0.1;
    return 1.0;
  }
}
