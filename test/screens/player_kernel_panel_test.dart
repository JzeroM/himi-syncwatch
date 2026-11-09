import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_kernel_panel.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('646.1：Windows 内核面板显示 MPV，移除 media_kit 入口', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final engines = PlayerEngineFactory.supportedEngines();
    expect(engines, contains(PlayerEngine.mpv));
    expect(engines, isNot(contains(PlayerEngine.mediaKit)));
    expect(engines, contains(PlayerEngine.mdk));
    expect(engines, contains(PlayerEngine.erika));
  });

  test('MPV 描述不再标记为鸿蒙专用', () {
    expect(
      PlayerKernelPanel.descriptionOf(PlayerEngine.mpv),
      isNot(contains('鸿蒙专用')),
    );
    expect(
      PlayerKernelPanel.descriptionOf(PlayerEngine.mpv),
      contains('Surface/纹理可配'),
    );
  });
}
