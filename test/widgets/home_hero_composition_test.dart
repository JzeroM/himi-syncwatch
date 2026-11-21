import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';

/// 698 N5-B 构图 A：海报完整居中（2:3 contain，零裁切）+ 同图虚化铺底
/// （320 小图 + 高斯模糊）——修「海报显示不全 / 放大糊」。
void main() {
  const posterUrl =
      'https://e.test/Items/1/Images/Primary?maxHeight=400&tag=p';

  Widget wrap({
    String? imageUrl,
    void Function(String url, BoxFit fit)? onImage,
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
            onImage?.call(url, fit);
            return const SizedBox.expand();
          },
        ),
      ),
    );
  }

  testWidgets('海报完整居中（AspectRatio 2:3 + contain）+ 虚化铺底在', (tester) async {
    final calls = <String, BoxFit>{};
    await tester.pumpWidget(wrap(
      imageUrl: posterUrl,
      onImage: (url, fit) => calls[url] = fit,
    ));
    await tester.pump();

    // 海报层：AspectRatio 2:3 + contain——完整可见不裁切。
    final ratios = tester
        .widgetList<AspectRatio>(find.byType(AspectRatio))
        .map((r) => r.aspectRatio)
        .toList();
    expect(ratios, contains(2 / 3), reason: '海报按 2:3 帧完整居中');
    expect(calls.values, contains(BoxFit.contain), reason: 'contain 零裁切');

    // 虚化铺底：同图 320 小图 + cover。
    final blurUrl =
        calls.keys.firstWhere((u) => u.contains('maxWidth=320'), orElse: () => '');
    expect(blurUrl, isNotEmpty, reason: '同图虚化铺底（320 小图）');
    expect(calls[blurUrl], BoxFit.cover);
    // 铺底经高斯模糊（ImageFiltered）。
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('海报大图走 hero 槽位（宁大勿糊：q90 + 宽度 600~1600）', (tester) async {
    final calls = <String, BoxFit>{};
    await tester.pumpWidget(wrap(
      imageUrl: posterUrl,
      onImage: (url, fit) => calls[url] = fit,
    ));
    await tester.pump();

    final poster = calls.keys.firstWhere(
      (u) => u.contains('quality=90'),
      orElse: () => '',
    );
    expect(poster, isNotEmpty, reason: 'hero 槽位 q90');
    expect(poster, contains('tag=p'), reason: 'tag 不改写');
    final w = int.parse(RegExp(r'maxWidth=(\d+)').firstMatch(poster)!.group(1)!);
    expect(w, inInclusiveRange(600, 1600), reason: 'hero 槽位钳 600~1600');
  });

  testWidgets('无图条目：不渲染海报/虚化层，信息块照常', (tester) async {
    await tester.pumpWidget(wrap(imageUrl: null));
    await tester.pump();
    expect(find.byType(AspectRatio), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('影片'), findsOneWidget);
  });
}
