import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/utils/emby_image_url.dart';

void main() {
  group('槽位策略表（698 N5-A/N7-D，借 SenPlayer 分档）', () {
    test('三档定值：hero 宁大勿糊 / logo 不抠质量 / card 小而清晰', () {
      final hero = embyImagePolicies[EmbyImageSlot.hero]!;
      expect(hero.minWidth, 600);
      expect(hero.maxWidth, 3000, reason: 'N7-D：上限 3000 对齐 media-detail:large 档');
      expect(hero.quality, 90);
      expect(hero.maxDpr, 3, reason: 'N7-D：hero 用满物理像素（dpr 封 3）');

      final logo = embyImagePolicies[EmbyImageSlot.logo]!;
      expect(logo.minWidth, 300);
      expect(logo.maxWidth, 800);
      expect(logo.quality, 100, reason: 'Logo 透明 PNG 不抠质量（q100）');

      final card = embyImagePolicies[EmbyImageSlot.card]!;
      expect(card.maxWidth, 540, reason: '对齐 SenPlayer media-card:poster:w540');
      expect(card.quality, 85);
    });

    test('embyImageSlotWidth：按槽位钳位 + 按档 dpr 封顶', () {
      // hero：390×3=1170（dpr 封 3，用满物理像素）；大窗钳 3000。
      expect(embyImageSlotWidth(EmbyImageSlot.hero, 390, 3), 1170);
      expect(embyImageSlotWidth(EmbyImageSlot.hero, 2000, 2), 3000);
      // card：小卡 120×2=240 钳下限 300；大卡钳 540。
      expect(embyImageSlotWidth(EmbyImageSlot.card, 120, 2), 300);
      expect(embyImageSlotWidth(EmbyImageSlot.card, 400, 2), 540);
      // logo：180×2=360。
      expect(embyImageSlotWidth(EmbyImageSlot.logo, 180, 2), 360);
    });
  });

  group('embyImageTargetWidth（设备感知目标宽，698 N4）', () {
    test('逻辑宽 × min(dpr, 封顶)：通用档封 2（省流量）', () {
      expect(embyImageTargetWidth(390, 3), 780); // 390×2
      expect(embyImageTargetWidth(390, 2), 780);
      expect(embyImageTargetWidth(640, 1.25), 800); // 桌面
    });

    test('默认钳位 600~1600（通用档）', () {
      expect(embyImageTargetWidth(200, 1), 600); // 钳下限
      expect(embyImageTargetWidth(2000, 2), 1600); // 钳上限
    });

    test('小件自定义区间（Logo 档 300~800）', () {
      expect(embyImageTargetWidth(180, 2, min: 300, max: 800), 360);
      expect(embyImageTargetWidth(50, 2, min: 300, max: 800), 300);
    });
  });

  group('embyImageUrlFor（URL 尺寸重写，698 N4/N4-5）', () {
    test('maxHeight=400 小图档 → maxWidth + quality=85', () {
      final out = embyImageUrlFor(
        'https://e.test/Items/1/Images/Primary?maxHeight=400&tag=abc',
        780,
      );
      expect(out, contains('maxWidth=780'));
      expect(out, contains('quality=85'));
      expect(out, isNot(contains('maxHeight=400')));
      expect(out, contains('tag=abc'), reason: 'tag 不得被改写');
    });

    test('无尺寸原图（Logo）→ 追加 maxWidth + quality=90', () {
      final out = embyImageUrlFor(
        'https://e.test/Items/1/Images/Logo?tag=xyz',
        360,
        quality: 90,
      );
      expect(out, contains('maxWidth=360'));
      expect(out, contains('quality=90'));
      expect(out, contains('tag=xyz'));
    });

    test('已带尺寸（虚化小图/宽幅档）→ 原样透传', () {
      const ambient =
          'https://e.test/Items/1/Images/Primary?maxWidth=320&quality=70&tag=abc';
      expect(embyImageUrlFor(ambient, 780), ambient);
      const wide =
          'https://e.test/Items/1/Images/Backdrop?maxWidth=1600&quality=90&tag=abc';
      expect(embyImageUrlFor(wide, 780), wide);
    });

    test('非 Emby 图片 URL → 透传（外部图床不受影响）', () {
      const external = 'https://image.tmdb.org/t/p/w500/abc.jpg';
      expect(embyImageUrlFor(external, 780), external);
    });

    test('quality 不重复追加', () {
      final out = embyImageUrlFor(
        'https://e.test/Items/1/Images/Primary?maxHeight=400&quality=70&tag=abc',
        780,
      );
      expect('quality=70'.allMatches(out!).length, 1);
    });

    test('null/空串 → null；无 scheme 原样返回', () {
      expect(embyImageUrlFor(null, 780), isNull);
      expect(embyImageUrlFor('', 780), isNull);
      expect(embyImageUrlFor('/Items/1/Images/Primary?maxHeight=400', 780),
          '/Items/1/Images/Primary?maxHeight=400');
    });
  });

  group('embyImageUrlForSlot（槽位取图入口，698 N5-A）', () {
    test('quality 跟槽位策略（hero q90 / logo q100 / card q85）', () {
      String urlFor(EmbyImageSlot slot) => embyImageUrlForSlot(
            'https://e.test/Items/1/Images/Primary?maxHeight=400&tag=abc',
            slot,
            390,
            2,
          )!;
      expect(urlFor(EmbyImageSlot.hero), contains('quality=90'));
      expect(urlFor(EmbyImageSlot.logo), contains('quality=100'));
      expect(urlFor(EmbyImageSlot.card), contains('quality=85'));
    });

    test('目标宽跟槽位钳位（同显示宽不同档）', () {
      // 400×2=800：hero 800 / card 钳 540 / logo 800。
      String? widthFor(EmbyImageSlot slot) {
        final out = embyImageUrlForSlot(
          'https://e.test/Items/1/Images/Primary?maxHeight=400&tag=abc',
          slot,
          400,
          2,
        )!;
        return RegExp(r'maxWidth=(\d+)').firstMatch(out)?.group(1);
      }

      expect(widthFor(EmbyImageSlot.hero), '800');
      expect(widthFor(EmbyImageSlot.card), '540');
      expect(widthFor(EmbyImageSlot.logo), '800');
    });
  });
}
