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

  group('接缝无缝（v1.2.15 去首页分隔线）', () {
    test('清晰图底部渐隐：终点透明（溶解进同源虚化层）', () {
      const g = HomeHeroCarousel.imageFadeGradient;
      expect(g.colors.first, Colors.white, reason: '顶部保持清晰');
      expect(g.colors.last, Colors.transparent, reason: '底边须完全渐隐');
      expect(g.stops, isNotNull);
      expect(g.stops!.last, 1.0);
      expect(g.stops![0], 0.0);
      expect(g.stops, orderedEquals(<double>[0.0, 0.62, 1.0]));
    });

    test('压暗罩末格 0x66：与虚化背景接缝 alpha（0.40）相等', () {
      const g = HomeHeroCarousel.scrimGradient;
      expect(g.colors.last, const Color(0x66000000));
      // 0x66/255 ≈ 0.40 = 虚化蒙罩在 hero 底边（屏高 42%，
      // 0.30→0.42@50% 的线性插值）处的暗度
      expect(g.colors.last.a, closeTo(0.40, 0.01));
      expect(g.colors[2], const Color(0x99000000),
          reason: '文字区维持 60% 可读性压暗');
    });

    test('先增后收敛：峰值后无反向回升（不产生暗带）', () {
      const g = HomeHeroCarousel.scrimGradient;
      final alphas = g.colors.map((c) => c.a).toList();
      var peak = 0;
      for (var i = 1; i < alphas.length; i++) {
        if (alphas[i] > alphas[peak]) peak = i;
      }
      for (var i = 1; i <= peak; i++) {
        expect(alphas[i], greaterThanOrEqualTo(alphas[i - 1] - 1e-9),
            reason: '峰值前只能逐渐变深');
      }
      for (var i = peak + 1; i < alphas.length; i++) {
        expect(alphas[i], lessThanOrEqualTo(alphas[i - 1] + 1e-9),
            reason: '峰值后只能逐渐收敛（变亮），不能回弹');
      }
    });

    testWidgets('清晰图包有 ShaderMask（dstIn 底部渐隐）', (tester) async {
      final controller = PageController();
      await _pump(tester, controller, items: [_item('1'), _item('2')]);
      final masks = tester
          .widgetList<ShaderMask>(find.byType(ShaderMask))
          .where((m) => m.blendMode == BlendMode.dstIn);
      expect(masks, isNotEmpty, reason: '清晰图须底部渐隐到透明');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      controller.dispose();
    });
  });
}
