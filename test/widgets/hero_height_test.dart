import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';

void main() {
  group('高度双档（698 N7-C，显示区比例贴图：轮播贴 2:3 / 详情贴横图）', () {
    test('轮播高度 = 宽×1.35（贴竖版海报 2:3）', () {
      // 390×844 手机：526.5（决策值，护栏不触碰）。
      expect(HomeHeroCarousel.carouselHeightFor(390, 844),
          closeTo(526.5, 0.001));
      // 钳位区间。
      expect(HomeHeroCarousel.carouselHeightFor(200, 844), 300);
      expect(HomeHeroCarousel.carouselHeightFor(1000, 2000), 640);
    });

    test('详情高度 = 宽×0.85（≈1.17:1 贴横版背景图，SenPlayer 同档）', () {
      expect(
          HomeHeroCarousel.detailHeightFor(390, 844), closeTo(331.5, 0.001));
      expect(HomeHeroCarousel.detailHeightFor(200, 844), 300);
      expect(HomeHeroCarousel.detailHeightFor(1000, 2000), 640);
    });

    test('视口护栏：宽扁窗高度不超屏高×0.65（撑破视口=懒列表不建）', () {
      // 800×600 桌面窗：轮播 800×1.35=1080 → 护栏 390。
      expect(HomeHeroCarousel.carouselHeightFor(800, 600), 390);
      // 详情 800×0.85=680 → 护栏 390。
      expect(HomeHeroCarousel.detailHeightFor(800, 600), 390);
    });

    test('比率常量与钳位区间', () {
      expect(HomeHeroCarousel.carouselHeightRatio, 1.35);
      expect(HomeHeroCarousel.detailHeightRatio, 0.85);
      expect(HomeHeroCarousel.viewportCapRatio, 0.65);
      expect(HomeHeroCarousel.heroHeightMin, 300);
      expect(HomeHeroCarousel.heroHeightMax, 640);
    });
  });

  group('698 N78：桌面 16:9 横图分支（Windows/macOS/Linux）', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('桌面轮播/详情高度 = 宽×0.5625（16:9）+ 更矮护栏', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      // 1280×800 窗口：1280×0.5625=720 → 护栏 0.5×800=400 → 400。
      expect(HomeHeroCarousel.carouselHeightFor(1280, 800), 400);
      expect(HomeHeroCarousel.detailHeightFor(1280, 800), 400);
      // 1920×1080：1920×0.5625=1080 → 护栏 0.5×1080=540 → 夹紧上限 480。
      expect(HomeHeroCarousel.carouselHeightFor(1920, 1080), 480);
      // 桌面钳位下限 240。
      expect(HomeHeroCarousel.carouselHeightFor(300, 800), 240);
    });

    test('桌面 hero 图片源用 backdrop（16:9 横图），手机用 poster', () {
      const item = HomeHeroItem(
        title: 't',
        imageUrl: 'poster.jpg',
        backdropUrl: 'backdrop.jpg',
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(HomeHeroCarousel.heroImageUrl(item), 'backdrop.jpg');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(HomeHeroCarousel.heroImageUrl(item), 'poster.jpg');
      // 无 backdrop 时桌面回退 poster。
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      const noBackdrop = HomeHeroItem(title: 't', imageUrl: 'poster.jpg');
      expect(HomeHeroCarousel.heroImageUrl(noBackdrop), 'poster.jpg');
    });

    test('手机仍走 1.35 / 0.85，不受桌面分支影响', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(HomeHeroCarousel.carouselHeightFor(390, 844), closeTo(526.5, 0.001));
      expect(HomeHeroCarousel.detailHeightFor(390, 844), closeTo(331.5, 0.001));
    });
  });
}
