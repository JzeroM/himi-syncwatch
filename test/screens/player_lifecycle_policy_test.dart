import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_lifecycle_policy.dart';

void main() {
  group('PlayerLifecyclePolicy.enterBackground', () {
    test('paused/hidden 视为进入后台（熄屏与切后台同链路）', () {
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.paused),
          isTrue);
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.hidden),
          isTrue);
    });

    test('inactive/resumed/detached 不算进入后台（瞬时失焦不重建）', () {
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.inactive),
          isFalse);
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.resumed),
          isFalse);
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.detached),
          isFalse);
    });
  });

  group('PlayerLifecyclePolicy.resumeAction', () {
    test('纹理/直通档 → 重建纹理', () {
      expect(PlayerLifecyclePolicy.resumeAction('texture'),
          PlayerResumeAction.recreateTexture);
      expect(PlayerLifecyclePolicy.resumeAction('tunnel'),
          PlayerResumeAction.recreateTexture);
    });

    test('SurfaceView 档 → 仅补帧（platform view 自行重绑）', () {
      expect(PlayerLifecyclePolicy.resumeAction('surfaceView'),
          PlayerResumeAction.pulseSurface);
    });
  });
}
