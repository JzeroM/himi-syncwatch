import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 640 里**仍然有效**的三项修复（655 删除自动回退时不得误伤）。
///
/// 640 是一个大杂烩提交，同时做了：
///   ① surface 失败自动回退（**655 已删除**，见 surface_fallback_640_test）
///   ② texture 时序死锁修复 ← 保留
///   ③ MPV 硬解默认生效 ← 保留
///   ④ 人数修复（观众 ID 统一 + 退出必发 leave）← 保留
///   ⑤ TV 引擎控件位置 ← 保留
///
/// 本文件锁定 ②~⑤，防止将来清理 640 遗留代码时把它们一起删掉。
void main() {
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final settings = File('lib/models/app_settings.dart').readAsStringSync();
  final playerSettings = File(
    'lib/screens/settings/player_settings_screen.dart',
  ).readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  String bodyOf(String src, String signature) {
    final idx = src.indexOf(signature);
    expect(idx, greaterThan(0), reason: '未找到 $signature');
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

  group('① texture 时序死锁修复（先开媒体再等纹理）', () {
    test('_ensurePlayer 不再 await 纹理', () {
      final body =
          stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, contains('_awaitTextureInBackground'));
      expect(
        body,
        isNot(contains('_textureId = await _waitForTextureId')),
        reason: '旧实现先等纹理再开媒体 → 时序死锁（加载好久后失败）',
      );
    });

    test('后台等待不抛异常（不判播放失败）', () {
      final body = stripComments(
          bodyOf(android, 'Future<void> _awaitTextureInBackground('));
      expect(body, contains('catch'));
      expect(body, isNot(contains('rethrow')));
    });
  });

  group('② MPV 硬解默认生效', () {
    test('设置默认解码模式为 hw', () {
      expect(settings, contains("this.decodeMode = 'hw',"));
    });

    test('videoDecoders setter 平台无关识别硬解器', () {
      final body =
          bodyOf(adapter, '  set videoDecoders(List<String> decoders) {');
      expect(body, contains('hwDecoderHints'));
      expect(body, contains("'mediacodec'"), reason: 'Android 硬解器');
      expect(body, contains("'d3d11'"), reason: 'Windows 硬解器');
      expect(body, contains("'ohcodec'"), reason: '鸿蒙硬解器');
      expect(body, contains("next = 'hw';"));
    });

    test("内部 'hw' 映射为 mpv 合法值（auto-safe）", () {
      final body = bodyOf(adapter,
          'String resolveWindowsHwdec(String mode, {required bool windows}) {');
      expect(body, contains("if (mode == 'hw')"));
      expect(body, contains('auto-safe'));
    });

    test('videoDecoders getter 不再恒返回 ohcodec', () {
      final idx = adapter.indexOf('List<String> get videoDecoders {');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 400);
      expect(body, contains('platformHwDecoderName'));
    });
  });

  group('③ 设置文案（640 更新，仍有效）', () {
    test('默认播放器文案不再写「Android/Windows 使用 MDK」', () {
      expect(
        stripComments(playerSettings),
        isNot(contains('Android/Windows 使用 MDK')),
      );
      expect(playerSettings, contains('Android / Windows / 鸿蒙使用 MPV'));
    });

    test('MPV 配置页不再写死 HarmonyOS / ohcodec', () {
      final body = stripComments(
        File('lib/screens/settings/engine_config_screen.dart')
            .readAsStringSync(),
      );
      expect(body, isNot(contains("Text('HarmonyOS MPV')")));
      expect(body, isNot(contains('ohcodec 硬件解码')));
      expect(body, contains("Text('MPV')"));
    });
  });

  group('④ 人数修复：观众端 ID 统一 + 退出必发 leave', () {
    test('观众端 _myUserId 统一为 rtmUserId（tokenId）', () {
      // 真机「观众端显示 3 人，实际 2 人」：_myUserId 是自造的
      // user_<timestamp>，而 RTM 用 tokenId → 集合里有两个「自己」。
      expect(screen, contains('_myUserId = rtmUserId;'));
    });

    test('dispose 开头捕获 RTM 引用（避免 ref 失效）', () {
      final body = stripComments(bodyOf(screen, 'void dispose() {'));
      final captureIdx =
          body.indexOf('rtmForLeave = ref.read(rtmServiceProvider)');
      final cleanupIdx = body.indexOf('final rtmLeave = rtmForLeave');
      expect(captureIdx, greaterThan(0), reason: '必须在开头捕获');
      expect(cleanupIdx, greaterThan(captureIdx));
      final cleanup = body.substring(cleanupIdx);
      expect(
        cleanup,
        isNot(contains('ref.read(rtmServiceProvider)')),
        reason: '组件销毁后 ref 可能失效 → leave 发不出去',
      );
    });

    test('leave 仍在 unsubscribe 之前且留 300ms', () {
      final body = stripComments(bodyOf(screen, 'void dispose() {'));
      final leaveIdx = body.indexOf("action: 'leave'");
      final unsubIdx = body.indexOf('unsubscribe(channelLeave)');
      expect(leaveIdx, greaterThan(0));
      expect(unsubIdx, greaterThan(leaveIdx));
      expect(body, contains('milliseconds: 300'));
    });
  });

  group('⑤ TV 引擎控件移到弹幕开关后', () {
    test('681：顶栏单引擎/ TV 模式均隐藏引擎按钮', () {
      expect(screen, contains('showKernelButton: !tvMode'));
      expect(screen, contains('isSingleEngine(tvMode: tvMode)'));
    });

    test('681：底栏引擎按钮仅多引擎 TV 显示', () {
      expect(screen, contains('isSingleEngine(tvMode: true)'));
      final idx = screen.indexOf('isSingleEngine(tvMode: true)');
      final body = screen.substring(idx, idx + 500);
      expect(body, contains('_kernelButtonFocusNode'));
      expect(body, contains('_toggleKernelMenu'));
    });
  });
}
