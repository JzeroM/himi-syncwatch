import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_page.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';
import 'package:himi_syncwatch/widgets/agora/agora_guide_book.dart';

Future<void> _pumpBook(
  WidgetTester tester, {
  ValueChanged<String>? onImageTap,
  Color? themeColor,
  AgoraBookExtraPageBuilder? extraPageBuilder,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 390,
            child: AgoraGuideBook(
              onImageTap: onImageTap,
              tone: themeColor,
              extraPageBuilder: extraPageBuilder,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openBook(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('agoraBookCover')));
  await tester.pumpAndSettle();
}

LinearGradient _coverGradient(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const ValueKey('agoraBookCoverSurface')),
  );
  return (container.decoration! as BoxDecoration).gradient! as LinearGradient;
}

void main() {
  testWidgets('首屏显示合上的做旧封面', (tester) async {
    await _pumpBook(tester);

    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agoraBookCoverSurface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agoraBookClosedPageBlock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agoraBookClosedPageClip')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agoraBookBookmark_0')), findsNothing);
    expect(find.text('声网接入指南'), findsOneWidget);
    expect(find.text('四步完成声网配置'), findsOneWidget);
    expect(find.text('步骤 1 / 4'), findsNothing);
    expect(find.text('共 4 步 · 左右滑动阅读'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraQuillButton')), findsNothing);
  });

  testWidgets('点按封面可翻开，首页可返回封面', (tester) async {
    await _pumpBook(tester);

    await _openBook(tester);

    expect(find.text('步骤 1 / 4'), findsOneWidget);
    expect(find.text('注册登录并创建通用项目'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agoraBookOpenPageBlock')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agoraBookOpenPageClip')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('agoraBookBookmark_0')), findsOneWidget);
    final prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookPrev')),
    );
    expect(prev.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('agoraBookPrev')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);

    await _openBook(tester);
    expect(find.text('步骤 1 / 4'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('agoraBookViewport')),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);
  });

  testWidgets('左右滑动翻页，页码同步更新', (tester) async {
    await _pumpBook(tester);
    await _openBook(tester);

    await tester.drag(
      find.byKey(const ValueKey('agoraBookViewport')),
      const Offset(-280, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('步骤 2 / 4'), findsOneWidget);
    expect(find.text('开通体验版套餐包'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_1')), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('agoraBookViewport')),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('步骤 1 / 4'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_0')), findsOneWidget);
  });

  testWidgets('扩展配置页作为第五页并带书签', (tester) async {
    await _pumpBook(
      tester,
      extraPageBuilder: (context, palette, index, total) {
        return AgoraBookPaperPage(
          index: index,
          total: total,
          palette: palette,
          kicker: '配置 / $total',
          title: '填写并保存凭证',
          child: const Text('配置内容'),
        );
      },
    );

    await _openBook(tester);
    await tester.tap(find.byKey(const ValueKey('agoraBookDot_4')));
    await tester.pumpAndSettle();

    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.text('配置内容'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_4')), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookNext')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('封面点击鹅毛笔直接跳到第五页配置', (tester) async {
    await _pumpBook(
      tester,
      extraPageBuilder: (context, palette, index, total) {
        return AgoraBookPaperPage(
          index: index,
          total: total,
          palette: palette,
          kicker: '配置 / $total',
          title: '填写并保存凭证',
          child: const Text('配置内容'),
        );
      },
    );

    final quill = find.byKey(const ValueKey('agoraQuillButton'));
    expect(quill, findsOneWidget);
    expect(tester.widget<GestureDetector>(quill).onTap, isNotNull);

    await tester.tap(quill);
    await tester.pumpAndSettle();

    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.text('配置内容'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_4')), findsOneWidget);
    expect(tester.widget<GestureDetector>(quill).onTap, isNull);
  });

  testWidgets('翻到中间页后点鹅毛笔仍直达第五页', (tester) async {
    await _pumpBook(
      tester,
      extraPageBuilder: (context, palette, index, total) {
        return AgoraBookPaperPage(
          index: index,
          total: total,
          palette: palette,
          kicker: '配置 / $total',
          title: '填写并保存凭证',
          child: const Text('配置内容'),
        );
      },
    );
    await _openBook(tester);
    await tester.tap(find.byKey(const ValueKey('agoraBookNext')));
    await tester.pumpAndSettle();
    expect(find.text('步骤 2 / 5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agoraQuillButton')));
    await tester.pumpAndSettle();

    expect(find.text('配置 / 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_4')), findsOneWidget);
  });

  testWidgets('点击指示点跳转到对应步骤', (tester) async {
    await _pumpBook(tester);
    await _openBook(tester);

    await tester.tap(find.byKey(const ValueKey('agoraBookDot_3')));
    await tester.pumpAndSettle();

    expect(find.text('步骤 4 / 4'), findsOneWidget);
    expect(find.text('获取 APP ID 和证书'), findsOneWidget);
    expect(find.byKey(const ValueKey('agoraBookBookmark_3')), findsOneWidget);
  });

  testWidgets('末页下一页按钮禁用', (tester) async {
    await _pumpBook(tester);
    await _openBook(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('agoraBookNext')));
      await tester.pumpAndSettle();
    }

    expect(find.text('步骤 4 / 4'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('agoraBookNext')),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('点击截图回调图片路径', (tester) async {
    String? tapped;
    await _pumpBook(tester, onImageTap: (image) => tapped = image);
    await _openBook(tester);

    final ctx = tester.element(find.byType(MaterialApp));
    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/agora_step1.png'),
          ctx,
        ));
    await tester.pumpAndSettle();

    final image = find.byKey(const ValueKey('agoraBookImage_0'));
    await tester.ensureVisible(image);
    await tester.tap(image);
    await tester.pump();

    expect(tapped, 'assets/images/agora_step1.png');
  });

  testWidgets('封面书皮跟随背景色调（N48 fromTone）', (tester) async {
    // N48：书皮跟随背景色（暗基调 + 背景色相派生 + 金点缀）。
    const tone = Color(0xFFEC4899);
    await _pumpBook(tester, themeColor: tone);

    expect(_coverGradient(tester).colors,
        contains(AgoraBookPalette.fromTone(tone).leather));

    // 换背景色调封面跟随变化。
    const otherTone = Color(0xFF10B981);
    await _pumpBook(tester, themeColor: otherTone);

    expect(_coverGradient(tester).colors,
        contains(AgoraBookPalette.fromTone(otherTone).leather));
  });

  test('N48 书皮 fromTone：烫字/皮革对比 ≥0.35（可读性守卫）', () {
    for (final tone in const [
      Color(0xFFEC4899),
      Color(0xFF10B981),
      Color(0xFF3B82F6),
      null,
    ]) {
      final p = AgoraBookPalette.fromTone(tone);
      final foilL = HSLColor.fromColor(p.foil).lightness;
      final leatherL = HSLColor.fromColor(p.leather).lightness;
      // N49 文字回归原版固定金——对比锁原版水准 ≥0.30。
      expect(foilL - leatherL, greaterThanOrEqualTo(0.30),
          reason: '烫字比皮革亮 ≥0.30（原版金箔水准；tone=$tone）');
    }
  });

  test('N49 文字回归原版：固定金箔 + 墨字 + 近白装饰字', () {
    for (final tone in const [Color(0xFF10B981), Color(0xFFEC4899), null]) {
      final p = AgoraBookPalette.fromTone(tone);
      expect(p.foil, const Color(0xFFC2A064), reason: '烫字原版金（tone=$tone）');
      expect(p.foilBright, const Color(0xFFE0C58C));
      expect(p.foilDim, const Color(0xFF8D7447));
      expect(p.ink, const Color(0xFF3B2A1C), reason: '内页墨字');
      expect(p.mutedInk, const Color(0xFF6E5741), reason: '次文字原版棕墨');
      // 近白装饰字（封面/书页 paperLight 文字源）。
      expect(p.paperLight, const Color(0xFFF0DFBF), reason: '近白装饰字');
      final plL = HSLColor.fromColor(p.paperLight).lightness;
      expect(plL, greaterThan(0.80), reason: '白色字（近白）');
    }
  });

  test('N49 书皮柔和 + 书页泛黄纸', () {
    final p = AgoraBookPalette.fromTone(const Color(0xFF10B981));
    // 皮革柔和：L∈[0.20, 0.28]（不压死）。
    final leatherL = HSLColor.fromColor(p.leather).lightness;
    expect(leatherL, inInclusiveRange(0.20, 0.28), reason: '皮革柔和');
    // 书页泛黄纸（N46 前原版暖纸）。
    expect(p.paper, const Color(0xFFE4CFA9), reason: '泛黄纸张');
    expect(p.paperLight, const Color(0xFFF0DFBF));
    expect(p.ink, const Color(0xFF3B2A1C), reason: '暖纸深墨字');
  });

  testWidgets('做旧纸张与书页纹理可渲染', (tester) async {
    await _pumpBook(tester);
    await _openBook(tester);

    expect(find.byKey(const ValueKey('agoraBookPage_0')), findsOneWidget);
    expect(find.text('步骤 1 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('翻页矩阵方向锁定为外翻', (tester) async {
    final transform = agoraPageTurnTransform(0.5);

    expect(transform.entry(2, 0), lessThan(0));
    expect(transform.entry(0, 0), lessThan(1));
  });

  testWidgets('窄屏下合上/翻开均不溢出', (tester) async {
    await _pumpBook(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('agoraBookCover')), findsOneWidget);

    await _openBook(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('步骤 1 / 4'), findsOneWidget);
  });
}
