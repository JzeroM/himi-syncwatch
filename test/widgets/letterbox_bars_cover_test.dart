import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/letterbox_bars_cover.dart';

void main() {
  group('LetterboxBarsCover.barsPath 几何', () {
    test('16:9 铺满 → 空 Path（无黑边）', () {
      final path = LetterboxBarsCover.barsPath(
        const Size(1920, 1080),
        16 / 9,
      );
      expect(path.getBounds().isEmpty, isTrue);
    });

    test('2.40:1 片源在 1920x1080 屏 → 上下黑边各约 140.5', () {
      final path = LetterboxBarsCover.barsPath(
        const Size(1920, 1080),
        3840 / 1598,
      );
      final b = path.getBounds();
      expect(b.left, 0);
      expect(b.right, 1920);
      final barH = (1080 - 1920 / (3840 / 1598)) / 2;
      expect(barH, closeTo(140.4, 0.2));
      // 上黑边内 / 视频矩形内 / 下黑边内
      expect(path.contains(const Offset(960, 70)), isTrue);
      expect(path.contains(const Offset(960, 540)), isFalse);
      expect(path.contains(const Offset(960, 1010)), isTrue);
    });

    test('4:3 片源在 16:9 屏 → 左右黑边', () {
      final path = LetterboxBarsCover.barsPath(
        const Size(1920, 1080),
        4 / 3,
      );
      expect(path.contains(const Offset(50, 540)), isTrue);
      expect(path.contains(const Offset(960, 540)), isFalse);
      expect(path.contains(const Offset(1870, 540)), isTrue);
    });

    test('参数非法 → 空 Path 且不抛', () {
      for (final aspect in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          LetterboxBarsCover.barsPath(const Size(1920, 1080), aspect)
              .getBounds()
              .isEmpty,
          isTrue,
          reason: 'aspect=$aspect',
        );
      }
      expect(
        LetterboxBarsCover.barsPath(Size.zero, 16 / 9).getBounds().isEmpty,
        isTrue,
      );
      expect(
        LetterboxBarsCover.barsPath(const Size(-1, 100), 16 / 9)
            .getBounds()
            .isEmpty,
        isTrue,
      );
    });
  });

  group('LetterboxBarsCover 挂载', () {
    /// 固定根视图为 1920x1080（默认 800x600 会让 SizedBox 被夹紧，
    /// 面积变化导致黑边几何与用例预期不符）。
    void useView1920x1080(WidgetTester tester) {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('2.40:1 → 渲染 CustomPaint 且在 IgnorePointer 内', (tester) async {
      useView1920x1080(tester);
      await tester.pumpWidget(
        const LetterboxBarsCover(aspect: 3840 / 1598),
      );
      expect(find.byType(CustomPaint), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(CustomPaint),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    testWidgets('16:9 铺满 → 收缩不渲染遮罩', (tester) async {
      useView1920x1080(tester);
      await tester.pumpWidget(
        const LetterboxBarsCover(aspect: 16 / 9),
      );
      expect(find.byType(CustomPaint), findsNothing);
    });
  });
}
