import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/fvp_options.dart';

void main() {
  group('buildFvpOptions（fvp 启动期全局选项）', () {
    test('默认：avsync.audio.adaptive 常开 + videoout.hdr=0，无 xa2/兼容模式', () {
      final options = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: false,
        videoOutHdrAuto: false,
      );
      expect(options.keys, ['global']);
      final global = options['global'] as Map;
      expect(global['avsync.audio.adaptive'], 1);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
      expect(global['videoout.hdr'], 0);
      expect(global.length, 2);
    });

    test('Windows：注入 audio.xa2.persistent=1', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: false,
        videoOutHdrAuto: false,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global.containsKey('gl.yuv_sampler'), isFalse);
      expect(global.containsKey('surfacetexture.glcontext'), isFalse);
      // avsync 常开不受平台开关影响
      expect(global['avsync.audio.adaptive'], 1);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
    });

    test('渲染兼容模式：注入 rockchip yuv 采样 + SurfaceTexture 上下文', () {
      final global = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: true,
        videoOutHdrAuto: false,
      )['global'] as Map;
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global.containsKey('audio.xa2.persistent'), isFalse);
    });

    test('HDR 输出自适应：videoout.hdr=1（1.1.187 实验开关）', () {
      final global = buildFvpOptions(
        xa2Persistent: false,
        renderCompatMode: false,
        videoOutHdrAuto: true,
      )['global'] as Map;
      expect(global['videoout.hdr'], 1);
    });

    test('三项同时开启：选项齐全互不覆盖（含 avsync 常开共 5 项）', () {
      final global = buildFvpOptions(
        xa2Persistent: true,
        renderCompatMode: true,
        videoOutHdrAuto: true,
      )['global'] as Map;
      expect(global['audio.xa2.persistent'], 1);
      expect(global['gl.yuv_sampler'], 1);
      expect(global['surfacetexture.glcontext'], 1);
      expect(global['avsync.audio.adaptive'], 1);
      expect(global.containsKey('avsync.video.decoder_drop'), isFalse);
      expect(global['videoout.hdr'], 1);
      expect(global.length, 5);
    });
  });
}
