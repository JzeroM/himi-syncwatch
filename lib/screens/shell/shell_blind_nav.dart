import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

/// 桌面宽度断点：≥ 此宽度走左侧百叶窗导航，否则回退底部胶囊导航。
const double kShellDesktopBreakpoint = 1000.0;

/// 桌面宽度下左侧导航项（与底部胶囊一致的四标签）。
const List<String> kShellNavLabels = ['首页', 'Emby服务器', '声网配置', '设置'];
const List<IconData> kShellNavIcons = [
  Icons.home_outlined,
  Icons.dns_outlined,
  Icons.key_outlined,
  Icons.settings_outlined,
];
const List<IconData> kShellNavSelectedIcons = [
  Icons.home,
  Icons.dns,
  Icons.key,
  Icons.settings,
];

/// 百叶窗风格桌面导航：左边缘吊绳 + 逐片翻开的抽屉。
///
/// - 吊绳常驻窗口左缘，点击拉绳 → 抽屉展开（容器先出底板，随后 5 片
///   内容以 rotateX 透视交错翻入，模拟百叶片依次翻开）
/// - 再点吊绳或点任一导航项 → 反向翻出收回
class ShellBlindNav extends StatefulWidget {
  const ShellBlindNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  State<ShellBlindNav> createState() => _ShellBlindNavState();
}

class _ShellBlindNavState extends State<ShellBlindNav>
    with TickerProviderStateMixin {
  static const double _panelWidth = 240;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    reverseDuration: const Duration(milliseconds: 330),
  );

  // 吊绳拉动手感（点按瞬间球体下移回弹）
  late final AnimationController _pullController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    _pullController.dispose();
    super.dispose();
  }

  bool get _expanded =>
      _controller.status == AnimationStatus.forward ||
      _controller.status == AnimationStatus.completed;

  void _toggle() {
    _pullController.forward(from: 0);
    if (_expanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  /// 第 i 片内容的翻入进度（0..1），交错区间保证逐片打开。
  double _sliceProgress(int index, int total) {
    final start = 0.12 + index * (0.44 / total);
    final interval =
        Interval(start, math.min(start + 0.40, 1.0), curve: Curves.easeOutCubic);
    return interval.transform(_controller.value);
  }

  Widget _buildSlice({
    required int index,
    required int total,
    required Widget child,
  }) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _sliceProgress(index, total);
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX((1 - t) * -1.25)
          ..translate((1 - t) * -36.0);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            transform: m,
            alignment: Alignment.centerLeft,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return _buildSlice(
      index: 0,
      total: 5,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HIMI',
              style: TextStyle(
                color: kNavBlobColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '同步观影',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(int index) {
    final selected = index == widget.currentIndex;
    return _buildSlice(
      index: index + 1,
      total: 5,
      child: _InkRipple(
        onTap: () {
          widget.onSelect(index);
          _controller.reverse();
        },
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? const Color(0x33FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                selected ? kShellNavSelectedIcons[index] : kShellNavIcons[index],
                size: 21,
                color: selected ? kNavBlobColor : Colors.white70,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  kShellNavLabels[index],
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, _pullController]),
      builder: (context, _) {
        final widthCurve = Interval(0, 0.45, curve: Curves.easeOutCubic)
            .transform(_controller.value);
        final width = _panelWidth * widthCurve;
        if (width <= 0.5) return const SizedBox.shrink();
        return SizedBox(
          width: width,
          key: const ValueKey('blindNavPanel'),
          child: _BlindPanelShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const Divider(height: 1, color: Colors.white10),
                for (var i = 0; i < kShellNavLabels.length; i++) ...[
                  _buildItem(i),
                  if (i < kShellNavLabels.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1, color: Colors.white10),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRope() {
    return Positioned(
      left: 4,
      top: 108,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: const ValueKey('blindNavRope'),
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: Listenable.merge([_controller, _pullController]),
            builder: (context, _) {
              return CustomPaint(
                size: const Size(30, 78),
                painter: _RopePainter(
                  pulling: Curves.easeOut.transform(_pullController.value),
                  expanded: _expanded,
                  hovered: _hovered,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _buildPanel(),
        ),
        _buildRope(),
      ],
    );
  }
}

/// 抽屉底板：暗色玻璃 + 百叶横纹分隔。
class _BlindPanelShell extends StatelessWidget {
  const _BlindPanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF01A1D23),
        border: Border(
          right: BorderSide(color: Color(0x33FFFFFF)),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 18, spreadRadius: 2),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

/// 简单按压水波（避免依赖 Scaffold Material）。
class _InkRipple extends StatefulWidget {
  const _InkRipple({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_InkRipple> createState() => _InkRippleState();
}

class _InkRippleState extends State<_InkRipple> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed ? const Color(0x14FFFFFF) : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// 吊绳：细绳 + 底部拉球；展开/悬停/拉动有颜色与位移反馈。
class _RopePainter extends CustomPainter {
  _RopePainter({
    required this.pulling,
    required this.expanded,
    required this.hovered,
  });

  final double pulling;
  final bool expanded;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final ballY = size.height - 10 + pulling * 6;
    final ropeColor = expanded
        ? kNavBlobColor.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: hovered ? 0.9 : 0.55);

    // 绳（略带弯曲）
    final path = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx + 2, size.height * 0.5, cx, ballY - 9);
    canvas.drawPath(
      path,
      Paint()
        ..color = ropeColor
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // 拉球
    final ballPaint = Paint()
      ..color = expanded
          ? kNavBlobColor
          : (hovered ? Colors.white : Colors.white70);
    canvas.drawCircle(Offset(cx, ballY), 9, ballPaint);
    canvas.drawCircle(
      Offset(cx, ballY),
      9,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    // 球面高光
    canvas.drawCircle(
      Offset(cx - 3, ballY - 3),
      2.4,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_RopePainter old) =>
      old.pulling != pulling ||
      old.expanded != expanded ||
      old.hovered != hovered;
}
