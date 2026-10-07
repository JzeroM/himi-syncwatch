import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/danmaku/danmaku_comment.dart';
import '../../../services/danmaku/danmaku_timeline.dart';

/// 弹幕渲染层：Ticker 逐帧驱动，按播放位置查询 [DanmakuTimeline]
/// 活跃弹幕并绘制（纯参数 widget，不依赖 provider）。
///
/// - 挂载于播放器 Stack（视频层之上、控件之下），[IgnorePointer]
///   整层不参与命中测试，不抢视频手势；
/// - 位置源 [position]（进度轮询约 0.5s 一跳）由 Ticker 在两次跳变
///   间插值，seek（值突变）通过重建基准自动重对齐；
/// - 时间轴在 comments/config/speed/宽度变化时才重建。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.comments,
    required this.config,
    required this.position,
    this.speed = 1.0,
    this.fontSizeScale = 1.0,
    this.opacity = 1.0,
  });

  /// 弹幕列表（解析后；空列表渲染空层）。
  final List<DanmakuComment> comments;

  /// 行数/屏蔽/上限配置（配置变化 → 时间轴重建）。
  final DanmakuTimelineConfig config;

  /// 播放位置源（seek 时值突变，overlay 自动重对齐）。
  final ValueListenable<Duration> position;

  /// 速度倍率（穿屏时长 = 8s ÷ speed）。
  final double speed;

  /// 字号倍率（基准 [baseFontSize]）。
  final double fontSizeScale;

  /// 整体不透明度 0~1。
  final double opacity;

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

  /// 最近一次 position 跳变值。
  Duration _lastPosition = Duration.zero;

  /// 与 [lastPosition] 对齐时的 ticker 经过时长。
  Duration _alignElapsed = Duration.zero;

  /// ticker 最近回调的经过时长。
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
    _lastPosition = widget.position.value;
    _ticker = createTicker((elapsed) {
      _elapsed = elapsed;
      setState(() {});
    })
      ..start();
    widget.position.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.position, widget.position)) {
      old.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
      _onPositionChanged();
    }
    if (old.fontSizeScale != widget.fontSizeScale) {
      _measureCache.clear();
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPositionChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    _lastPosition = widget.position.value;
    _alignElapsed = _elapsed;
  }

  /// 当前插值播放位置 = 最近跳变值 + 对齐后的 ticker 增量。
  Duration get _nowPosition => _lastPosition + (_elapsed - _alignElapsed);

  DanmakuTimeline _timelineFor(double width) {
    final comments = widget.comments;
    final config = widget.config;
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
          final active = _timelineFor(width).activeAt(_nowPosition);
          if (active.isEmpty) return const SizedBox.expand();

          final px = DanmakuOverlay.baseFontSize * widget.fontSizeScale;
          final lineHeight = px + DanmakuOverlay.rowGap;
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
    final color = Color(
      (comment.color & 0x00FFFFFF) | (alpha << 24),
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
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 3),
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
