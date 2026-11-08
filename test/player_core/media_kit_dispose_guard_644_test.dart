import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 644：Windows 退出/切引擎闪退的**真正根因**——media_kit 适配器缺少
/// dispose 守卫。
///
/// 【日志实证】1.5.63 崩溃前最后一行：
///   `[23:25:45.001][Player] 内容路由重建引擎: media_kit → MDK`
/// 紧接着 `_recreateEngineForLoad` 执行 `_player.state = stopped`
/// → `NipaMediaKitAdapter.state` setter → `_player.stop()`
/// → mpv ctx 已释放 → `0xc0000005`（Windows SEH，Dart try/catch 抓不到）。
///
/// 【为什么以前不崩】v1.3.0 之前 Windows 用的是
/// `lib/services/player/media_kit_player_adapter.dart`（旧适配器）：
///   - `stopped` 只调 `_player.pause()`，**从不调 `stop()`**
///   - 有 `_disposed` 守卫
/// v1.3.0 迁移 NipaPlay 后换成 `NipaMediaKitAdapter`（`stopped → stop()`），
/// 641 把 media_kit 设为 Windows 默认后才暴露该缺口。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const adapterPath = 'lib/player_core/adapters/nipa_media_kit_adapter.dart';
  const ifacePath = 'lib/services/player/player_adapter.dart';

  group('① PlayerAdapter 接口暴露 isDisposed（644）', () {
    test('接口声明 isDisposed getter', () {
      final src = read(ifacePath);
      expect(src, contains('bool get isDisposed'));
      // 文档必须说明 SEH 不可捕获（防止后人删掉守卫）。
      expect(src, contains('0xc0000005'));
    });

    test('三个适配器 + 桥都实现 isDisposed', () {
      for (final path in [
        'lib/services/player/mdk_player_adapter.dart',
        'lib/services/player/mpv_player_adapter.dart',
        'lib/services/player/media_kit_player_adapter.dart',
        'lib/services/player/erika_player_adapter.dart',
        'lib/player_core/player_core_bridge.dart',
      ]) {
        final src = read(path);
        expect(src, contains('bool get isDisposed'), reason: path);
      }
    });

    test('NipaMediaKitAdapter 实现 PlayerDisposableState', () {
      final src = read(adapterPath);
      expect(src, contains('PlayerDisposableState'));
      expect(src, contains('bool get isDisposed => _isDisposed'));
    });
  });

  group('② media_kit 适配器：state setter 守卫（崩溃直接点）', () {
    late String src;

    setUp(() => src = read(adapterPath));

    test('守卫在 switch 之前', () {
      final start = src.indexOf('set state(PlayerPlaybackState value) {');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 1800);

      final guardIdx = body.indexOf('if (_isDisposed)');
      final switchIdx = body.indexOf('switch (value)');
      expect(guardIdx, greaterThan(-1), reason: 'state setter 必须有 _isDisposed 守卫');
      expect(switchIdx, greaterThan(guardIdx), reason: '守卫必须在 switch 之前');
    });

    test('守卫分支仍更新本地 _state（不丢状态一致性）', () {
      final start = src.indexOf('set state(PlayerPlaybackState value) {');
      final body = src.substring(start, start + 1800);
      final guardIdx = body.indexOf('if (_isDisposed)');
      final guardBlock = body.substring(guardIdx, guardIdx + 120);
      expect(guardBlock, contains('_state = value'));
      expect(guardBlock, contains('return'));
    });

    test('stopped 分支仍调 stop()（守卫负责拦截，不改变语义）', () {
      final start = src.indexOf('set state(PlayerPlaybackState value) {');
      final body = src.substring(start, start + 1800);
      expect(body, contains('_player.stop()'));
    });
  });

  group('③ 其他原生入口守卫', () {
    late String src;

    setUp(() => src = read(adapterPath));

    /// 断言某方法体内（从签名到原生调用）出现过 _isDisposed。
    void expectGuard(String signature, String nativeCall) {
      final start = src.indexOf(signature);
      expect(start, greaterThan(-1), reason: '找不到 $signature');
      final body = src.substring(start, start + 2600);
      final callIdx = body.indexOf(nativeCall);
      expect(callIdx, greaterThan(-1), reason: '$signature 内找不到 $nativeCall');
      final guardIdx = body.indexOf('_isDisposed');
      expect(
        guardIdx,
        greaterThan(-1),
        reason: '$signature 缺少 _isDisposed 守卫',
      );
      expect(
        guardIdx,
        lessThan(callIdx),
        reason: '$signature 的守卫必须在原生调用之前',
      );
    }

    test('volume setter', () {
      expectGuard('set volume(double value) {', '_player.setVolume');
    });

    test('playbackRate setter', () {
      expectGuard('set playbackRate(double value) {', '_player.setRate');
    });

    test('activeAudioTracks setter', () {
      expectGuard('set activeAudioTracks(List<int> value) {', '_player.setAudioTrack');
    });

    test('activeSubtitleTracks setter', () {
      expectGuard(
        'set activeSubtitleTracks(List<int> value) {',
        '_player.setSubtitleTrack',
      );
    });

    test('_ensureDefaultTracksSelected', () {
      expectGuard('void _ensureDefaultTracksSelected() {', '_player.setAudioTrack');
    });

    test('seekAndWait', () {
      expectGuard('Future<void> seekAndWait({required int position}) async {', '_player.seek');
    });

    test('playDirectly / pauseDirectly', () {
      expectGuard('Future<void> playDirectly() async {', '_player.play');
      expectGuard('Future<void> pauseDirectly() async {', '_player.pause');
    });

    test('stepBackward', () {
      expectGuard('void stepBackward() {', '_player');
    });

    test('_retryJellyfinPlayback', () {
      expectGuard('void _retryJellyfinPlayback() {', '_player');
    });
  });

  group('④ 全量守卫审计（防止将来新增无守卫的原生调用）', () {
    test('所有 _player 原生调用都在含 _isDisposed 的方法体内', () {
      final lines = read(adapterPath).split('\n');
      final reg = RegExp(
        r'_player\.(play|pause|stop|seek|setVolume|setRate|setProperty|'
        r'setAudioTrack|setSubtitleTrack|dispose|open)\(',
      );
      final violations = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().startsWith('//')) continue;
        if (!reg.hasMatch(line)) continue;
        // 向上找方法签名。
        var start = -1;
        for (var j = i; j >= 0; j--) {
          if (RegExp(r'^  (Future|void|bool|int|double|String|set |[A-Z])')
                  .hasMatch(lines[j]) &&
              (lines[j].contains('{') || lines[j].contains('=>'))) {
            start = j;
            break;
          }
        }
        if (start < 0) continue;
        final guarded = lines
            .sublist(start, i + 1)
            .any((l) => l.contains('_isDisposed'));
        if (!guarded) {
          violations.add('L${i + 1}: ${line.trim()}');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '以下原生调用缺少 _isDisposed 守卫（会触发 0xc0000005）：\n'
            '${violations.join('\n')}',
      );
    });
  });

  group('⑤ 对照：旧适配器为何不崩（回归证据）', () {
    test('旧 media_kit 适配器的 stopped 只调 pause，从不调 stop', () {
      final old = read('lib/services/player/media_kit_player_adapter.dart');
      // 旧实现的 stopped 分支用 pause。
      final start = old.indexOf('set state(AdapterPlaybackState value) {');
      expect(start, greaterThan(-1));
      final body = old.substring(start, start + 500);
      expect(body, contains('AdapterPlaybackState.stopped'));
      expect(body, contains('_player.pause()'));
      // 旧适配器全文没有 _player.stop() —— 这正是它不崩的原因。
      expect(
        old,
        isNot(contains('_player.stop()')),
        reason: '旧适配器从不调 stop()，所以不会触发 mpv ctx 访问违例',
      );
    });
  });
}
