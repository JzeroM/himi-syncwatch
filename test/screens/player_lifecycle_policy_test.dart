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

    test('inactive/resumed/detached 不算进入后台（瞬时失焦不重载）', () {
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.inactive),
          isFalse);
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.resumed),
          isFalse);
      expect(PlayerLifecyclePolicy.enterBackground(AppLifecycleState.detached),
          isFalse);
    });
  });

  group('PlayerLifecyclePolicy.resumeAction', () {
    test('纹理/直通档 → 重载当前流重建管线', () {
      expect(PlayerLifecyclePolicy.resumeAction('texture'),
          PlayerResumeAction.reprime);
      expect(PlayerLifecyclePolicy.resumeAction('tunnel'),
          PlayerResumeAction.reprime);
    });

    test('SurfaceView 档 → 不处理（platform view 自愈）', () {
      expect(PlayerLifecyclePolicy.resumeAction('surfaceView'),
          PlayerResumeAction.none);
    });
  });
}
