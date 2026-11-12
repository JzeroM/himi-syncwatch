import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 655：删除 640 的 surface→texture **自动回退**，视频路径改为纯手动设置。
///
/// ## 为什么删掉自动回退
///
/// 640 加了两条「检测到渲染失败就自动切纹理」的规则，本意是修 Mali-450
/// 盒子（H96 Max RK3528）上 `vo=gpu-next` + `gpu-context=android` 的 EGL
/// 初始化失败（有声音无画面）。但实现有两个致命缺陷：
///
/// ### 缺陷 1：判据太宽，正常设备会误判
///
/// ```dart
/// final failed = (t.contains('egl') && (...)) ||
///     t.contains('could not create') ||     // ← 没有前缀限定
///     t.contains('failed to create') ||     // ← 没有前缀限定
///     ...
/// ```
///
/// `could not create` / `failed to create` 是通用短语，mpv 的 info 级日志
/// 里音频设备、字幕字体、某个解码 profile 都会打。只要命中一行就判定
/// 「surface 渲染失败」。
///
/// 另一条 `vo-configured` 连续 5s 非 `yes` 同样会误伤：网络转码起播慢、
/// 4K HEVC 硬解初始化慢、片头黑场都满足条件。
///
/// ### 缺陷 2：误判被持久化后**无法自愈**
///
/// 640 的提交说明写「持久化 mpvVideoOutput=texture（**userSet 保持
/// false**）」，但实际实现是：
///
/// ```dart
/// // settings_provider.dart
/// mpvVideoOutput: mpvVideoOutput,
/// mpvVideoOutputUserSet: mpvVideoOutput != null ? true : null,  // ← 恒置 true
/// ```
///
/// `update()` 无法区分「用户手动改」与「程序自动改」，一律置
/// `userSet = true`。而 `userSet == true` 是最高优先级：
///
/// ```dart
/// static String effectiveVideoOutput({...}) {
///   if (windows && !userSet) return texture;
///   return normalizeVideoOutput(configured);   // userSet 时直接用 configured
/// }
/// ```
///
/// → **一次误判 = 该设备永久锁定纹理，重启也不恢复**。
///
/// 用户真机现象：「以前手机播是好的，现在自动回退到纹理」。
///
/// ## 现在的行为
///
/// 视频路径只由设置页决定（`mpvVideoOutput` + `userSet`）。渲染失败不再
/// 自动改写设置，只在日志里留诊断信息。用户可随时在
/// 「设置 → 播放内核 → MPV 视频输出」手动切换。
void main() {
  final android = File(
    'plugins/himi_mpv_android/lib/himi_mpv_android.dart',
  ).readAsStringSync();
  final adapter = File(
    'lib/services/player/mpv_player_adapter.dart',
  ).readAsStringSync();
  final screen =
      File('lib/screens/player/player_screen.dart').readAsStringSync();
  final engineConfig = File(
    'lib/screens/settings/engine_config_screen.dart',
  ).readAsStringSync();

  /// 去掉行注释，避免注释里提到旧名字造成误判。
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

  group('① 自动回退逻辑已彻底删除', () {
    late String code;

    setUpAll(() => code = stripComments(android));

    test('不再有 _forceTexture 字段', () {
      expect(code, isNot(contains('_forceTexture')));
    });

    test('不再有 _textureFallbackTried 防重入标记', () {
      expect(code, isNot(contains('_textureFallbackTried')));
    });

    test('不再有 _voNotConfiguredTicks 计数', () {
      expect(code, isNot(contains('_voNotConfiguredTicks')));
    });

    test('三个回退方法全部不存在', () {
      expect(code, isNot(contains('_maybeFallbackOnLog')));
      expect(code, isNot(contains('_startVoConfiguredWatch')));
      expect(code, isNot(contains('_fallbackToTexture')));
    });

    test('不再有 onSurfaceRenderFailed 回调字段', () {
      expect(code, isNot(contains('onSurfaceRenderFailed')));
    });

    test('日志订阅只记日志，不再触发回退', () {
      final body = stripComments(bodyOf(android, 'void _wire(Player player) {'));
      expect(body, contains('_log('), reason: '日志仍要落盘（诊断需要）');
      expect(body, isNot(contains('_maybeFallbackOnLog')));
      expect(body, isNot(contains('_fallbackToTexture')));
    });

    test('媒体打开后不再启动 vo-configured 监控', () {
      final body =
          stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, isNot(contains('_startVoConfiguredWatch')));
    });
  });

  group('② effectiveSurface 只由设置决定', () {
    test('effectiveSurface 直接等于 nativeSurface', () {
      final body =
          stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(
        body,
        contains('final effectiveSurface = nativeSurface;'),
        reason: '不应再叠加任何运行时回退标志',
      );
      expect(body, isNot(contains('!_forceTexture')));
    });

    test('创建播放器日志不再打印 forceTexture', () {
      final body =
          stripComments(bodyOf(android, 'Future<void> _ensurePlayer() async {'));
      expect(body, isNot(contains('forceTexture')));
    });
  });

  group('③ Dart 层不再持久化输出路径', () {
    test('adapter 不再有 onSurfaceRenderFailed 字段', () {
      final code = stripComments(adapter);
      expect(code, isNot(contains('onSurfaceRenderFailed')));
    });

    test('播放页不再有 _onSurfaceRenderFailed', () {
      final code = stripComments(screen);
      expect(code, isNot(contains('_onSurfaceRenderFailed')));
    });

    test('播放页不再自动写 mpvVideoOutput', () {
      final code = stripComments(screen);
      expect(
        code,
        isNot(contains('mpvVideoOutput: MpvOutputPolicy.texture')),
        reason: '这是 640 的自动回退落点，必须删除',
      );
    });

    test('_attachNativeUiBridge 只接原生 UI 三个回调', () {
      final body =
          stripComments(bodyOf(screen, 'void _attachNativeUiBridge(PlayerAdapter player) {'));
      expect(body, contains('nativeUiActive.addListener'));
      expect(body, contains('onNativeUiExit'));
      expect(body, contains('onNativeUiCommand'));
      expect(body, isNot(contains('onSurfaceRenderFailed')));
    });
  });

  group('④ 设置文案改为手动指引', () {
    test('不再宣传「渲染失败自动回退纹理」', () {
      expect(
        stripComments(engineConfig),
        isNot(contains('渲染失败自动回退纹理')),
      );
    });

    test('Android 文案给出手动切换指引', () {
      expect(engineConfig, contains('有声音无画面'));
      expect(engineConfig, contains('手动切到'));
    });

    test('685：Windows 已移除「视频路径」项（不再有会崩的入口）', () {
      // 640 时这里断言设置页有「Windows 默认 Surface」文案（提醒别切纹理）；
      // 685 起整项从 Windows 移除——文案与下拉框一起消失，运行时由
      // `effectiveMpvVideoOutput` 恒返回 surface 兜底。
      expect(engineConfig, isNot(contains('Windows 默认 Surface')));
      expect(engineConfig, isNot(contains('纹理路径在 Windows 会闪退')));
      // Android/鸿蒙仍保留该项
      expect(engineConfig, contains("title: '视频路径'"));
    });
  });

  group('⑤ 保留的诊断能力不受影响', () {
    test('mpv 日志仍逐行落盘（黑屏定性依赖它）', () {
      final body = stripComments(bodyOf(android, 'void _wire(Player player) {'));
      expect(body, contains("_log('mpv["));
    });

    test('Android 会话仍把 debugLog 接到 LogService', () {
      expect(
        stripComments(adapter),
        contains('HimiMpvAndroidSession.debugLog'),
      );
    });
  });
}
