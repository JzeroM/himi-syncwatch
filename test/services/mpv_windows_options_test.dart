import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_windows/himi_mpv_windows.dart';

void main() {
  group('buildWindowsMpvOptions', () {
    test('初始化前启用视频/音频轨并固定 gpu-next', () {
      final options = buildWindowsMpvOptions(hdr: false, hlg: false);

      expect(options['vo'], 'gpu-next');
      expect(options['vid'], 'auto');
      expect(options['aid'], 'auto');
      expect(options['gpu-api'], 'd3d11');
      expect(options['gpu-context'], 'd3d11');
      expect(options['d3d11-output-format'], 'auto');
      expect(options['d3d11-output-mode'], 'window');
      expect(options['gpu-hwdec-interop'], 'auto');
      expect(options['hwdec'], 'auto-copy');
      expect(options['cache-on-disk'], 'no');
      expect(options.containsKey('target-colorspace-hint'), isFalse);
    });

    test('HDR10 参数完整', () {
      final options = buildWindowsMpvOptions(hdr: true, hlg: false);

      expect(options['d3d11-output-format'], 'rgb10_a2');
      expect(options['target-colorspace-hint'], 'yes');
      expect(options['target-prim'], 'bt.2020');
      expect(options['target-trc'], 'pq');
      expect(options['hdr-compute-peak'], 'auto');
      expect(options['tone-mapping'], 'clip');
    });

    test('HLG 使用 hlg target-trc', () {
      final options = buildWindowsMpvOptions(hdr: true, hlg: true);

      expect(options['target-trc'], 'hlg');
    });
  });
}
