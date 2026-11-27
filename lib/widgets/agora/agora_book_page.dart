
import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/agora/agora_book_cover.dart';
import 'package:himi_syncwatch/utils/asset_image.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';

class AgoraGuideStep {
  const AgoraGuideStep({
    required this.title,
    required this.image,
    required this.description,
  });

  final String title;
  final String image;
  final String description;
}

const agoraGuideSteps = <AgoraGuideStep>[
  AgoraGuideStep(
    title: '注册登录并创建通用项目',
    image: 'assets/images/agora_step1.png',
    description: '访问 shengwang.cn 注册并登录\n'
        '创建项目时选择「通用项目」\n'
        '鉴权机制选择「APP ID + Token」',
  ),
  AgoraGuideStep(
    title: '开通体验版套餐包',
    image: 'assets/images/agora_step2.png',
    description: '套餐包 → RTM\n'
        '选择「体验版」（免费）',
  ),
  AgoraGuideStep(
    title: '开启 Presence 和 Storage',
    image: 'assets/images/agora_step3.png',
    description: '全部产品 → 实时消息 RTM → 基础配置\n'
        '启用「出席通知 (Presence)」\n'
        '启用「状态同步 (Storage)」\n'
        '数据存储区域选「中国」',
  ),
  AgoraGuideStep(
    title: '获取 APP ID 和证书',
    image: 'assets/images/agora_step4.png',
    description: '项目总览页 → 复制 APP ID\n'
        '展开查看主要证书 → 复制 APP Certificate\n'
        '翻到第 5 页 → 填入并保存',
  ),
];

class AgoraBookPaperPage extends StatelessWidget {
  const AgoraBookPaperPage({
    super.key,
    required this.index,
    required this.total,
    required this.palette,
    required this.kicker,
    required this.title,
    required this.child,
  });

  final int index;
  final int total;
  final AgoraBookPalette palette;
  final String kicker;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 698 N67：中间纸张比玻璃封面/底面小一圈（缩进 8px——夹心层次）。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Container(
      key: ValueKey('agoraBookPage_$index'),
      // 698 N68：白纸（参考图 1:1——横线格由 painter 画）。
      decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AgedPaperPainter(palette, seed: index),
              ),
            ),
          ),
          //（698 N65：书签飘带删除。）
          // 698 N68：燕尾箭头标签（参考图 1:1，每页一色）。
          Positioned(
            left: -22,
            top: 56,
            child: IgnorePointer(
              child: _RibbonTag(step: index + 1),
            ),
          ),
          // 698 N65：每页装订——顶缘线圈 + 装订孔（与封面同款同位）。
          Positioned(
            top: -6,
            left: 26,
            right: 26,
            child: const BindingRings(),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 17, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: palette.ink,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.foilDim,
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: palette.paperLight,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        kicker,
                        style: TextStyle(
                          color: palette.mutedInk,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: 0.2,
                    shadows: [
                      Shadow(
                        color: palette.paperLight.withValues(alpha: 0.5),
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: child),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 20,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.ink.withValues(alpha: 0.18),
                      palette.ink.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class AgoraBookGuidePage extends StatelessWidget {
  const AgoraBookGuidePage({
    super.key,
    required this.index,
    required this.total,
    required this.step,
    required this.palette,
    required this.onImageTap,
  });

  final int index;
  final int total;
  final AgoraGuideStep step;
  final AgoraBookPalette palette;
  final ValueChanged<String>? onImageTap;

  @override
  Widget build(BuildContext context) {
    return AgoraBookPaperPage(
      index: index,
      total: total,
      palette: palette,
      kicker: '步骤 ${index + 1} / $total',
      title: step.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              key: ValueKey('agoraBookImage_$index'),
              behavior: HitTestBehavior.opaque,
              onTap: onImageTap == null ? null : () => onImageTap!(step.image),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    palette.paperLight,
                    Colors.white,
                    0.55,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: palette.paperEdge.withValues(alpha: 0.75),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.ink.withValues(alpha: 0.14),
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox.expand(
                    // 681：按**显示宽度**解码（原图分辨率同步解码会阻塞
                    // 首帧 → 切声网标签明显掉帧）。
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return assetImage(
                          context,
                          step.image,
                          displayWidth: constraints.maxWidth,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(
                              '请将截图放到:\n${step.image}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.mutedInk,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.description,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.ink,
              fontSize: 12,
              height: 1.58,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                '点击截图可放大',
                style: TextStyle(
                  color: palette.mutedInk.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                '${(index + 1).toString().padLeft(2, '0')} · '
                '${total.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: palette.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 698 N68：横线格纸（参考图 1:1）——白纸 + 浅蓝灰横线格 + 右侧橙色
/// margin 竖线（替代做旧纸纹）。
class _AgedPaperPainter extends CustomPainter {
  const _AgedPaperPainter(this.palette, {required this.seed});

  final AgoraBookPalette palette;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // 白纸底。
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFFAFAFA));
    // 浅蓝灰横线格（行距 24，全页横贯）。
    final linePaint = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFFC8D4E0);
    for (var y = 40.0; y < size.height - 10; y += 24) {
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), linePaint);
    }
    // 右侧橙色 margin 竖线（距右 22%）。
    canvas.drawLine(
      Offset(size.width * 0.78, 24),
      Offset(size.width * 0.78, size.height - 12),
      Paint()
        ..strokeWidth = 1.5
        ..color = const Color(0xFFE8A838),
    );
  }

  @override
  bool shouldRepaint(covariant _AgedPaperPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class _RibbonTag extends StatelessWidget {
  const _RibbonTag({required this.step});

  final int step;

  static const _colors = [
    Color(0xFF1CA5B8), // 01 蓝绿
    Color(0xFFF0A020), // 02 橙
    Color(0xFFE8604C), // 03 珊瑚红
    Color(0xFF6C63C8), // 04 蓝紫
    Color(0xFF4CAF6E), // 05 绿
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colors[(step - 1).clamp(0, 4)];
    return SizedBox(
      width: 86,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 左侧丝带扣环（小矩形环）。
          Positioned(
            left: -8,
            top: 16,
            child: Container(
              width: 14,
              height: 22,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // 主体（圆角 + 右端箭头尖）。
          CustomPaint(
            size: const Size(86, 56),
            painter: _RibbonPainter(color),
          ),
          // 文字。
          Positioned.fill(
            left: 18,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const Text(
                  'STEP',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 燕尾形状（圆角主体 + 右端箭头尖）。
class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8, 4)
      ..lineTo(size.width - 18, 4)
      ..lineTo(size.width - 2, size.height / 2) // 右尖
      ..lineTo(size.width - 18, size.height - 4)
      ..lineTo(8, size.height - 4)
      ..quadraticBezierTo(0, size.height - 4, 0, size.height - 12)
      ..lineTo(0, 12)
      ..quadraticBezierTo(0, 4, 8, 4);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.12)!],
          ).createShader(Offset.zero & size));
    // 下方微阴影。
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
