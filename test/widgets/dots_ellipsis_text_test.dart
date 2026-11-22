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
}
