import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/fvp_surface_view.dart';

void main() {
  group('FvpSurfaceView.surfaceKey（切集强制重建的 key 语义）', () {
    test('同参数同 key（同集内复用，不销毁 view）', () {
      final a = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      final b = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      expect(a, b);
    });

    test('epoch+1 key 必变（切集强制销毁重建 platform view）', () {
      final a = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      final b = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 1);
      expect(a, isNot(b),
          reason: '切集后旧 surface 的 setDecoders({}) 必须先于新 '
              'surface 的 setDecoders(surface) 落定');
    });

    test('分辨率/tunnel 变化同样触发重建（原有语义不回归）', () {
      final base = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      expect(
          FvpSurfaceView.surfaceKey(
              width: 1280, height: 720, tunnel: false, epoch: 0),
          isNot(base));
      expect(
          FvpSurfaceView.surfaceKey(
              width: 1920, height: 1080, tunnel: true, epoch: 0),
          isNot(base));
    });
  });
}
