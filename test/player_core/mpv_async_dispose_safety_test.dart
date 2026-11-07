import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 631：Windows「从 MPV 切换引擎点击即闪退」根因防回归。
///
/// 事故链（全部可在源码中验证，无需真机）：
/// 1. 618 给 Windows 设 `async: false` → media_kit 走**同步 FFI**
///    （`mpv_set_property_string` / `mpv_command`），直接解引用 `ctx`，
///    且**没有**有效性检查。
/// 2. media_kit `Player.dispose()` 内部顺序：
///      NativeReferenceHolder.remove(ctx) → stop() → disposed = true
///    `stop()` 执行时 `disposed` 仍为 false，`_command` 的守卫
///    `if (_isClosing || disposed) return;` 放行 → 真的写 ctx。
/// 3. 切换引擎时 `_disposeOldEngine()` 对 dispose 加超时；超时后继续
///    创建新引擎，旧 session 仍在后台销毁 → 与第 2 步叠加 = 访问已释放
///    内存 → 段错误（Dart try/catch 抓不到，进程直接退出）。
///
/// 因此本测试把两条硬约束锁死：
/// - Windows **不得**出现 `async: false`
/// - `_disposeOldEngine` 的 dispose 超时 **≥ 4s**
void main() {
  final windows = File(
    'plugins/himi_mpv_windows/lib/himi_mpv_windows.dart',
  ).readAsStringSync();
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final screen = File(
    'lib/screens/player/player_screen.dart',
  ).readAsStringSync();

  /// 去掉行注释，避免「注释里提到 async: false」被误判成真实配置。
  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  group('① Windows 必须异步入队（async: true）', () {
    test('源码中不得出现 async: false', () {
      expect(
        stripComments(windows),
        isNot(contains('async: false')),
        reason: '同步 FFI 在 dispose 竞态下解引用已释放 ctx → 段错误',
      );
    });

    test('不得显式传 async: true 以外的值', () {
      // PlayerConfiguration 里 async 只应缺省（默认 true）。
      expect(
        RegExp(r'async:\s*(?!true)').hasMatch(stripComments(windows)),
        isFalse,
        reason: 'async 只能缺省或显式 true',
      );
    });

    test('根因注释留档（631）', () {
      expect(windows, contains('631'));
      expect(windows, contains('dispose'));
    });
  });

  group('② Android 保持 618 的加速（未观察到崩溃）', () {
    test('仍传 async: false', () {
      expect(stripComments(android), contains('async: false,'));
    });
  });

  group('③ 引擎切换的 dispose 超时足够', () {
    test('_disposeOldEngine 超时 ≥ 4 秒', () {
      final start = screen.indexOf('Future<void> _disposeOldEngine() async {');
      expect(start, greaterThan(0), reason: '未找到 _disposeOldEngine');
      // 取函数体到下一个顶层方法声明之间。
      final end = screen.indexOf('Future<void> _recreateEngineForLoad(', start);
      expect(end, greaterThan(start));
      final body = screen.substring(start, end);
      final match = RegExp(r'seconds:\s*(\d+)').firstMatch(body);
      expect(match, isNotNull, reason: 'dispose 必须带 timeout');
      final seconds = int.parse(match!.group(1)!);
      expect(
        seconds,
        greaterThanOrEqualTo(4),
        reason: 'Windows 销毁 libmpv ctx + SHUTDOWN + destroySurface(HWND) '
            '需要更长时间；2s 易超时导致新旧 session 争抢同一 HWND',
      );
    });

    test('超时后不再把旧 player 当有效对象使用', () {
      final start = screen.indexOf('Future<void> _disposeOldEngine() async {');
      final end = screen.indexOf('Future<void> _recreateEngineForLoad(', start);
      final body = screen.substring(start, end);
      // dispose 之后不得再访问 old 的播放接口。
      final afterDispose = body.substring(body.indexOf('disposeAsync()'));
      expect(afterDispose, isNot(contains('old.play(')));
      expect(afterDispose, isNot(contains('old.setProperty(')));
    });
  });
}
