import 'package:flutter/material.dart';
import 'package:himi_syncwatch/utils/motion.dart';

/// 687：骨架屏——加载中的灰色占位块 + 微光扫过。
///
/// ## 为什么需要
///
/// 旧实现加载时显示 `CircularProgressIndicator`（转圈）或空白。
/// 转圈只说明「在加载」，不提示「即将出现什么」；骨架屏用形状预告
/// 内容布局，**感知速度明显更快**（用户看到结构就安心）。
///
/// ## 无障碍
///
/// 系统开启「减少动画」时微光动画停止，只显示静态灰块。
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = 6,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _shimmer.repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduced(context);
    final base = const Color(0x14FFFFFF);
    final highlight = const Color(0x26FFFFFF);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: reduce
            ? const SizedBox.shrink()
            : AnimatedBuilder(
                animation: _shimmer,
                builder: (context, _) {
                  // 微光从左扫到右
                  final t = _shimmer.value;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment(-1.5 + t * 3, 0),
                        end: Alignment(-0.5 + t * 3, 0),
                        colors: [base, highlight, base],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// 687：海报卡骨架（2:3 图 + 标题条 + 年份条）。
class SkeletonPosterCard extends StatelessWidget {
  const SkeletonPosterCard({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: width,
            height: width * 1.5,
            borderRadius: 12,
          ),
          const SizedBox(height: 8),
          SkeletonBox(width: width * 0.8, height: 11),
          const SizedBox(height: 5),
          SkeletonBox(width: width * 0.45, height: 9),
        ],
      ),
    );
  }
}

/// 687：海报网格骨架（一行 3 个，共 [rows] 行）。
class SkeletonPosterGrid extends StatelessWidget {
  const SkeletonPosterGrid({
    super.key,
    this.columns = 3,
    this.rows = 3,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(16),
  });

  final int columns;
  final int rows;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // 骨架屏不需要真实滚动，但必须可滚动容器——否则在受限高度下
      // `Column` 会 RenderFlex overflow（真机测试直接抛断言）。
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++) ...[
                Row(
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      SkeletonPosterCard(width: w),
                      if (c < columns - 1) SizedBox(width: spacing),
                    ],
                  ],
                ),
                if (r < rows - 1) SizedBox(height: spacing * 1.6),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 687：横向海报栏骨架（一行 N 个）。
class SkeletonPosterRow extends StatelessWidget {
  const SkeletonPosterRow({
    super.key,
    this.itemWidth = 110,
    this.count = 4,
    this.spacing = 12,
  });

  final double itemWidth;
  final int count;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemWidth * 1.5 + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (_, __) => SkeletonPosterCard(width: itemWidth),
      ),
    );
  }
}
