import 'dart:math' as math;

import 'package:flutter/material.dart';

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
        '填入输入框 → 点击保存',
  ),
];

class AgoraGuideBook extends StatefulWidget {
  const AgoraGuideBook({
    super.key,
    this.steps = agoraGuideSteps,
    this.onImageTap,
  });

  final List<AgoraGuideStep> steps;
  final ValueChanged<String>? onImageTap;

  @override
  State<AgoraGuideBook> createState() => _AgoraGuideBookState();
}

class _AgoraGuideBookState extends State<AgoraGuideBook> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= widget.steps.length) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 440),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('agoraGuideBook'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 0.72,
          child: _BookShell(
            steps: widget.steps,
            controller: _controller,
            currentPage: _page,
            onPageChanged: (page) => setState(() => _page = page),
            onImageTap: widget.onImageTap,
          ),
        ),
        const SizedBox(height: 8),
        _BookControls(
          page: _page,
          total: widget.steps.length,
          onPrevious: () => _goTo(_page - 1),
          onNext: () => _goTo(_page + 1),
          onSelect: _goTo,
        ),
      ],
    );
  }
}

class _BookShell extends StatelessWidget {
  const _BookShell({
    required this.steps,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.onImageTap,
  });

  final List<AgoraGuideStep> steps;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String>? onImageTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: 10,
          left: 5,
          right: 3,
          bottom: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.46),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF472A5A), Color(0xFF24132F)],
            ),
            border: Border.all(
              color: const Color(0xFFD8B26B).withValues(alpha: 0.48),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(11, 11, 20, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BookSpine(),
              const SizedBox(width: 9),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned(
                      top: 6,
                      right: -7,
                      bottom: 6,
                      child: _PageStack(),
                    ),
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: PageView.builder(
                          key: const ValueKey('agoraBookPageView'),
                          controller: controller,
                          itemCount: steps.length,
                          allowImplicitScrolling: true,
                          onPageChanged: onPageChanged,
                          itemBuilder: (context, index) {
                            return _TurnablePage(
                              index: index,
                              currentPage: currentPage,
                              controller: controller,
                              child: _GuidePage(
                                index: index,
                                total: steps.length,
                                step: steps[index],
                                onImageTap: onImageTap,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Positioned(
          top: -7,
          right: 42,
          child: IgnorePointer(child: _Bookmark()),
        ),
      ],
    );
  }
}

class _BookSpine extends StatelessWidget {
  const _BookSpine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF1A0D24),
            Color(0xFF563769),
            Color(0xFF2A1637),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFD8B26B).withValues(alpha: 0.24),
        ),
      ),
      child: const Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            'HIMI',
            style: TextStyle(
              color: Color(0xFFD8B26B),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageStack extends StatelessWidget {
  const _PageStack();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PageEdge(color: const Color(0xFFDCC9A8), width: 3),
        _PageEdge(color: const Color(0xFFEBDCC2), width: 2),
        _PageEdge(color: const Color(0xFFF7EBD8), width: 2),
      ],
    );
  }
}

class _PageEdge extends StatelessWidget {
  const _PageEdge({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: double.infinity,
      margin: const EdgeInsets.only(left: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Bookmark extends StatelessWidget {
  const _Bookmark();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(16, 40),
      painter: _BookmarkPainter(),
    );
  }
}

class _BookmarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 7)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFC24E5A),
    );
    canvas.drawLine(
      const Offset(0, 1),
      Offset(size.width, 1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TurnablePage extends StatelessWidget {
  const _TurnablePage({
    required this.index,
    required this.currentPage,
    required this.controller,
    required this.child,
  });

  final int index;
  final int currentPage;
  final PageController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        if (index != currentPage ||
            !controller.hasClients ||
            !controller.position.hasContentDimensions) {
          return child!;
        }
        final page = controller.page ?? currentPage.toDouble();
        final progress = (page - currentPage).clamp(-1.0, 1.0);
        if (progress.abs() < 0.001) return child!;

        final angle = progress * math.pi * 0.42;
        return Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateY(-angle),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(
                          alpha: 0.22 * progress.abs(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({
    required this.index,
    required this.total,
    required this.step,
    required this.onImageTap,
  });

  final int index;
  final int total;
  final AgoraGuideStep step;
  final ValueChanged<String>? onImageTap;

  static const _ink = Color(0xFF3C2B20);
  static const _mutedInk = Color(0xFF7B6553);
  static const _accent = Color(0xFF8B5A2B);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('agoraBookPage_$index'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBF1), Color(0xFFF2E3C8)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _PaperGrainPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 17, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _ink,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFD8B26B),
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Color(0xFFF8E8C8),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '步骤 ${index + 1} / $total',
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.auto_stories_outlined,
                      size: 16,
                      color: Color(0x998B5A2B),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  step.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 9),
                Expanded(
                  child: GestureDetector(
                    key: ValueKey('agoraBookImage_$index'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onImageTap == null
                        ? null
                        : () => onImageTap!(step.image),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: const Color(0x225C3B1E),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox.expand(
                          child: Image.asset(
                            step.image,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                '请将截图放到:\n${step.image}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _mutedInk,
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
                const SizedBox(height: 9),
                Text(
                  step.description,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      '点击截图可放大',
                      style: TextStyle(
                        color: _mutedInk,
                        fontSize: 10,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(index + 1).toString().padLeft(2, '0')} / '
                      '${total.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: _mutedInk,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 18,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF5C3B1E).withValues(alpha: 0.16),
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

class _PaperGrainPainter extends CustomPainter {
  const _PaperGrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x085C3B1E)
      ..strokeWidth = 0.6;
    for (var y = 12.0; y < size.height; y += 9) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BookControls extends StatelessWidget {
  const _BookControls({
    required this.page,
    required this.total,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  final int page;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('agoraBookPrev'),
          tooltip: '上一页',
          onPressed: page > 0 ? onPrevious : null,
          iconSize: 18,
          color: Colors.white70,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                GestureDetector(
                  key: ValueKey('agoraBookDot_$i'),
                  onTap: () => onSelect(i),
                  child: Container(
                    width: i == page ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color:
                          i == page ? const Color(0xFFD8B26B) : Colors.white38,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  '左右滑动翻页',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('agoraBookNext'),
          tooltip: '下一页',
          onPressed: page < total - 1 ? onNext : null,
          iconSize: 18,
          color: Colors.white70,
          disabledColor: Colors.white24,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
