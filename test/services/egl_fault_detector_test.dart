import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/egl_fault_detector.dart';

/// 黑屏自愈检测器：判据来自 H96_Max_RK3528 真机深诊日志。
void main() {
  group('EglFaultDetector', () {
    late EglFaultDetector d;

    setUp(() => d = EglFaultDetector());

    test('初始未故障', () {
      expect(d.fault, isFalse);
      expect(d.feed('ffmpeg.configuration ...'), isFalse);
    });

    test('真机样本 No EGL config found 命中', () {
      expect(
        d.feed('[mdk] ContextEGL ERROR! No EGL config found'),
        isTrue,
      );
      expect(d.fault, isTrue);
    });

    test('真机样本 eglChooseConfig EGL ERROR (3004) 命中', () {
      expect(
        d.feed('ret = eglChooseConfig(disp, ca.data(), nullptr, 0, &nb_cfgs) '
            'EGL ERROR (3004) @820ensureConfig'),
        isTrue,
      );
      expect(d.fault, isTrue);
    });

    test('幂等：命中后再次 feed 返回 false 且状态不变', () {
      expect(d.feed('No EGL config found'), isTrue);
      expect(d.feed('EGL ERROR (3004)'), isFalse);
      expect(d.fault, isTrue);
    });

    test('其他 EGL 错误码不误报（判据收窄）', () {
      expect(d.feed('eglBindAPI EGL ERROR (3009)'), isFalse);
      expect(d.fault, isFalse);
    });

    test('正常渲染日志不误报', () {
      for (final line in [
        '1st video frame rendered',
        'EGL extensions: EGL_ANDROID_recordable EGL_EXT_yuv_surface',
        'release MediaCodec output buffer which was not rendered @0',
        'ContextGL: using EGL 1.5',
      ]) {
        expect(d.feed(line), isFalse, reason: line);
      }
      expect(d.fault, isFalse);
    });

    test('reset 恢复初始状态', () {
      d.feed('No EGL config found');
      expect(d.fault, isTrue);
      d.reset();
      expect(d.fault, isFalse);
      expect(d.feed('No EGL config found'), isTrue);
    });

    test('全局实例可被共享访问', () {
      eglFaultDetector.reset();
      expect(eglFaultDetector.fault, isFalse);
    });
  });
}
