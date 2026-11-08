import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 645：Windows 退出/切引擎闪退的最终根因——media_kit 适配器 `stopped`
/// 分支用了 `_player.stop()`，与 `dispose()` 内部的 `stop()` 竞争 mpv ctx。
///
/// 【为什么所有引擎都崩】
/// Windows 默认引擎是 media_kit（641 起）。无论点返回还是切到 MDK/Erika，
/// 旧引擎都是 media_kit，`_recreateEngineForLoad` / 退出路径的第一步都是
/// `_player.state = stopped` → 本 setter → `_player.stop()`。
///
/// 【竞争链】
///   外部：_player.stop()（fire-and-forget，排队进 lock.synchronized）
///   紧接：_player.dispose() → 内部
///         stop(notify: false, synchronized: false)   ← 不加锁，立即执行
///         Initializer(mpv).dispose(ctx)
///         _terminateNativePlayer(...)                ← ctx 已销毁
///   此时外部 stop 的续体才真正执行 _command(['stop']) → 访问已销毁 ctx
///   → 0xc0000005（Windows SEH，Dart try/catch 抓不到）
///
/// 【对照证据】旧适配器 `lib/services/player/media_kit_player_adapter.dart`
/// 的 stopped 分支用 `_player.pause()`，Windows 从未因此崩溃。
/// 剥离 Dart 行注释（`//`），避免注释里提到的 `_player.stop()` 被误判。
String stripLineComments(String src) => src
    .split('\n')
    .map((l) {
      final idx = l.indexOf('//');
      return idx >= 0 ? l.substring(0, idx) : l;
    })
    .join('\n');

void main() {
  String read(String p) => File(p).readAsStringSync();

  const adapterPath = 'lib/player_core/adapters/nipa_media_kit_adapter.dart';
  const oldAdapterPath = 'lib/services/player/media_kit_player_adapter.dart';

  group('① state setter 的 stopped 分支改用 pause（核心修复）', () {
    late String src;

    setUp(() => src = read(adapterPath));

    test('stopped 分支调 pause() 而不是 stop()', () {
      final code = stripLineComments(src);
      final start = code.indexOf('set state(PlayerPlaybackState value) {');
      expect(start, greaterThan(-1));
      final body = code.substring(start, start + 1200);

      final stoppedIdx = body.indexOf('PlayerPlaybackState.stopped:');
      expect(stoppedIdx, greaterThan(-1));

      // 取 stopped 分支到下一个 case 之间的代码。
      final nextCase = body.indexOf('case PlayerPlaybackState.paused:', stoppedIdx);
      expect(nextCase, greaterThan(stoppedIdx));
      final branch = body.substring(stoppedIdx, nextCase);

      expect(
        branch,
        contains('_player.pause()'),
        reason: 'stopped 分支必须用 pause()（对齐旧适配器）',
      );
      expect(
        branch,
        isNot(contains('_player.stop()')),
        reason: 'stop() 会与 dispose() 内部的 stop() 竞争 mpv ctx → 0xc0000005',
      );
    });

    test('_ticker?.stop() 保留（内部 ticker，与 mpv 无关）', () {
      final start = src.indexOf('set state(PlayerPlaybackState value) {');
      final body = src.substring(start, start + 2600);
      final stoppedIdx = body.indexOf('PlayerPlaybackState.stopped:');
      final nextCase = body.indexOf('case PlayerPlaybackState.paused:', stoppedIdx);
      final branch = body.substring(stoppedIdx, nextCase);
      expect(branch, contains('_ticker?.stop()'));
    });

    test('playing / paused 分支不变', () {
      final start = src.indexOf('set state(PlayerPlaybackState value) {');
      final body = src.substring(start, start + 2600);
      expect(body, contains('_player.play()'));
      expect(body, contains('_player.pause()'));
    });

    test('state setter 的 644 dispose 守卫仍保留', () {
      final start = src.indexOf('set state(PlayerPlaybackState value) {');
      final body = src.substring(start, start + 2600);
      final guardIdx = body.indexOf('if (_isDisposed)');
      final switchIdx = body.indexOf('switch (value)');
      expect(guardIdx, greaterThan(-1));
      expect(switchIdx, greaterThan(guardIdx));
    });
  });

  group('② 回归守卫：state setter 内不得再出现 _player.stop()', () {
    test('全文件的 _player.stop() 都不在 state setter 里', () {
      final code = stripLineComments(read(adapterPath));
      final start = code.indexOf('set state(PlayerPlaybackState value) {');
      expect(start, greaterThan(-1));
      // 取 setter 到方法结束（下一个 2 空格缩进的 `}`）。
      final end = code.indexOf('\n  }', start);
      expect(end, greaterThan(start));
      final setter = code.substring(start, end);
      expect(
        setter,
        isNot(contains('_player.stop()')),
        reason: 'state setter 里出现 stop() 会重现 0xc0000005',
      );
    });
  });

  group('③ 对照旧适配器（Windows 从未崩的实现）', () {
    test('旧适配器 stopped 分支用 pause()', () {
      final src = read(oldAdapterPath);
      final start = src.indexOf('set state(AdapterPlaybackState value) {');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 500);
      expect(body, contains('AdapterPlaybackState.stopped'));
      expect(body, contains('_player.pause()'));
    });

    test('旧适配器全文没有 _player.stop()', () {
      expect(
        read(oldAdapterPath),
        isNot(contains('_player.stop()')),
        reason: '旧实现从不调 stop()，这正是它不崩的原因',
      );
    });

    test('新适配器已对齐（state setter 也用 pause）', () {
      final code = stripLineComments(read(adapterPath));
      final start = code.indexOf('set state(PlayerPlaybackState value) {');
      final end = code.indexOf('\n  }', start);
      final setter = code.substring(start, end);
      expect(setter, contains('_player.pause()'));
    });
  });

  group('④ 诊断增强：debugPrint 接入运行时日志', () {
    late String mainSrc;

    setUp(() => mainSrc = read('lib/main.dart'));

    test('debugPrint 被重定向到 LogService', () {
      expect(mainSrc, contains('debugPrint = (String? message'));
      expect(mainSrc, contains("LogService().log('debug', message)"));
    });

    test('重定向在 _installErrorHooks 内（启动早期生效）', () {
      final start = mainSrc.indexOf('void _installErrorHooks()');
      expect(start, greaterThan(-1));
      final body = mainSrc.substring(start, start + 2000);
      expect(body, contains('debugPrint ='));
    });
  });

  group('⑤ 关键路径分步日志（崩溃可精确定位）', () {
    late String screen;

    setUp(() => screen = read('lib/screens/player/player_screen.dart'));

    test('_recreateEngineForLoad 有 7 步日志', () {
      final start = screen.indexOf('Future<void> _recreateEngineForLoad(');
      expect(start, greaterThan(-1));
      final body = screen.substring(start, start + 3000);
      for (final step in ['1/7', '2/7', '3/7', '4/7', '5/7', '6/7', '7/7']) {
        expect(body, contains('[rebuild] $step'), reason: '缺少 $step 日志');
      }
    });

    test('_disposeOldEngine 有开始/完成日志', () {
      final start = screen.indexOf('Future<void> _disposeOldEngine() async {');
      expect(start, greaterThan(-1));
      final body = screen.substring(start, start + 2200);
      expect(body, contains('[dispose-old] 开始'));
      expect(body, contains('[dispose-old] disposeAsync 完成'));
      expect(body, contains('[dispose-old] 结束'));
    });
  });
}
