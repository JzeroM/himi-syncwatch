import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';

/// 698 N7-A/B 构图（SenPlayer 同款满幅）：竖版海报满幅 cover 居中裁切 +
/// 窄带渐隐（0.88 起）+ 信息块图上叠加——撤 contain/虚化铺底（N5-B 回归）。
void main() {
  const posterUrl =
      'https://e.test/Items/1/Images/Primary?maxHeight=400&tag=p';

  Widget wrap({
    String? imageUrl,
    void Function(String url, BoxFit fit, int? cacheWidth)? onImage,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: HomeHeroCarousel(
          items: [HomeHeroItem(title: '影片', imageUrl: imageUrl)],
          controller: PageController(),
          height: 500,
          onPageChanged: (_) {},
          imageBuilder: (url,
              {BoxFit fit = BoxFit.cover,
              int? cacheWidth,
              bool transparent = false,
              Widget? errorWidget}) {
            onImage?.call(url, fit, cacheWidth);
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }

  testWidgets('满幅 cover 一层图（无 contain/虚化铺底层）', (tester) async {
    final calls = <String, BoxFit>{};
    await tester.pumpWidget(wrap(
      imageUrl: posterUrl,
      onImage: (url, fit, _) => calls[url] = fit,
    ));
    await tester.pump();

    // 只有一层图（铺底层已撤）。
    expect(calls.length, 1, reason: 'N7-A 构图回归：满幅大图一层');
    expect(calls.values.single, BoxFit.cover, reason: 'cover 居中裁切满幅');
    // 不再有 contain 帧 / 虚化模糊层。
    expect(calls.values, isNot(contains(BoxFit.contain)));
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(AspectRatio), findsNothing);
  });

  testWidgets('hero 槽取图（q90 + 宽度钳 600~3000 + 同宽解码）', (tester) async {
    String? url;
    BoxFit? fit;
    int? cacheWidth;
    await tester.pumpWidget(wrap(
      imageUrl: posterUrl,
      onImage: (u, f, c) {
        url = u;
        fit = f;
        cacheWidth = c;
      },
    ));
    await tester.pump();

    expect(url, contains('quality=90'), reason: 'hero 槽 q90');
    expect(url, contains('tag=p'), reason: 'tag 不改写');
    final w =
        int.parse(RegExp(r'maxWidth=(\d+)').firstMatch(url!)!.group(1)!);
    expect(w, inInclusiveRange(600, 3000), reason: 'hero 槽钳 600~3000（N7-D）');
    expect(cacheWidth, w, reason: '同宽解码');
    expect(fit, BoxFit.cover);
  });

  testWidgets('信息块图上叠加（Logo/片名在图上，N7-A）', (tester) async {
    await tester.pumpWidget(wrap(imageUrl: posterUrl));
    await tester.pump();
    expect(find.text('影片'), findsOneWidget, reason: '片名叠加在图上');
  });

  testWidgets('无图条目：不渲染图层，信息块照常', (tester) async {
    await tester.pumpWidget(wrap(imageUrl: null));
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('影片'), findsOneWidget);
  });
}
