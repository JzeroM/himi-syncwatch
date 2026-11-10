import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 653：Windows 原生 UI 门控断链 → Flutter 播放页不退场。
///
/// 【真机回归】云调试截图：左侧 Flutter 窗口**同时**显示详情页与播放页
/// 顶栏/底栏（`末路兼职 – S01E03` + 进度条 + 控制按钮），右侧是原生
/// `HIMI Player` 窗口。
///
/// 【根因】门控链断在 `nativeUiPlatformName`：
/// ```dart
/// static String? get nativeUiPlatformName {
///   if (isOhos) return 'ohos';
///   if (Platform.isAndroid) return 'android';
///   return null;              // ← Windows 返回 null
/// }
/// ```
/// → `_openNativeUiIfNeeded()` 的 `if (platform == null) return;` 直接退出
/// → `nativeUiActive` **永不置 true**
/// → `PlayerScreen` 的 `SizedBox.shrink()` 守卫不生效
/// → 播放页 UI 照常渲染。
///
/// 注意：原生窗口本身**是正常创建的**（走 `nativeUi: true` 会话路径），
/// 所以「窗口建了 ≠ 门控通过」——这是本轮最容易误判的点。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const platformPath = 'lib/services/player/mpv_session_platform.dart';
  const adapterPath = 'lib/services/player/mpv_player_adapter.dart';
  const screenPath = 'lib/screens/player/player_screen.dart';

  group('① nativeUiPlatformName 覆盖 Windows', () {
    late String src;

    setUp(() => src = read(platformPath));

    test('Windows 分支返回 windows', () {
      final start = src.indexOf('static String? get nativeUiPlatformName');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 1600);
      expect(body, contains('Platform.isWindows'));
      expect(body, contains("return 'windows'"));
    });

    test('Android / 鸿蒙 仍返回各自标识', () {
      final start = src.indexOf('static String? get nativeUiPlatformName');
      final body = src.substring(start, start + 1600);
      expect(body, contains("return 'ohos'"));
      expect(body, contains("return 'android'"));
    });

    test('Windows 分支带根因注释（防将来被删）', () {
      final start = src.indexOf('static String? get nativeUiPlatformName');
      expect(start, greaterThan(-1));
      // 根因注释写在方法**之前**（文档注释块），往前取足够长的窗口。
      final doc = src.substring(
        (start - 2000).clamp(0, start),
        start,
      );
      expect(doc, contains('nativeUiActive'));
      expect(doc, contains('SizedBox.shrink'));
    });
  });

  group('② 门控链路：platform 非 null 才会置 nativeUiActive', () {
    late String adapter;

    setUp(() => adapter = read(adapterPath));

    test('_openNativeUiIfNeeded 仍有 platform == null 早退', () {
      final start = adapter.indexOf('Future<void> _openNativeUiIfNeeded(');
      expect(start, greaterThan(-1));
      final body = adapter.substring(start, start + 3200);
      expect(body, contains('if (platform == null) return;'));
    });

    test('nativeUiActive 置 true 在 platform 检查之后', () {
      final start = adapter.indexOf('Future<void> _openNativeUiIfNeeded(');
      final body = adapter.substring(start, start + 3200);
      final guardIdx = body.indexOf('if (platform == null) return;');
      final activeIdx = body.indexOf('nativeUiActive.value = true');
      expect(guardIdx, greaterThan(-1));
      expect(activeIdx, greaterThan(guardIdx),
          reason: '门控通过后才置 active');
    });

    test('_nativeUiEnabled 由会话实际 surface 决定（Windows 走 surface 时为 true）', () {
      expect(
        adapter,
        contains('_nativeUiEnabled = nativeUiRequested && player.usesNativeSurface'),
      );
    });
  });

  group('③ 播放页退场守卫', () {
    late String screen;

    setUp(() => screen = read(screenPath));

    test('Windows + 原生 UI 激活时返回 SizedBox.shrink', () {
      final idx = screen.indexOf(
          'if (_nativeUiActive && defaultTargetPlatform == TargetPlatform.windows)');
      expect(idx, greaterThan(-1));
      final block = screen.substring(idx, idx + 220);
      expect(block, contains('SizedBox.shrink'));
    });

    test('_nativeUiActive 依赖适配器的 nativeUiActive.value', () {
      final start = screen.indexOf('bool get _nativeUiActive');
      expect(start, greaterThan(-1));
      final body = screen.substring(start, start + 300);
      expect(body, contains('nativeUiActive.value'));
    });
  });

  group('④ 配套方法在 Windows 是空实现（窗口已由会话创建）', () {
    late String src;

    setUp(() => src = read(platformPath));

    test('openNativeUi 在 Windows 无分支（窗口由会话创建）', () {
      // 656：closeNativeUi 现在有 Windows 分支（关闭 Qt 播放器进程），
      // 但 openNativeUi 仍是空实现——646 的原生窗口在会话创建时就建好了，
      // Qt 播放器则由 MpvSessionPlatform.launchQtPlayer 单独拉起。
      final start = src.indexOf('static Future<void> openNativeUi()');
      expect(start, greaterThan(-1), reason: '找不到 openNativeUi');
      // 精确取到函数体结束（避免窗口过长把 closeNativeUi 的 isWindows 算进来）
      final end = src.indexOf('\n  }', start);
      final body = src.substring(start, end);
      expect(body, isNot(contains('isWindows')),
          reason: 'openNativeUi 在 Windows 应为空实现');
    });

    test('closeNativeUi 在 Windows 会关闭 Qt 播放器（656）', () {
      final start = src.indexOf('static Future<void> closeNativeUi()');
      expect(start, greaterThan(-1), reason: '找不到 closeNativeUi');
      final body = src.substring(start, start + 500);
      expect(body, contains('closeQtPlayer'));
    });

    test('pushNativeState / nativeUiCommandStream 对 Windows 返回空', () {
      final pushStart = src.indexOf('static Future<void> pushNativeState(');
      expect(pushStart, greaterThan(-1));
      final pushBody = src.substring(pushStart, pushStart + 500);
      expect(pushBody, contains('Future<void>.value()'));

      final cmdStart = src.indexOf('static Stream<Map<Object?, Object?>> nativeUiCommandStream()');
      expect(cmdStart, greaterThan(-1));
      final cmdBody = src.substring(
        cmdStart,
        (cmdStart + 400).clamp(0, src.length),
      );
      expect(cmdBody, contains('.empty()'));
    });
  });
}
