import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 683：Android Kotlin 编译失败（`LayoutParams` 用了 `Window` 的方法）。
///
/// ## CI 报错
///
/// ```
/// e: AndroidNativePlayerHost.kt:552:25 Unresolved reference 'addFlags'
/// e: AndroidNativePlayerHost.kt:565:25 Unresolved reference 'addFlags'
/// e: AndroidNativePlayerHost.kt:582:25 Unresolved reference 'clearFlags'
/// e: AndroidNativePlayerHost.kt:598:25 Unresolved reference 'clearFlags'
/// > Execution failed for task ':app:compileReleaseKotlin'
/// ```
///
/// ## 根因
///
/// `addFlags` / `clearFlags` 是 **`android.view.Window`** 的方法，
/// `WindowManager.LayoutParams` **没有**这两个方法。
///
/// 同一文件里两处接收者不同，极易混淆：
///
/// ```kotlin
/// // ✅ 接收者是 Window（Dialog.window）
/// dlg.window?.apply {
///     addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
/// }
///
/// // ❌ 接收者是 LayoutParams（window.attributes）——没有 addFlags
/// w.attributes = w.attributes.apply {
///     addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
/// }
/// ```
///
/// 682 新增的 `suspend()` / `resume()` 误用了后者。修复：`LayoutParams`
/// 直接操作 `flags` 位字段——
///   加：`flags = flags or FLAG`
///   清：`flags = flags and FLAG.inv()`
///
/// 用 `and inv()` 而不是 `flags = 0`，保证只清这一位，不误清
/// `applyFullscreen` 维护的 `FLAG_KEEP_SCREEN_ON` / `FLAG_FULLSCREEN`。
void main() {
  const path = 'android/app/src/main/kotlin/com/himi/syncwatch/'
      'nativeplayer/AndroidNativePlayerHost.kt';
  final src = File(path).readAsStringSync();
  final lines = src.split('\n');

  /// 剔除注释行（注释里会提到旧写法，说明为什么改）。
  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  /// 判断某行调用的 `addFlags`/`clearFlags` 的接收者是谁：
  /// 向上找最近的 `xxx.apply {`。
  String receiverOf(int lineIndex) {
    final re = RegExp(r'(\w+(?:\.\w+)*)\s*(?:\?\.)?apply\s*\{');
    for (var j = lineIndex - 1; j >= 0; j--) {
      final m = re.firstMatch(lines[j]);
      if (m != null) return m.group(1)!;
    }
    return '?';
  }

  group('A LayoutParams 不得调用 Window 的方法', () {
    test('A1 全文件只有 Window 接收者能用 addFlags/clearFlags', () {
      final violations = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final t = line.trimLeft();
        if (t.startsWith('//') || t.startsWith('*')) continue;
        if (!RegExp(r'\b(addFlags|clearFlags)\s*\(').hasMatch(line)) continue;
        final recv = receiverOf(i);
        // 合法接收者：Dialog.window（Window 实例）
        if (!recv.endsWith('window')) {
          violations.add('第 ${i + 1} 行：接收者=$recv');
        }
      }
      expect(violations, isEmpty,
          reason: 'LayoutParams 没有 addFlags/clearFlags，会编译失败：\n'
              '${violations.join('\n')}');
    });

    test('A2 suspend 用 flags or 加 NOT_TOUCHABLE', () {
      final idx = src.indexOf('fun suspend() {');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 1600);
      expect(body, contains('flags = flags or'));
      expect(body, contains('FLAG_NOT_TOUCHABLE'));
      // 不得再出现 Window 方法
      expect(codeOnly(body), isNot(contains('addFlags')));
    });

    test('A3 resume 用 flags and inv() 清 NOT_TOUCHABLE', () {
      final idx = src.indexOf('fun resume() {');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 1600);
      expect(body, contains('flags = flags and'));
      expect(body, contains('FLAG_NOT_TOUCHABLE.inv()'));
      expect(codeOnly(body), isNot(contains('clearFlags')));
    });

    test('A4 只清 NOT_TOUCHABLE 一位（不误清全屏/常亮）', () {
      // resume 里必须是 `and inv()`，不能是 `flags = 0` 之类的粗暴清零。
      final idx = src.indexOf('fun resume() {');
      final body = src.substring(idx, idx + 1600);
      expect(body, isNot(contains('flags = 0')));
      expect(body, contains('FLAG_NOT_TOUCHABLE.inv()'));
    });
  });

  group('B 双窗都处理（surface + controls）', () {
    test('B1 suspend 两个窗口都加 NOT_TOUCHABLE', () {
      final idx = src.indexOf('fun suspend() {');
      final body = src.substring(idx, idx + 1600);
      final count = RegExp(r'flags = flags or').allMatches(body).length;
      expect(count, 2, reason: 'surface 窗与控件窗都要处理');
    });

    test('B2 resume 两个窗口都清 NOT_TOUCHABLE', () {
      final idx = src.indexOf('fun resume() {');
      final body = src.substring(idx, idx + 1600);
      final count =
          RegExp(r'FLAG_NOT_TOUCHABLE\.inv\(\)').allMatches(body).length;
      expect(count, 2, reason: 'surface 窗与控件窗都要处理');
    });
  });

  group('C 不破坏既有全屏逻辑', () {
    test('C1 applyFullscreen 仍用 Window.addFlags（合法用法）', () {
      final idx = src.indexOf('private fun applyFullscreen(');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 900);
      // 接收者是 dlg.window → Window，addFlags 合法
      expect(body, contains('dlg.window?.apply'));
      expect(body, contains('addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)'));
      expect(body, contains('addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)'));
    });

    test('C2 suspend 不销毁窗口（不 hide，保留 surface）', () {
      final idx = src.indexOf('fun suspend() {');
      final body = src.substring(idx, idx + 1600);
      expect(body, isNot(contains('.hide()')));
      expect(body, contains('alpha = 0f'));
    });
  });
}
