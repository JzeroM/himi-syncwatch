import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/fvp_options.dart';

void main() {
  group('buildFvpOptions（fvp 启动期全局选项）', () {
    test('默认：avsync 关（0）+ videoout.hdr 恒 0，无 xa2/兼容模式', () {
      final options = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: false,
        avsyncAudioAdaptive: false,
      );
      expect(options.keys, ['global']);
      final global = options['global'] as Map;
      expect(global['avsync.audio.adaptive'], 0);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
      expect(global['videoout.hdr'], 0);
      expect(global.length, 2);
    });

    test('avsync 开关开启：avsync.audio.adaptive=1（实验开关，默认关）', () {
      final global = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: false,
        avsyncAudioAdaptive: true,
      )['global'] as Map;
      expect(global['avsync.audio.adaptive'], 1);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
    });

    test('videoout.hdr 恒 0（HDR/DV 输出改由 Player.set(ColorSpace) 控制）', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: true,
        avsyncAudioAdaptive: true,
      )['global'] as Map;
      expect(global['videoout.hdr'], 0);
    });

    test('Windows：注入 audio.xa2.persistent=1（不受 avsync 开关影响）', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: false,
        avsyncAudioAdaptive: false,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global.containsKey('gl.yuv_sampler'), isFalse);
      expect(global.containsKey('surfacetexture.glcontext'), isFalse);
      expect(global['avsync.audio.adaptive'], 0);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
    });

    test('渲染兼容模式：注入 rockchip yuv 采样 + SurfaceTexture 上下文', () {
      final global = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: true,
        avsyncAudioAdaptive: false,
      )['global'] as Map;
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global.containsKey('audio.xa2.persistent'), isFalse);
    });

    test('全开关同时开启：选项齐全互不覆盖（共 5 项，videoout.hdr 仍 0）', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: true,
        avsyncAudioAdaptive: true,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global['avsync.audio.adaptive'], 1);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
      expect(global['videoout.hdr'], 0);
      expect(global.length, 5);
    });
  });
}
