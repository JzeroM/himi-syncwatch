import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';

void main() {
  // 0.55 二进制不可精确表示，屏高 × 0.55 存在浮点舍入 → 数值断言用 closeTo。
  group('heroHeightFor（698 轮播/详情页海报高度单源）', () {
    test('常规屏高：0.55 × 屏高', () {
      // 600 → 330；900 → 495。
      expect(HomeHeroCarousel.heroHeightFor(600), closeTo(330, 0.001));
      expect(HomeHeroCarousel.heroHeightFor(900), closeTo(495, 0.001));
    });

    test('小窗钳到下限 300（400×0.55=220 → 300）', () {
      expect(HomeHeroCarousel.heroHeightFor(400), 300);
      expect(HomeHeroCarousel.heroHeightFor(545), 300);
    });

    test('超大窗钳到上限 640（1200×0.55=660 → 640）', () {
      expect(HomeHeroCarousel.heroHeightFor(1200), 640);
      expect(HomeHeroCarousel.heroHeightFor(2000), 640);
    });

    test('钳位边界：恰好 300 / 640 附近时钳制生效', () {
      // 300/0.55 ≈ 545.45；640/0.55 ≈ 1163.64。
      expect(HomeHeroCarousel.heroHeightFor(300 / 0.55), closeTo(300, 0.001));
      expect(HomeHeroCarousel.heroHeightFor(640 / 0.55), closeTo(640, 0.001));
    });

    test('比例常量语义（改比例需同步更新此断言）', () {
      expect(HomeHeroCarousel.heroHeightRatio, 0.55);
      expect(HomeHeroCarousel.heroHeightMin, 300);
      expect(HomeHeroCarousel.heroHeightMax, 640);
    });
  });
}
