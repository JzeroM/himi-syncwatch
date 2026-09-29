import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 选中态图标/文字主色（青色，仅跟随水珠所在格的图标，水珠本体为透明玻璃）。
const Color kNavBlobColor = Color(0xFF2EE6C6);

/// 四标签底部导航内容（不含玻璃外壳）。
///
/// - 每格 icon+label 组在胶囊内上下左右严格居中，四格对齐
/// - 单个半透明水珠指示器：点击平滑移形；横向滑动或长按均可跟手拖动，
///   拖动中水珠所在格图标实时点亮青色，松手按落点切换
class ShellNavBar extends StatefulWidget {
  const ShellNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  State<ShellNavBar> createState() => _ShellNavBarState();
}

class _ShellNavBarState extends State<ShellNavBar>
    with SingleTickerProviderStateMixin {
  static const int _tabCount = 4;
  static const double _navHeight = 60;
  static const double _blobHeight = 50;

  static const List<String> _labels = ['首页', 'Emby服务器', '声网配置', '设置'];
  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.dns_outlined,
    Icons.key_outlined,
    Icons.settings_outlined,
  ];
  static const List<IconData> _selectedIcons = [
    Icons.home,
    Icons.dns,
    Icons.key,
    Icons.settings,
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  double _totalWidth = 0;
  double _navGlobalX = 0;

  /// 水珠中心（相对导航宽 0..1）。
  double _blobT = 0;

  /// 水珠宽度倍数（相对单格宽）。
  double _blobFactor = 1;

  double _fromT = 0;
  double _toT = 0;
  double _fromFactor = 1;
  double _peak = 0;
  bool _dragging = false;

  /// 抓取偏移（水珠中心 - 手指 x，相对导航左沿）。
  /// 手指落在当前水珠范围内时保持相对位置跟手，落在别格时吸附到手指。
  double _grabOffset = 0;

  static double _centerT(int index) => (index + 0.5) / _tabCount;

  /// 视觉激活格：以水珠中心所在格为准（拖动/飞行中实时跟随）。
  int get _activeIndex =>
      (_blobT * _tabCount).floor().clamp(0, _tabCount - 1);

  @override
  void initState() {
    super.initState();
    _blobT = _centerT(widget.currentIndex);
    _controller.addListener(_onTick);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ShellNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex &&
        !_dragging &&
        !_controller.isAnimating) {
      _animateTo(widget.currentIndex);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final raw = _controller.value;
    final p = Curves.easeOutBack.transform(raw);
    setState(() {
      _blobT = _fromT + (_toT - _fromT) * p;
      _blobFactor =
          (_fromFactor + (1 - _fromFactor) * p) + _peak * math.sin(math.pi * raw);
    });
  }

  void _animateTo(int index) {
    _fromT = _blobT;
    _fromFactor = _blobFactor;
    _toT = _centerT(index);
    final distanceTabs = (_toT - _fromT).abs() * _tabCount;
    _peak = distanceTabs.clamp(0.0, 2.0) * 0.22;
    _controller.forward(from: 0);
  }

  void _select(int index) {
    if (index != widget.currentIndex) widget.onSelect(index);
    _animateTo(index);
  }

  double _relativeX(double globalX) {
    if (_totalWidth <= 0) return 0;
    return (globalX - _navGlobalX).clamp(0.0, _totalWidth);
  }

  void _captureNavOrigin() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      _navGlobalX = box.localToGlobal(Offset.zero).dx;
    }
  }

  /// 进入拖动态（横向滑动或长按触发共用）。
  void _beginDrag(double globalX) {
    // 测试环境无振动通道实现，忽略失败
    HapticFeedback.mediumImpact().ignore();
    _captureNavOrigin();
    _controller.stop();
    final x = _relativeX(globalX);
    final center = _blobT * _totalWidth;
    final halfW = (_totalWidth / _tabCount) * _blobFactor / 2;
    _grabOffset = (x - center).abs() <= halfW ? center - x : 0;
    setState(() => _dragging = true);
    _applyDrag(x);
  }

  void _moveDrag(double globalX) {
    if (!_dragging) return;
    _applyDrag(_relativeX(globalX));
  }

  void _applyDrag(double x) {
    if (_totalWidth <= 0) return;
    final t = ((x + _grabOffset) / _totalWidth).clamp(0.0, 1.0);
    final tabW = _totalWidth / _tabCount;
    final offsetPx = (t - _centerT(widget.currentIndex)).abs() * _totalWidth;
    final factor = 1 + (offsetPx / (tabW * 2)).clamp(0.0, 1.0) * 0.6;
    setState(() {
      _blobT = t;
      _blobFactor = factor;
    });
  }

  /// 松手：按手指落点格切换（落点才切，拖动中途不回调）。
  void _endDrag(double globalX) {
    if (!_dragging) return;
    setState(() => _dragging = false);
    if (_totalWidth <= 0) return;
    final t = (_relativeX(globalX) / _totalWidth).clamp(0.0, 1.0);
    final index = (t * _tabCount).floor().clamp(0, _tabCount - 1);
    _select(index);
  }

  /// 拖动被系统/父级手势打断：结束拖动态并回到当前格。
  void _cancelDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    _animateTo(widget.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _totalWidth = constraints.maxWidth;
        final tabW = _totalWidth / _tabCount;
        final blobWidth = (tabW * _blobFactor).clamp(0.0, _totalWidth);
        final blobLeft = _blobT * _totalWidth - blobWidth / 2;

        return SizedBox(
          height: _navHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: blobLeft,
                top: (_navHeight - _blobHeight) / 2,
                width: blobWidth,
                height: _blobHeight,
                child: DecoratedBox(
                  key: const ValueKey('navBlob'),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius:
                        BorderRadius.all(Radius.circular(_blobHeight / 2)),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.10),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: List.generate(_tabCount, (i) {
                    final selected = i == _activeIndex;
                    final color = selected ? kNavBlobColor : Colors.white70;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _select(i),
                        onHorizontalDragStart: (d) =>
                            _beginDrag(d.globalPosition.dx),
                        onHorizontalDragUpdate: (d) =>
                            _moveDrag(d.globalPosition.dx),
                        onHorizontalDragEnd: (d) =>
                            _endDrag(d.globalPosition.dx),
                        onHorizontalDragCancel: _cancelDrag,
                        onLongPressStart: (d) =>
                            _beginDrag(d.globalPosition.dx),
                        onLongPressMoveUpdate: (d) =>
                            _moveDrag(d.globalPosition.dx),
                        onLongPressEnd: (d) => _endDrag(d.globalPosition.dx),
                        child: SizedBox(
                          height: _navHeight,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                selected ? _selectedIcons[i] : _icons[i],
                                size: 24,
                                color: color,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _labels[i],
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight:
                                      selected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
