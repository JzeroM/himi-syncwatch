import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/dots_ellipsis_text.dart';

void main() {
  group('DotsEllipsisText（698 N13 三点省略号多行文本）', () {
    test('三点字面量（非 …）+ painter 末行截断语义', () {
      expect(DotsEllipsisText.dots, '...',
          reason: '第二行行尾三点「...」（用户拍板，非 Unicode 省略号）');

      // 超长文本 + 窄宽 → 超出 maxLines（省略号只画末行；首行行尾无省略）。
      final painter = DotsEllipsisText.buildPainter(
        text: '很长的简介' * 50,
        maxWidth: 200,
        style: const TextStyle(fontSize: 13, height: 1.5),
        maxLines: 2,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      expect(painter.didExceedMaxLines, isTrue, reason: '超出走省略');
      expect(painter.height, greaterThan(0));

      // 短文本不截断（无省略号）。
      final short = DotsEllipsisText.buildPainter(
        text: '短简介',
        maxWidth: 400,
        style: const TextStyle(fontSize: 13),
        maxLines: 2,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      expect(short.didExceedMaxLines, isFalse);
    });

    testWidgets('渲染：居中 + maxLines 生效 + 语义标签为全文', (tester) async {
      const text = '八仙在成仙和成功之间选择了成团，在搞钱和搞事业之间选择了搞事情';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: DotsEllipsisText(
              text,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ),
      ));
      final w = tester.widget<DotsEllipsisText>(find.byType(DotsEllipsisText));
      expect(w.maxLines, 2);
      expect(w.textAlign, TextAlign.center);
      expect(find.bySemanticsLabel(text), findsOneWidget,
          reason: '读屏仍可全文朗读');
    });
  });

  group('末行截断位 lastLineInset（698 N16 简介加长）', () {
    const style = TextStyle(fontSize: 13, height: 1.5);

    test('首行断点切分：长文本一分为二，短文本余下为空', () {
      const text = '八仙在成仙和成功之间选择了成团，在搞钱和搞事业之间选择了搞事情，八个身份各异的凡人';
      final (first, rest) = DotsEllipsisText.splitAfterFirstLine(
        text: text,
        maxWidth: 300,
        style: style,
        textDirection: TextDirection.ltr,
      );
      expect(first, isNotEmpty);
      expect(rest, isNotEmpty);
      expect('$first$rest'.replaceAll(' ', ''), text.replaceAll(' ', ''),
          reason: '切分无丢失（仅去换行处空白）');

      const short = '短简介';
      final (f2, r2) = DotsEllipsisText.splitAfterFirstLine(
        text: short,
        maxWidth: 300,
        style: style,
        textDirection: TextDirection.ltr,
      );
      expect(f2, short);
      expect(r2, isEmpty, reason: '单行文本无余下 → 按末行处理');
    });

    test('末行绘制 x：居中钳位——不进右侧避让区，超宽行从 0 起画', () {
      // 超宽末行（占满 W−inset）→ 起画 0（右端恰在截断位）。
      expect(
        DotsEllipsisText.lastLineX(maxWidth: 300, lineWidth: 208, lastLineInset: 92),
        0.0,
      );
      // 短行居中无碰撞 → 正居中。
      expect(
        DotsEllipsisText.lastLineX(maxWidth: 300, lineWidth: 60, lastLineInset: 92),
        120.0,
        reason: '短行居中不歪',
      );
      // 居中会进避让区 → 左推到避让区外（右端 ≤ 300-92）。
      final x = DotsEllipsisText.lastLineX(
          maxWidth: 300, lineWidth: 150, lastLineInset: 92);
      expect(x, lessThanOrEqualTo(300 - 92 - 150),
          reason: '钳位到不进胶囊区');
      expect(x, greaterThanOrEqualTo(0));
    });

    testWidgets('渲染：双行时首行满宽、末行截断在 inset 前；语义全文', (tester) async {
      const text =
          '八仙在成仙和成功之间选择了成团，在搞钱和搞事业之间选择了搞事情，八个身份各异的凡人最终携手';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: DotsEllipsisText(
              text,
              maxLines: 2,
              textAlign: TextAlign.center,
              lastLineInset: 92,
              style: style,
            ),
          ),
        ),
      ));
      expect(find.bySemanticsLabel(text), findsOneWidget,
          reason: '读屏仍可全文朗读');
      final box = tester.renderObject<RenderBox>(find.byType(CustomPaint).last);
      expect(box.size.width, 300, reason: 'N16：文本框满宽（首行满宽前提）');
      expect(box.size.height, greaterThan(15),
          reason: '两行排版（首行 + 截断末行）');
    });

    testWidgets('单行文本按末行处理（同高并排胶囊避让）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: DotsEllipsisText(
              '短简介',
              maxLines: 2,
              textAlign: TextAlign.center,
              lastLineInset: 92,
              style: style,
            ),
          ),
        ),
      ));
      final box = tester.renderObject<RenderBox>(find.byType(CustomPaint).last);
      expect(box.size.height, lessThan(25), reason: '单行高度');
    });
  });

  group('首行左截断位 firstLineInset（698 N24 胶囊行首）', () {
    const style = TextStyle(fontSize: 13, height: 1.5);

    test('首行绘制 x：居中钳位——不进左侧避让区', () {
      // 超宽首行（占满 W−inset）→ 起画 inset（左端恰在胶囊后）。
      expect(
        DotsEllipsisText.firstLineX(
            maxWidth: 300, lineWidth: 208, textAlign: TextAlign.center,
            firstLineInset: 92),
        92.0,
      );
      // 短行居中无碰撞 → 正居中。
      expect(
        DotsEllipsisText.firstLineX(
            maxWidth: 300, lineWidth: 60, textAlign: TextAlign.center,
            firstLineInset: 92),
        120.0,
        reason: '短行居中不歪',
      );
      // 居中会进左侧避让区 → 右推到避让区外。
      final x = DotsEllipsisText.firstLineX(
          maxWidth: 300, lineWidth: 150, textAlign: TextAlign.center,
          firstLineInset: 92);
      expect(x, greaterThanOrEqualTo(92), reason: '钳位到不进胶囊区');
    });

    testWidgets('渲染：首行左避让、末行满宽；语义全文', (tester) async {
      const text =
          '八仙在成仙和成功之间选择了成团，在搞钱和搞事业之间选择了搞事情，八个身份各异的凡人最终携手';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: DotsEllipsisText(
              text,
              maxLines: 2,
              textAlign: TextAlign.center,
              firstLineInset: 92,
              style: style,
            ),
          ),
        ),
      ));
      expect(find.bySemanticsLabel(text), findsOneWidget);
      final box = tester.renderObject<RenderBox>(find.byType(CustomPaint).last);
      expect(box.size.width, 300, reason: '文本框满宽（末行满宽）');
      expect(box.size.height, greaterThan(15), reason: '两行排版');
    });
  });
}
