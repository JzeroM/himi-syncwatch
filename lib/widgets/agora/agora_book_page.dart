import 'dart:math' as math;

import 'package:flutter/material.dart';
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
    return Container(
      key: ValueKey('agoraBookPage_$index'),
      decoration: BoxDecoration(gradient: palette.paperGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AgedPaperPainter(palette, seed: index),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 26,
            child: IgnorePointer(
              child: _PageBookmark(
                key: ValueKey('agoraBookBookmark_$index'),
                palette: palette,
              ),
            ),
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
                          fontSize: 10.5,
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
                    fontSize: 17.5,
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
                    child: Image.asset(
                      step.image,
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
              fontSize: 12.3,
              height: 1.48,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                '点击截图可放大',
                style: TextStyle(
                  color: palette.mutedInk.withValues(alpha: 0.8),
                  fontSize: 9.5,
                ),
              ),
              const Spacer(),
              Text(
                '${(index + 1).toString().padLeft(2, '0')} · '
                '${total.toString().padLeft(2, '0')}',
                style: TextStyle(
                  color: palette.mutedInk,
                  fontSize: 9.5,
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

class _PageBookmark extends StatelessWidget {
  const _PageBookmark({
    super.key,
    required this.palette,
  });

  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(15, 54),
      painter: _PageBookmarkPainter(palette),
    );
  }
}

class _PageBookmarkPainter extends CustomPainter {
  const _PageBookmarkPainter(this.palette);

  final AgoraBookPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 8)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path.shift(const Offset(1, 1.4)),
      Paint()
        ..color = palette.ink.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.ribbon.withValues(alpha: 0.78),
            palette.ribbon,
            palette.ribbon.withValues(alpha: 0.66),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawLine(
      const Offset(1, 1),
      Offset(size.width - 1, 1),
      Paint()
        ..color = palette.paperLight.withValues(alpha: 0.25)
        ..strokeWidth = 0.8,
    );
    canvas.drawLine(
      Offset(size.width / 2, 4),
      Offset(size.width / 2, size.height - 10),
      Paint()
        ..color = palette.ink.withValues(alpha: 0.14)
        ..strokeWidth = 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant _PageBookmarkPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _AgedPaperPainter extends CustomPainter {
  const _AgedPaperPainter(this.palette, {required this.seed});

  final AgoraBookPalette palette;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(0x9E37 + seed * 7919);

    final fiber = Paint()
      ..strokeWidth = 0.5
      ..color = palette.ink.withValues(alpha: 0.035);
    for (var y = 10.0; y < size.height; y += 8.5) {
      final x2 = size.width * (0.55 + random.nextDouble() * 0.45);
      canvas.drawLine(Offset(0, y), Offset(x2, y), fiber);
    }

    for (var i = 0; i < 7; i++) {
      final center = Offset(
        10 + random.nextDouble() * (size.width - 20),
        12 + random.nextDouble() * (size.height - 24),
      );
      canvas.drawCircle(
        center,
        0.6 + random.nextDouble() * 2.1,
        Paint()
          ..color = palette.mutedInk
              .withValues(alpha: 0.025 + random.nextDouble() * 0.035),
      );
    }

    final stain = Paint()
      ..color = palette.paperEdge.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final stainCenter = Offset(
      size.width * (0.62 + random.nextDouble() * 0.22),
      size.height * (0.16 + random.nextDouble() * 0.24),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: stainCenter,
        width: 18 + random.nextDouble() * 26,
        height: 8 + random.nextDouble() * 14,
      ),
      stain,
    );

    final edge = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          palette.paperDark.withValues(alpha: 0.22),
          Colors.transparent,
          palette.paperDark.withValues(alpha: 0.14),
        ],
        stops: const [0, 0.18, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, edge);
  }

  @override
  bool shouldRepaint(covariant _AgedPaperPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.seed != seed;
}
