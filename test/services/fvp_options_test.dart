import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/fvp_options.dart';

void main() {
  group('buildFvpOptions（fvp 启动期全局选项）', () {
    test('默认（无 xa2、无兼容模式）仅含空 global', () {
      final options = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: false,
      );
      expect(options.keys, ['global']);
      expect((options['global'] as Map).isEmpty, isTrue);
    });

    test('Windows：注入 audio.xa2.persistent=1', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: false,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global.containsKey('gl.yuv_sampler'), isFalse);
      expect(global.containsKey('surfacetexture.glcontext'), isFalse);
    });

    test('渲染兼容模式：注入 rockchip yuv 采样 + SurfaceTexture 上下文', () {
      final global = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: true,
      )['global'] as Map;
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global.containsKey('audio.xa2.persistent'), isFalse);
    });

    test('两项同时开启：选项齐全互不覆盖', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: true,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global.length, 3);
    });
  });
}
