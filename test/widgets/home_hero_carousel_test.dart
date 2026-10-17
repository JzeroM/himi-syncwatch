import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';

MediaItem _item(String id) => MediaItem(id: id, name: '影片$id', type: 'Movie');

Future<void> _pump(
  WidgetTester tester,
  PageController controller, {
  required List<MediaItem> items,
  void Function(MediaItem)? onTap,
  ValueChanged<int>? onPageChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: HomeHeroCarousel(
            items: items,
            controller: controller,
            height: 300,
            onTap: onTap,
            onPageChanged: onPageChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('渲染多页 + 页码点，满 5 秒自动切页', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, items: [_item('1'), _item('2'), _item('3')]);

    expect(controller.page, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.page, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('末页满 5 秒回卷到首页', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await _pump(tester, controller, items: [_item('1'), _item('2')]);

    controller.jumpToPage(1);
    await tester.pump();
    expect(controller.page, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.page, 0, reason: '末页应回卷首页');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点击当前页回调对应条目', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    MediaItem? tapped;
    await _pump(
      tester,
      controller,
      items: [_item('1'), _item('2')],
      onTap: (item) => tapped = item,
    );

    await tester.tap(find.byType(PageView));
    await tester.pump();
    expect(tapped?.id, '1');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('销毁后无悬挂定时器', (tester) async {
    final controller = PageController();
    await _pump(tester, controller, items: [_item('1'), _item('2')]);
    // 卸载组件 → dispose 取消 timer；若未取消，测试结束会报 pending timer
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    controller.dispose();
  });
}
