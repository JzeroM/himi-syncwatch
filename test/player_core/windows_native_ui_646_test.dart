import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_gating.dart';

/// 646：Windows 原生播放器（顶层窗口 + MPV HDR 直出）阶段 1。
///
/// 【背景】Windows 上 Flutter 用 DirectComposition 呈现到一个不透明顶层
/// 窗口，原生**子** HWND 不在其合成树里 → 只能被整体遮挡（真机实证：
/// MPV surface 灰屏）。Flutter 又不提供 Windows PlatformView
/// （platform_views.dart 无 windows 分支），无法像安卓/鸿蒙那样嵌入。
///
/// 唯一可行路径：自建 **WS_POPUP 顶层窗口** + MPV `vo=gpu-next` + `wid`
/// → 真 HDR 直出。本阶段只验证 HDR 画面能否显示，UI 后续用 Direct2D 叠加。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const cppPath =
      'plugins/himi_mpv_windows/windows/himi_mpv_windows_plugin.cpp';
  const hPath = 'plugins/himi_mpv_windows/windows/himi_mpv_windows_plugin.h';
  const dartPath = 'plugins/himi_mpv_windows/lib/himi_mpv_windows.dart';

  group('① C++ 顶层窗口（不被 Flutter 遮挡的关键）', () {
    late String cpp;

    setUp(() => cpp = read(cppPath));

    test('CreateHostWindow 使用 WS_POPUP（顶层窗口，非 WS_CHILD）', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 2200);
      expect(body, contains('WS_POPUP'));
      // 只看实际 CreateWindowEx 调用参数，不把注释里的对比说明算进去。
      final callStart = body.indexOf('::CreateWindowEx(');
      expect(callStart, greaterThan(-1));
      final call = body.substring(callStart, callStart + 400);
      expect(
        call,
        isNot(contains('WS_CHILD')),
        reason: '子窗口会被 Flutter 的 DirectComposition 不透明层遮挡（灰屏根因）',
      );
      // parent 必须为 nullptr（顶层）。
      expect(call, contains('nullptr, nullptr, ::GetModuleHandle(nullptr)'));
    });

    test('顶层窗口带 WS_EX_TOPMOST（盖在 Flutter 之上）', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateHostWindow');
      final body = cpp.substring(start, start + 2200);
      expect(body, contains('WS_EX_TOPMOST'));
      expect(body, contains('WS_EX_NOACTIVATE'), reason: '不抢焦点');
    });

    test('CreateRenderSurface 是 host 的子窗口', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateRenderSurface');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 1800);
      expect(body, contains('WS_CHILD'));
      expect(body, contains('host_hwnd_'), reason: '父窗口必须是 host');
    });

    test('UpdateHostWindow 同步位置/尺寸并带 SWP_NOACTIVATE', () {
      final start = cpp.indexOf('void HimiMpvWindowsPlugin::UpdateHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 900);
      expect(body, contains('SetWindowPos'));
      expect(body, contains('SWP_NOACTIVATE'));
      expect(body, contains('HWND_TOPMOST'));
    });

    test('DestroyHostWindow 先销毁 render 再销毁 host', () {
      final start = cpp.indexOf('void HimiMpvWindowsPlugin::DestroyHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 700);
      final renderIdx = body.indexOf('render_hwnd_');
      final hostIdx = body.indexOf('host_hwnd_');
      expect(renderIdx, greaterThan(-1));
      expect(hostIdx, greaterThan(renderIdx), reason: '先销毁渲染子窗口');
    });

    test('析构函数清理顶层窗口', () {
      final start = cpp.indexOf('HimiMpvWindowsPlugin::~HimiMpvWindowsPlugin()');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 200);
      expect(body, contains('DestroyHostWindow()'));
    });

    test('头文件声明了 646 的新方法与成员', () {
      final h = read(hPath);
      expect(h, contains('HWND CreateHostWindow('));
      expect(h, contains('HWND CreateRenderSurface()'));
      expect(h, contains('void UpdateHostWindow('));
      expect(h, contains('void DestroyHostWindow()'));
      expect(h, contains('HostWndProc'));
      expect(h, contains('host_hwnd_'));
      expect(h, contains('render_hwnd_'));
    });

    test('channel 暴露 646 的 5 个方法', () {
      for (final method in [
        'createHostWindow',
        'createRenderSurface',
        'updateHostWindow',
        'destroyHostWindow',
        'getHostWindowInfo',
      ]) {
        expect(cpp, contains('"$method"'), reason: '缺少 $method');
      }
    });
  });

  group('② Dart 会话支持 nativeUi', () {
    late String dart;

    setUp(() => dart = read(dartPath));

    test('create 接受 nativeUi 参数并强制 nativeSurface', () {
      final start = dart.indexOf('static Future<HimiMpvWindowsSession> create({');
      expect(start, greaterThan(-1));
      final body = dart.substring(start, start + 900);
      expect(body, contains('bool nativeUi = false'));
      expect(
        body,
        contains('nativeSurface: nativeUi ? true : nativeSurface'),
        reason: 'nativeUi 必须走原生 surface（顶层窗口渲染）',
      );
    });

    test('_start 在 nativeUi 下创建顶层窗口并用 render HWND 作 wid', () {
      final start = dart.indexOf('Future<void> _start() async {');
      expect(start, greaterThan(-1));
      final body = dart.substring(start, start + 1800);
      expect(body, contains("invokeMethod<int>('createHostWindow'"));
      expect(body, contains("invokeMethod<int>('createRenderSurface'"));
      expect(body, contains('_surfaceHandle = render'));
    });

    test('dispose 在 nativeUi 下销毁顶层窗口（而非 destroySurface）', () {
      final start = dart.indexOf('Future<void> dispose() async {');
      expect(start, greaterThan(-1));
      final body = dart.substring(
        start,
        (start + 2600).clamp(0, dart.length),
      );
      expect(body, contains("invokeMethod<void>('destroyHostWindow')"));
    });

    test('提供 updateHostGeometry 驱动窗口几何', () {
      expect(dart, contains('Future<void> updateHostGeometry('));
      expect(dart, contains("invokeMethod<void>('updateHostWindow'"));
      // 必须实现独立可选接口（不放主接口，否则 Android/鸿蒙被迫写空实现）。
      expect(dart, contains('implements MpvSession, MpvHostWindowSession'));
    });
  });

  group('③ HDR 直出配置', () {
    late String dart;

    setUp(() => dart = read(dartPath));

    test('原生 surface 选项含 vo=gpu-next 与 HDR 元数据透传', () {
      final start = dart.indexOf('Map<String, String> buildWindowsMpvOptions(');
      expect(start, greaterThan(-1));
      final body = dart.substring(start, start + 2000);
      expect(body, contains("'gpu-api': 'd3d11'"));
      expect(body, contains("'gpu-context': 'd3d11'"));
      expect(
        body,
        contains("'target-colorspace-hint': 'yes'"),
        reason: 'HDR 直出核心开关（仅 vo=gpu-next 支持）',
      );
      expect(body, contains("'hdr-compute-peak'"));
      expect(body, contains('rgb10_a2'), reason: 'HDR 需 10bit 输出格式');
    });

    test('纹理路径仍显式关闭 HDR 直出（target-colorspace-hint=no）', () {
      final start = dart.indexOf('Map<String, String> buildWindowsMpvTextureOptions(');
      expect(start, greaterThan(-1));
      final body = dart.substring(start, start + 1500);
      expect(body, contains("'target-colorspace-hint': 'no'"));
    });
  });

  group('④ 门控与会话工厂接线', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Windows 加入原生 UI 支持平台', () {
      expect(
        NativePlayerGating.isPlatformSupported('windows'),
        isTrue,
      );
      expect(NativePlayerGating.isPlatformSupported('android'), isTrue);
      expect(NativePlayerGating.isPlatformSupported('ohos'), isTrue);
      expect(NativePlayerGating.isPlatformSupported('ios'), isFalse);
    });

    test('shouldUseCurrent 在 Windows 上启用', () {
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platform: TargetPlatform.windows,
        ),
        isTrue,
      );
    });

    test('mpv_session_platform 把 nativeUi 传给 Windows 会话', () {
      final src = read('lib/services/player/mpv_session_platform.dart');
      final start = src.indexOf('if (Platform.isWindows) {');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 900);
      expect(body, contains('nativeUi: nativeUi'));
      expect(
        body,
        isNot(contains('参数透传但忽略')),
        reason: '旧注释「Windows 不支持原生播放器 UI」已过时',
      );
    });
  });

  group('⑤ 播放页退场（648：独立窗口，无需几何同步）', () {
    late String screen;

    setUp(() => screen = read('lib/screens/player/player_screen.dart'));

    test('原生 UI 接管时视频区挂 key 并退场', () {
      final start = screen.indexOf('Widget _buildVideoArea()');
      expect(start, greaterThan(-1));
      final body = screen.substring(start, start + 2600);
      expect(body, contains('SizedBox.expand(key: _videoAreaKey)'));
    });

    test('648 起移除几何同步（独立窗口不跟随 Flutter 布局）', () {
      // 646 曾用 _syncNativeHostGeometry 把视频区几何传给覆盖式窗口，
      // 但坐标基准错误导致窗口飘在左上角。648 改为独立标准窗口后不再需要。
      expect(
        screen,
        isNot(contains('_syncNativeHostGeometry')),
        reason: '独立窗口由用户自由摆放，无需跟随 Flutter 布局',
      );
    });

    test('改为订阅原生窗口事件（关闭/按键/点击）', () {
      expect(screen, contains('void _attachHostWindowEvents()'));
      expect(screen, contains('_hostEventSub'));
    });
  });
}
