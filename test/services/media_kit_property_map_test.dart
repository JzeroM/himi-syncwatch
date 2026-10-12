import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/media_kit_player_adapter.dart';

void main() {
  group('MediaKitPlayerAdapter.mapMdkPropertyToMpv（字幕属性映射）', () {
    test('字幕开关：subtitle 1/0 → sub-visibility yes/no', () {
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle', '1'),
        (name: 'sub-visibility', value: 'yes'),
      );
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle', '0'),
        (name: 'sub-visibility', value: 'no'),
      );
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle', 'true'),
        (name: 'sub-visibility', value: 'yes'),
      );
    });

    test('字幕样式：scale/margin/font/border/shadow 映射到 mpv 属性', () {
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle.scale', '1.20'),
        (name: 'sub-scale', value: '1.20'),
      );
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle.margin.y', '40'),
        (name: 'sub-margin-y', value: '40'),
      );
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle.font.size', '40'),
        (name: 'sub-font-size', value: '40'),
      );
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle.border', '2'),
        (name: 'sub-outline-size', value: '2'),
      );
    });

    test('字幕阴影：1 → offset 1；0 → offset 0（mpv 无开关语义）', () {
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle.shadow', '1'),
        (name: 'sub-shadow-offset', value: '1'),
      );
      expect(
        MediaKitPlayerAdapter.mapMdkPropertyToMpv('subtitle.shadow', '0'),
        (name: 'sub-shadow-offset', value: '0'),
      );
    });

    test('非字幕属性原样透传（mpv 直写通道）', () {
      for (final name in const [
        'hwdec',
        'tone-mapping',
        'cache-size',
        'avformat.probesize',
        'audio.avfilter',
        'http-header-fields',
      ]) {
        expect(
          MediaKitPlayerAdapter.mapMdkPropertyToMpv(name, 'v'),
          (name: name, value: 'v'),
          reason: name,
        );
      }
    });
  });
}
