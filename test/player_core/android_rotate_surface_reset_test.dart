import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 615：安卓横转竖后画面被裁切（surface 窗口尺寸未随转屏重设）。
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
    'NativePlayerScreenView.kt',
  ).readAsStringSync();

  group('① 转屏后无条件重设 surface 窗口尺寸', () {
    test('onSizeChanged 不再只在 inset>0 时重置', () {
      final idx = kotlin.indexOf('override fun onSizeChanged(');
      expect(idx, greaterThan(0));
      final end = kotlin.indexOf('companion object {', idx);
      final body = kotlin.substring(idx, end);
      // 旧写法：`if (lastVideoSplitInsetPx > 0) { ... }` 必须移除。
      expect(body, isNot(contains('if (lastVideoSplitInsetPx > 0) {')));
      // 新写法：无条件重置两个 inset。
      expect(body, contains('val prevInset = lastVideoSplitInsetPx.coerceAtLeast(0)'));
      expect(body, contains('lastVideoSplitInsetPx = -1'));
      expect(body, contains('lastVideoInsetRightPx = -1'));
    });

    test('重置后重新应用控件分栏 + surface 窗口', () {
      final idx = kotlin.indexOf('override fun onSizeChanged(');
      final end = kotlin.indexOf('companion object {', idx);
      final body = kotlin.substring(idx, end);
      expect(body, contains('applyVideoSplit(prevInset)'));
      expect(body, contains('listener?.onVideoInsetRight(prevInset)'));
    });

    test('注释记录「两条短路同时拦住」根因', () {
      expect(kotlin, contains('两条短路同时拦住'));
    });
  });

  group('② applyVideoSplit 恢复全屏时不走幂等短路', () {
    test('inset<=0 时无条件执行', () {
      final idx = kotlin.indexOf('private fun applyVideoSplit(insetPx: Int) {');
      expect(idx, greaterThan(0));
      final body = kotlin.substring(idx, idx + 500);
      expect(body, contains('if (insetPx > 0 && insetPx == lastVideoSplitInsetPx) return'));
      // 旧的无条件短路必须移除。
      expect(body, isNot(contains('if (insetPx == lastVideoSplitInsetPx) return')));
    });
  });

  group('③ 非房间模式强制恢复全屏', () {
    test('renderRoomPanel 有 forceFullscreen', () {
      final idx = kotlin.indexOf('private fun renderRoomPanel() {');
      expect(idx, greaterThan(0));
      final body = kotlin.substring(idx, idx + 2500);
      expect(body, contains('val forceFullscreen = !show && lastVideoInsetRightPx != 0'));
      expect(body, contains('if (panelPx != lastVideoInsetRightPx || forceFullscreen)'));
    });
  });

  group('④ placeholderView 纳入分栏收窄', () {
    test('applyVideoSplit 里收窄 placeholderView', () {
      final idx = kotlin.indexOf('private fun applyVideoSplit(insetPx: Int) {');
      final end = kotlin.indexOf('private fun applyState()', idx);
      final body = kotlin.substring(idx, end);
      expect(body, contains('placeholderView.layoutParams'));
      expect(body, contains('it.width = videoW; it.height = videoH; placeholderView.layoutParams = it'));
    });
  });

  group('⑤ 宿主侧窗口尺寸重设仍是 setLayout（未回退）', () {
    test('applyVideoInsetRight 用 setLayout 且无短路', () {
      final host = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'AndroidNativePlayerHost.kt',
      ).readAsStringSync();
      final idx = host.indexOf('private fun applyVideoInsetRight(insetPx: Int) {');
      expect(idx, greaterThan(0));
      final body = host.substring(idx, idx + 1600);
      expect(body, contains('win.setLayout(targetW, targetH)'));
      expect(body, contains('lastVideoInsetPx = insetPx.coerceAtLeast(0)'));
    });
  });
}
