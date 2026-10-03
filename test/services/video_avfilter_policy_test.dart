import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/video_avfilter_policy.dart';

/// 非标尺寸规范化滤镜（v1.1.70 实验）：
/// 真机对照 3840x1598 黑屏 vs 3840x2160 正常，若根因是 16 对齐拒绝，
/// scale 补齐即出画；对齐尺寸零影响（返回 null 不写属性）。
void main() {
  group('VideoAvfilterPolicy.resolve', () {
    test('触发条件=非 8 对齐；对齐尺寸返回 null 不写属性', () {
      expect(VideoAvfilterPolicy.resolve(3840, 2160), isNull);
      expect(VideoAvfilterPolicy.resolve(1920, 1080), isNull);
      expect(VideoAvfilterPolicy.resolve(1280, 720), isNull);
      // 16×99=1584（8/16 双对齐）边界
      expect(VideoAvfilterPolicy.resolve(3840, 1584), isNull);
      // 8×199=1592（仅 8 对齐）：不触发——正常片源零干预
      expect(VideoAvfilterPolicy.resolve(3840, 1592), isNull);
    });

    test('真机黑屏样本 3840x1598 → scale 补到 3840x1600（16×100）', () {
      expect(
        VideoAvfilterPolicy.resolve(3840, 1598),
        'scale=3840:1600:flags=neighbor',
      );
    });

    test('触发后目标一律 ceil16（宏块粒度）：1918x1078 → 1920x1088', () {
      expect(
        VideoAvfilterPolicy.resolve(1918, 1078),
        'scale=1920:1088:flags=neighbor',
      );
    });

    test('宽高同时非对齐 → 两维都补到 16 对齐', () {
      expect(
        VideoAvfilterPolicy.resolve(1919, 1079),
        'scale=1920:1088:flags=neighbor',
      );
    });

    test('触发后目标一律 ceil16：1921x1080 → 1936x1088', () {
      expect(
        VideoAvfilterPolicy.resolve(1921, 1080),
        'scale=1936:1088:flags=neighbor',
      );
    });

    test('非法尺寸（<=0）返回 null，不写坏滤镜串', () {
      expect(VideoAvfilterPolicy.resolve(0, 1080), isNull);
      expect(VideoAvfilterPolicy.resolve(1920, 0), isNull);
      expect(VideoAvfilterPolicy.resolve(-1, -1), isNull);
    });

    test('只补不裁：非对齐值永远 ceil 到原值之上', () {
      // 1585（非 8 对齐）→ 1600，绝不裁到 1584
      expect(VideoAvfilterPolicy.resolve(3840, 1585),
          'scale=3840:1600:flags=neighbor');
    });
  });
}
