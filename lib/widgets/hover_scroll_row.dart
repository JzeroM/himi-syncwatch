import 'package:flutter/material.dart';

/// 首页横向栏：桌面（鼠标）悬停时左右显示翻页箭头。
///
/// - 未悬停 / 内容不足一屏 → 两箭头都隐藏；
/// - 悬停在最左 → 只显示右箭头；在最右 → 只显示左箭头；中间 → 两边都显示；
/// - 箭头叠在栏上（不占布局），点击按视口宽 ~0.8 翻页。
///
/// 手机/TV 无鼠标悬停，箭头不出现，触摸拖动 / 焦点滚动行为不变。
class HoverScrollRow extends StatefulWidget {
  const HoverScrollRow({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.clipBehavior = Clip.none,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;

  /// TV 焦点框 1.06 放大溢出内容盒，默认 `Clip.none` 不裁上下边。
  final Clip clipBehavior;

  @override
  State<HoverScrollRow> createState() => _HoverScrollRowState();
}

class _HoverScrollRowState extends State<HoverScrollRow> {
  final ScrollController _controller = ScrollController();
  bool _hovered = false;
  bool _showLeft = false;
  bool _showRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_recompute);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void didUpdateWidget(covariant HoverScrollRow old) {
    super.didUpdateWidget(old);
    if (old.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_recompute);
    _controller.dispose();
    super.dispose();
  }

  bool get _canScroll =>
      _controller.hasClients && _controller.position.maxScrollExtent > 0.5;

  void _recompute() {
    if (!mounted) return;
    final canScroll = _canScroll;
    final offset = canScroll ? _controller.offset : 0.0;
    final maxExtent = canScroll ? _controller.position.maxScrollExtent : 0.0;
    final showLeft = _hovered && canScroll && offset > 1.0;
    final showRight = _hovered && canScroll && offset < maxExtent - 1.0;
    if (showLeft != _showLeft || showRight != _showRight) {
      setState(() {
        _showLeft = showLeft;
        _showRight = showRight;
      });
    }
  }

  void _onHover(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    _recompute();
  }

  void _scrollBy(double direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final page = position.viewportDimension * 0.8;
    final target = (_controller.offset + direction * page)
        .clamp(0.0, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _arrow({required bool left}) {
    return Positioned(
      left: left ? 4 : null,
      right: left ? null : 4,
      top: 0,
      bottom: 0,
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey(left ? 'scrollArrowLeft' : 'scrollArrowRight'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _scrollBy(left ? -1 : 1),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(
                left ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: SizedBox(
        width: double.infinity,
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: (_) {
                  _recompute();
                  return false;
                },
                child: ListView.builder(
                  controller: _controller,
                  clipBehavior: widget.clipBehavior,
                  scrollDirection: Axis.horizontal,
                  padding: widget.padding,
                  itemCount: widget.itemCount,
                  itemBuilder: widget.itemBuilder,
                ),
              ),
            ),
            if (_showLeft) _arrow(left: true),
            if (_showRight) _arrow(left: false),
          ],
        ),
      ),
    );
  }
}
