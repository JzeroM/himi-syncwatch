import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/video_avfilter_policy.dart';

/// E4（v1.1.74）：mdk 0.39.0 滤镜链回归——非标资源全平台黑屏、
/// 标尺寸（不触发滤镜）正常 → 停用滤镜生成，resolve 恒 null。
/// 恢复滤镜逻辑见 git 历史（v1.1.73 及以前）。
void main() {
  group('VideoAvfilterPolicy.resolve（已停用，恒 null）', () {
    test('标尺寸返回 null（与停用前一致，不写属性）', () {
      expect(VideoAvfilterPolicy.resolve(3840, 2160), isNull);
      expect(VideoAvfilterPolicy.resolve(1920, 1080), isNull);
      expect(VideoAvfilterPolicy.resolve(1280, 720), isNull);
      expect(VideoAvfilterPolicy.resolve(3840, 1584), isNull);
      expect(VideoAvfilterPolicy.resolve(3840, 1592), isNull);
    });

    test('非标尺寸（E4 黑屏样本）也返回 null——不再生成滤镜', () {
      // v1.1.73 实测黑屏的四片源
      expect(VideoAvfilterPolicy.resolve(3840, 1598), isNull);
      expect(VideoAvfilterPolicy.resolve(3840, 1636), isNull);
      expect(VideoAvfilterPolicy.resolve(3832, 2076), isNull);
      expect(VideoAvfilterPolicy.resolve(3840, 1606), isNull);
      // v1.1.70 时代的其他非对齐样本
      expect(VideoAvfilterPolicy.resolve(1918, 1078), isNull);
      expect(VideoAvfilterPolicy.resolve(1919, 1079), isNull);
      expect(VideoAvfilterPolicy.resolve(1921, 1080), isNull);
      expect(VideoAvfilterPolicy.resolve(3840, 1585), isNull);
    });

    test('非法尺寸（<=0）返回 null，不写坏滤镜串', () {
      expect(VideoAvfilterPolicy.resolve(0, 1080), isNull);
      expect(VideoAvfilterPolicy.resolve(1920, 0), isNull);
      expect(VideoAvfilterPolicy.resolve(-1, -1), isNull);
    });
  });
}
