import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 三点省略号多行文本（698 N13）：截断时**末行行尾画三点「...」**（Flutter
/// 原生 [TextOverflow.ellipsis] 只能画「…」，自绘换三点）；**首行行尾永不
/// 出现省略号**（TextPainter 标准行为：省略号只画在最后一行）。
///
/// 居中/行距/字重随 [style] 与 [textAlign]；语义标签取原文本（截断可见性
/// 由 maxLines 控制，读屏仍可全文朗读）。
class DotsEllipsisText extends StatelessWidget {
  const DotsEllipsisText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.center,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  /// 三点省略号（守卫断言用；绘制即此字面量）。
  @visibleForTesting
  static const String dots = '...';

  /// 构造排版 painter（@visibleForTesting：省略号语义单测直查）。
  @visibleForTesting
  static TextPainter buildPainter({
    required String text,
    required double maxWidth,
    required TextStyle style,
    required int maxLines,
    required TextAlign textAlign,
    required TextDirection textDirection,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      ellipsis: dots,
      textAlign: textAlign,
      textDirection: textDirection,
    )..layout(maxWidth: maxWidth);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle =
        DefaultTextStyle.of(context).style.merge(style ?? const TextStyle());
    final direction = Directionality.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = buildPainter(
        text: text,
        maxWidth: constraints.maxWidth,
        style: resolvedStyle,
        maxLines: maxLines,
        textAlign: textAlign,
        textDirection: direction,
      );
      return Semantics(
        label: text,
        child: CustomPaint(
          size: Size(constraints.maxWidth, painter.height),
          painter: _DotsTextPainter(painter),
        ),
      );
    });
  }
}

class _DotsTextPainter extends CustomPainter {
  const _DotsTextPainter(this._painter);

  final TextPainter _painter;

  @override
  void paint(Canvas canvas, Size size) => _painter.paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_DotsTextPainter oldDelegate) =>
      oldDelegate._painter != _painter;
}
