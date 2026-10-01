import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/window_fullscreen_service.dart';

void main() {
  // 测试环境无窗口插件注册：验证所有调用静默兜底、绝不抛出
  test('插件不可用时 isFullScreen 返回 false', () async {
    final service = WindowFullscreenService();
    expect(await service.isFullScreen(), isFalse);
  });

  test('插件不可用时 setFullScreen 静默完成', () async {
    final service = WindowFullscreenService();
    await expectLater(service.setFullScreen(true), completes);
    await expectLater(service.setFullScreen(false), completes);
  });
}
