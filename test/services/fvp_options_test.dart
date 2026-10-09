import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/fvp_options.dart';

void main() {
  group('buildFvpOptions（fvp 启动期全局选项）', () {
    test('默认：avsync 两参数常开，无 xa2/兼容模式', () {
      final options = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: false,
      );
      expect(options.keys, ['global']);
      final global = options['global'] as Map;
      expect(global['avsync.audio.adaptive'], 1);
      expect(global['avsync.video.decoder_drop'], 1);
      expect(global.length, 2);
    });

    test('Windows：注入 audio.xa2.persistent=1', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: false,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global.containsKey('gl.yuv_sampler'), isFalse);
      expect(global.containsKey('surfacetexture.glcontext'), isFalse);
      // avsync 常开不受平台开关影响
      expect(global['avsync.audio.adaptive'], 1);
      expect(global['avsync.video.decoder_drop'], 1);
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

    test('两项同时开启：选项齐全互不覆盖（含 avsync 常开共 5 项）', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: true,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global['avsync.audio.adaptive'], 1);
      expect(global['avsync.video.decoder_drop'], 1);
      expect(global.length, 5);
    });
  });
}
