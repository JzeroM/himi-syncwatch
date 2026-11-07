import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 618：MPV 切轨（音轨/字幕）加速，观感接近 MDK。
///
/// MDK 的 `setActiveTracks` 是**同步 FFI、无锁**；MPV 却是
/// `mpv_set_property_async` + `await` + 全局 `Lock` + 叠加重建。
/// 三项优化叠加即可对齐：
/// ① `async: false`（同步 FFI）
/// ② `synchronized: false`（绕过全局锁）
/// ③ 抑制切轨窗口内的叠加重建
void main() {
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final windows = File(
    'plugins/himi_mpv_windows/lib/himi_mpv_windows.dart',
  ).readAsStringSync();
  final screen = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final mdk = File('lib/services/player/mdk_player_adapter.dart').readAsStringSync();

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
    // 从签名**末尾之后**开始配平——否则签名里参数位置的 `{`
    //（如 `({bool immediate = false}) {`）会被误当作函数体起点。
    var depth = 0;
    var started = false;
    for (var i = idx + signature.length - 1; i < src.length; i++) {
      final ch = src[i];
      if (ch == '{') {
        depth++;
        started = true;
      } else if (ch == '}') {
        depth--;
        if (started && depth == 0) return src.substring(idx, i + 1);
      }
    }
    fail('$signature 的大括号未配平');
  }

  group('① async: false（同步 FFI，对齐 MDK setActiveTracks）', () {
    for (final (name, src) in [('安卓', android), ('Windows', windows)]) {
      test('$name：PlayerConfiguration 传 async: false', () {
        expect(src, contains('async: false,'));
        // 注释记录理由（MDK 同语义 + media_kit 默认 true 是为 macOS）。
        expect(src, contains('618'));
      });
    }

    test('MDK 侧确实是同步 FFI（对照基准）', () {
      final fvp = File('third_party/fvp/lib/src/player.dart').readAsStringSync();
      final body = bodyOf(fvp, 'void setActiveTracks(MediaType type, List<int> value) {');
      // 同步 void 方法，不 await、不返回 Future。
      expect(body, contains('setActiveTracks'));
      expect(body, isNot(contains('await')));
    });
  });

  group('② synchronized: false（绕过 media_kit 全局锁）', () {
    for (final (name, src) in [('安卓', android), ('Windows', windows)]) {
      test('$name：_selectTrackNoLock 直调 platform', () {
        expect(src, contains('Future<void> _selectTrackNoLock('));
        expect(src, contains('_player?.platform as dynamic'));
      });

      test('$name：选轨传 synchronized: false', () {
        final audio = bodyOf(src, 'Future<void> setAudioTrack(int id) async {');
        expect(audio, contains('synchronized: false'));
        final sub =
            bodyOf(src, 'Future<void> setSubtitleTrack(int id) async {');
        expect(sub, contains('synchronized: false'));
      });

      test('$name：不再直接调 _player.setAudioTrack（走锁）', () {
        final audio = bodyOf(src, 'Future<void> setAudioTrack(int id) async {');
        expect(audio, isNot(contains('_player?.setAudioTrack(')));
        final sub =
            bodyOf(src, 'Future<void> setSubtitleTrack(int id) async {');
        expect(sub, isNot(contains('_player?.setSubtitleTrack(')));
      });

      test('$name：无重复 @override', () {
        // 正则更简洁（避免手写多行字符串的括号/转义问题）。
        expect(
          RegExp(r'@override\s*@override').hasMatch(src),
          isFalse,
          reason: '617 改动误留了重复的 @override',
        );
      });
    }
  });

  group('③ 切轨窗口抑制叠加重建', () {
    test('存在 _trackSwitchInFlight 标志与定时器', () {
      expect(screen, contains('bool _trackSwitchInFlight = false;'));
      expect(screen, contains('Timer? _trackSwitchTimer;'));
    });

    test('_applySubtitleStyle 在窗口内直接跳过', () {
      final body = bodyOf(screen, 'void _applySubtitleStyle() {');
      expect(body, contains('if (_trackSwitchInFlight) return;'));
    });

    test('_enterTrackSwitchWindow 300ms 后复位并补写样式', () {
      final body = bodyOf(screen, 'void _enterTrackSwitchWindow() {');
      expect(body, contains('_trackSwitchInFlight = true;'));
      expect(body, contains('Duration(milliseconds: 300)'));
      expect(body, contains('_trackSwitchInFlight = false;'));
      // 窗口结束后补写（切轨期间被跳过的值在这里落地）。
      expect(body, contains('_applySubtitleStyle()'));
    });

    test('字幕切轨接入窗口', () {
      final body = bodyOf(screen, 'Future<void> _selectEmbySubtitle(int embyIndex) async {');
      expect(body, contains('_enterTrackSwitchWindow()'));
    });

    test('音轨切轨接入窗口', () {
      final body = bodyOf(screen, 'void _selectEmbyAudio(int embyIndex) {');
      expect(body, contains('_enterTrackSwitchWindow()'));
    });

    test('延迟重载避开切轨窗口（不叠 sub-add）', () {
      // 注意：用完整签名（含 `{`），否则会命中调用点而非定义处。
      final body = bodyOf(
        screen,
        'void _maybeApplySubtitleDelay({bool immediate = false}) {',
      );
      expect(body, contains('if (_trackSwitchInFlight)'));
      // 窗口内改为延后重试，而不是立即 _reloadSubtitleForDelay。
      expect(body, contains('_maybeApplySubtitleDelay(immediate: true)'));
    });
  });

  group('④ 对照：音轨早已有同构保护（本轮补齐字幕侧）', () {
    test('_audioFilterDeferTimer 存在（300ms 延后先例）', () {
      expect(screen, contains('Timer? _audioFilterDeferTimer;'));
      expect(screen, contains('Duration(milliseconds: 300)'));
    });

    test('注释记录了「两次重建叠加 = 卡顿」的根因', () {
      expect(screen, contains('两次重建'));
      expect(screen, contains('叠加'));
    });
  });

  group('⑤ MDK 选轨是同步 setter（对照基准）', () {
    test('MDK adapter 直接赋值，不 await', () {
      final body = bodyOf(mdk, 'set activeAudioTracks(List<int> tracks) {');
      expect(body, contains('_player.activeAudioTracks = tracks;'));
      expect(body, isNot(contains('await')));
    });
  });
}
