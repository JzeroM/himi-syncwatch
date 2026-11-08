import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 640：surface 渲染失败自动回退 + texture 时序死锁 + 硬解默认 + 文案。
///
/// 1. **Mali-450 盒子 surface 黑屏**（有声音无画面）——`vo=gpu-next` +
///    `gpu-context=android` 的 EGL 初始化失败。而 MDK 能播是因为它走
///    `tunnel`（MediaCodec 直写 SurfaceView，**完全绕过 GL/EGL**）。
///    修复：检测失败（mpv 日志关键字 1-2s + `vo-configured` 5s 兜底）
///    后自动回退 texture，并持久化该设备的选择。
/// 2. **加载好久后失败、重试才正常**（手机与 TV 都复现）——
///    `_ensurePlayer` 在**打开媒体之前**就 `await _waitForTextureId`
///    （最长 20s），而纹理注册依赖媒体已打开 → 时序死锁。
/// 3. **MPV 硬解默认不生效**——`videoDecoders` setter 只认 `ohcodec`
///    （鸿蒙），Android 的 `AMediaCodec` / Windows 的 `D3D11` 全被判为
///    无硬解 → `decodeMode='hw'` 静默退化成 `auto`。
/// 4. **设置文案过时**——写死「HarmonyOS MPV」「Android/Windows 使用 MDK」。
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
  final engineConfig = File(
    'lib/screens/settings/engine_config_screen.dart',
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

  group('① surface 渲染失败自动回退 texture', () {
    test('新增 _forceTexture / _textureFallbackTried', () {
      expect(android, contains('bool _forceTexture = false;'));
      expect(android, contains('bool _textureFallbackTried = false;'));
    });

    test('effectiveSurface 叠加 _forceTexture', () {
      expect(
        android,
        contains('final effectiveSurface = nativeSurface && !_forceTexture;'),
      );
    });

    test('mpv 日志关键字触发回退（最快信号）', () {
      expect(android, contains('_maybeFallbackOnLog'));
      final body = bodyOf(android, 'void _maybeFallbackOnLog(String text) {');
      expect(body, contains("t.contains('egl')"));
      expect(body, contains('could not create'));
      expect(body, contains('_fallbackToTexture()'));
    });

    test('vo-configured 兜底（5s = 500ms × 10）', () {
      expect(android, contains('_startVoConfiguredWatch'));
      final body = bodyOf(android, 'void _startVoConfiguredWatch() {');
      expect(body, contains('_voNotConfiguredTicks >= 10'));
      expect(body, contains("getProperty('vo-configured')"));
      expect(body, contains('milliseconds: 500'));
    });

    test('媒体打开后启动 vo-configured 监控', () {
      final body = stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      final openIdx = body.indexOf('_openNow(pending)');
      final watchIdx = body.indexOf('_startVoConfiguredWatch()');
      expect(openIdx, greaterThan(0));
      expect(watchIdx, greaterThan(openIdx), reason: '必须先开媒体再监控');
    });

    test('回退后通知 Dart 层持久化', () {
      expect(android, contains('onSurfaceRenderFailed'));
      expect(adapter, contains('onSurfaceRenderFailed'));
      expect(screen, contains('_onSurfaceRenderFailed'));
      expect(screen, contains('mpvVideoOutput: MpvOutputPolicy.texture'));
    });
  });

  group('② texture 时序死锁修复（先开媒体再等纹理）', () {
    test('_ensurePlayer 不再 await 纹理', () {
      final body = stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, contains('_awaitTextureInBackground'));
      expect(
        body,
        isNot(contains('_textureId = await _waitForTextureId')),
        reason: '旧实现先等纹理再开媒体 → 时序死锁（加载好久后失败）',
      );
    });

    test('后台等待不抛异常（不判播放失败）', () {
      final body =
          stripComments(bodyOf(android, 'Future<void> _awaitTextureInBackground('));
      expect(body, contains('catch'));
      expect(body, isNot(contains('rethrow')));
    });
  });

  group('③ MPV 硬解默认生效', () {
    test('设置默认解码模式为 hw', () {
      expect(settings, contains("this.decodeMode = 'hw',"));
    });

    test('videoDecoders setter 平台无关识别硬解器', () {
      final body = bodyOf(adapter, '  set videoDecoders(List<String> decoders) {');
      expect(body, contains('hwDecoderHints'));
      expect(body, contains("'mediacodec'"), reason: 'Android 硬解器');
      expect(body, contains("'d3d11'"), reason: 'Windows 硬解器');
      expect(body, contains("'ohcodec'"), reason: '鸿蒙硬解器');
      expect(body, contains("next = 'hw';"));
    });

    test("内部 'hw' 映射为 mpv 合法值（auto-safe）", () {
      final body = bodyOf(adapter, 'String resolveWindowsHwdec(String mode, {required bool windows}) {');
      expect(body, contains("if (mode == 'hw')"));
      expect(body, contains('auto-safe'));
      expect(
        body,
        isNot(contains("if (mode == 'no') return mode;")),
        reason: 'hw 必须在 windows 分支之前处理',
      );
    });

    test('videoDecoders getter 不再恒返回 ohcodec', () {
      final idx = adapter.indexOf('List<String> get videoDecoders {');
      expect(idx, greaterThan(0));
      final body = adapter.substring(idx, idx + 400);
      expect(body, contains('platformHwDecoderName'));
    });
  });

  group('④ 设置文案更新', () {
    test('默认播放器文案不再写「Android/Windows 使用 MDK」', () {
      expect(
        stripComments(playerSettings),
        isNot(contains('Android/Windows 使用 MDK')),
      );
      // 641：Windows 改为 media_kit（MPV 在 Windows 上 texture 返回崩溃、
      // surface 灰屏），文案同步。
      expect(
        playerSettings,
        contains('Android / 鸿蒙使用 MPV，Windows 使用 media_kit'),
      );
    });

    test('MPV 配置页不再写死 HarmonyOS / ohcodec', () {
      final body = stripComments(engineConfig);
      expect(body, isNot(contains("Text('HarmonyOS MPV')")));
      expect(body, isNot(contains('ohcodec 硬件解码')));
      expect(body, contains("Text('MPV')"));
    });

    test('视频路径文案反映当前行为', () {
      expect(engineConfig, contains('Windows 默认纹理'));
      expect(engineConfig, contains('渲染失败自动回退纹理'));
    });
  });

  group('⑤ 人数修复：观众端 ID 统一 + 退出必发 leave', () {
    test('观众端 _myUserId 统一为 rtmUserId（tokenId）', () {
      // 真机「观众端显示 3 人，实际 2 人」：_myUserId 是自造的
      // user_<timestamp>，而 RTM 用 tokenId → 集合里有两个「自己」。
      expect(screen, contains('_myUserId = rtmUserId;'));
    });

    test('dispose 开头捕获 RTM 引用（避免 ref 失效）', () {
      final body = stripComments(bodyOf(screen, 'void dispose() {'));
      final captureIdx = body.indexOf('rtmForLeave = ref.read(rtmServiceProvider)');
      final cleanupIdx = body.indexOf('final rtmLeave = rtmForLeave');
      expect(captureIdx, greaterThan(0), reason: '必须在开头捕获');
      expect(cleanupIdx, greaterThan(captureIdx));
      // 清理段不得再读 ref。
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

  group('⑥ TV 引擎控件移到弹幕开关后', () {
    test('顶栏 TV 模式隐藏引擎按钮', () {
      expect(screen, contains('showKernelButton: !settings.tvMode && !_switchingKernel'));
    });

    test('底栏弹幕开关后插入引擎按钮', () {
      expect(screen, contains('if (tvMode && !_switchingKernel)'));
      final idx = screen.indexOf('if (tvMode && !_switchingKernel)');
      final body = screen.substring(idx, idx + 400);
      expect(body, contains('_kernelButtonFocusNode'));
      expect(body, contains('_toggleKernelMenu'));
    });
  });
}
