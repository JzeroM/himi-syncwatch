import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/fvp_surface_view.dart';

void main() {
  group('FvpSurfaceView.surfaceKey（必要重建的 key 语义）', () {
    test('同参数同 key（同集内复用，不销毁 view）', () {
      final a = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      final b = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      expect(a, b);
    });

    test('epoch+1 key 必变（两阶段重建 attach 阶段强制换 view）', () {
      final a = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 0);
      final b = FvpSurfaceView.surfaceKey(
          width: 1920, height: 1080, tunnel: false, epoch: 1);
      expect(a, isNot(b),
          reason: 'detach（旧 surface 解绑落定）与 attach（新 view 创建）'
              '必须分帧，epoch 保证 attach 必换新 key');
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

  group('creationParams（与上游 fvp FvpVideoView 协议对照，升版防失配）', () {
    test('键名与上游一致：player/width/height/tunnel', () {
      final params = FvpSurfaceView.creationParams(
        nativeHandle: 12345,
        videoWidth: 3840,
        videoHeight: 2160,
        tunnel: false,
      );
      expect(params.keys.toSet(), {'player', 'width', 'height', 'tunnel'});
      expect(params['player'], 12345);
      expect(params['width'], 3840);
      expect(params['height'], 2160);
      expect(params['tunnel'], false);
    });

    test('tunnel=true 直传（Java 侧 Boolean.TRUE.equals 判定）', () {
      final params = FvpSurfaceView.creationParams(
        nativeHandle: -1,
        videoWidth: 1920,
        videoHeight: 1080,
        tunnel: true,
      );
      expect(params['tunnel'], isTrue);
      expect(params['player'], -1);
    });

    test('viewType 常量与上游 buildViewWithOptions 一致', () {
      expect(FvpSurfaceView.platformViewType, 'fvp/video-view');
    });
  });
}
