import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/utils/emby_image_url.dart';

void main() {
  group('embyImageTargetWidth（设备感知目标宽，698 N4）', () {
    test('逻辑宽 × min(dpr,2)：dpr 3 封顶 2（省流量）', () {
      expect(embyImageTargetWidth(390, 3), 780); // 390×2
      expect(embyImageTargetWidth(390, 2), 780);
      expect(embyImageTargetWidth(640, 1.25), 800); // 桌面
    });

    test('钳位 600~1280（hero 默认档）', () {
      expect(embyImageTargetWidth(200, 1), 600); // 钳下限
      expect(embyImageTargetWidth(2000, 2), 1280); // 钳上限
    });

    test('小件自定义区间（Logo 档 300~600）', () {
      expect(embyImageTargetWidth(180, 2, min: 300, max: 600), 360);
      expect(embyImageTargetWidth(50, 2, min: 300, max: 600), 300);
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
}
