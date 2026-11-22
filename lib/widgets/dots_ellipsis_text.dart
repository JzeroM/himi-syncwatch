import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 三点省略号多行文本（698 N13）：截断时**末行行尾画三点「...」**（Flutter
/// 原生 [TextOverflow.ellipsis] 只能画「…」，自绘换三点）；**首行行尾永不
/// 出现省略号**（TextPainter 标准行为：省略号只画在最后一行）。
///
/// **末行右截断位（698 N16）**：[lastLineInset] > 0 时双 painter 分行排版——
/// 首行满宽居中；末行按「满宽 − lastLineInset」量算截断（省略号画在截断位
/// 之前），居中钳位到不进右侧避让区。
/// **首行左截断位（698 N24）**：[firstLineInset] > 0 时首行按「满宽 −
/// firstLineInset」量算、居中钳位到不进左侧避让区（如详情简介「全部」
/// 胶囊在第一行行首）。单行文本同时避让左右（胶囊同高并排时）。
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
    this.lastLineInset = 0,
    this.firstLineInset = 0,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  /// 末行右截断位（逻辑 px）：末行可用宽 = 满宽 − lastLineInset。
  /// 0 = 不避让（旧行为，单 painter 整段排版）。
  final double lastLineInset;

  /// 首行左截断位（逻辑 px，698 N24）：首行可用宽 = 满宽 − firstLineInset，
  /// 居中钳位到不进左侧避让区。
  final double firstLineInset;

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

  /// 首行断点切分（698 N16，@visibleForTesting）：返回 (首行文本, 余下文本)。
  ///
  /// 断点取满宽排版下第一行行尾；余下文本去前导空白（换行处的空格）。
  @visibleForTesting
  static (String, String) splitAfterFirstLine({
    required String text,
    required double maxWidth,
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    final painter = buildPainter(
      text: text,
      maxWidth: maxWidth,
      style: style,
      maxLines: 1,
      textAlign: TextAlign.left,
      textDirection: textDirection,
    );
    final pos = painter.getPositionForOffset(
      Offset(maxWidth, painter.height / 2),
    );
    final cut = pos.offset.clamp(0, text.length);
    final rest = text.substring(cut).replaceFirst(RegExp(r'^\s+'), '');
    return (text.substring(0, cut), rest);
  }

  /// 末行绘制 x（698 N16）：居中钳位——先按满宽居中，若进入右侧避让区
  /// （宽 − lastLineInset 以右）则左推到避让区外；超宽行从 0 起画。
  @visibleForTesting
  static double lastLineX({
    required double maxWidth,
    required double lineWidth,
    required double lastLineInset,
  }) {
    final maxX = (maxWidth - lastLineInset - lineWidth).clamp(0.0, double.infinity);
    return ((maxWidth - lineWidth) / 2).clamp(0.0, maxX);
  }

  /// 首行绘制 x（按 [textAlign] 在满宽内定位；698 N24 钳位不进左侧
  /// 避让区 firstLineInset）。
  @visibleForTesting
  static double firstLineX({
    required double maxWidth,
    required double lineWidth,
    required TextAlign textAlign,
    double firstLineInset = 0,
  }) {
    final x = switch (textAlign) {
      TextAlign.center || TextAlign.justify => (maxWidth - lineWidth) / 2,
      TextAlign.right || TextAlign.end => maxWidth - lineWidth,
      _ => 0.0,
    };
    final minX = firstLineInset.clamp(0.0, double.infinity);
    return x.clamp(
      minX,
      (maxWidth - lineWidth).clamp(minX, double.infinity),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedStyle =
        DefaultTextStyle.of(context).style.merge(style ?? const TextStyle());
    final direction = Directionality.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;

      // 旧行为（无避让）：单 painter 整段排版。
      if (lastLineInset <= 0 && firstLineInset <= 0) {
        final painter = buildPainter(
          text: text,
          maxWidth: w,
          style: resolvedStyle,
          maxLines: maxLines,
          textAlign: textAlign,
          textDirection: direction,
        );
        return _wrap(
          painter: painter,
          size: Size(w, painter.height),
        );
      }

      // 单行文本：同时避让左右（胶囊同高并排）。
      final (first, rest) = splitAfterFirstLine(
        text: text,
        maxWidth: w - firstLineInset,
        style: resolvedStyle,
        textDirection: direction,
      );
      if (rest.isEmpty || maxLines <= 1) {
        final painter = buildPainter(
          text: text,
          maxWidth: w - lastLineInset - firstLineInset,
          style: resolvedStyle,
          maxLines: 1,
          textAlign: TextAlign.left,
          textDirection: direction,
        );
        return _wrap(
          painter: painter,
          size: Size(w, painter.height),
          offsetX: firstLineX(
            maxWidth: w,
            lineWidth: painter.width,
            textAlign: TextAlign.center,
            firstLineInset: firstLineInset,
          ).clamp(
            firstLineInset.clamp(0.0, double.infinity),
            (w - lastLineInset - painter.width)
                .clamp(firstLineInset.clamp(0.0, double.infinity),
                    double.infinity),
          ),
        );
      }

      // 双 painter 分行：首行左避让（N24）；末行截断位避让 + 居中钳位。
      final painterA = buildPainter(
        text: first,
        maxWidth: w - firstLineInset,
        style: resolvedStyle,
        maxLines: 1,
        textAlign: TextAlign.left,
        textDirection: direction,
      );
      final painterB = buildPainter(
        text: rest,
        maxWidth: w - lastLineInset,
        style: resolvedStyle,
        maxLines: maxLines - 1,
        textAlign: TextAlign.left,
        textDirection: direction,
      );
      return _wrap(
        painter: painterA,
        painterB: painterB,
        size: Size(w, painterA.height + painterB.height),
        offsetX: firstLineX(
          maxWidth: w,
          lineWidth: painterA.width,
          textAlign: textAlign,
          firstLineInset: firstLineInset,
        ),
        offsetX2: lastLineX(
          maxWidth: w,
          lineWidth: painterB.width,
          lastLineInset: lastLineInset,
        ),
        offsetY2: painterA.height,
      );
    });
  }

  Widget _wrap({
    required TextPainter painter,
    TextPainter? painterB,
    required Size size,
    double offsetX = 0,
    double offsetX2 = 0,
    double offsetY2 = 0,
  }) {
    return Semantics(
      label: text,
      child: CustomPaint(
        size: size,
        painter: _DotsTextPainter(painter, painterB, offsetX, offsetX2, offsetY2),
      ),
    );
  }
}

class _DotsTextPainter extends CustomPainter {
  const _DotsTextPainter(
    this._painter,
    this._painterB,
    this._offsetX,
    this._offsetX2,
    this._offsetY2,
  );

  final TextPainter _painter;
  final TextPainter? _painterB;
  final double _offsetX;
  final double _offsetX2;
  final double _offsetY2;

  @override
  void paint(Canvas canvas, Size size) {
    _painter.paint(canvas, Offset(_offsetX, 0));
    _painterB?.paint(canvas, Offset(_offsetX2, _offsetY2));
  }

  @override
  bool shouldRepaint(_DotsTextPainter oldDelegate) =>
      oldDelegate._painter != _painter ||
      oldDelegate._painterB != _painterB ||
      oldDelegate._offsetX != _offsetX ||
      oldDelegate._offsetX2 != _offsetX2 ||
      oldDelegate._offsetY2 != _offsetY2;
}
