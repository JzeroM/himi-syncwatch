import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 648：Windows 独立原生播放器窗口（标准窗口，像普通播放器）。
///
/// 【演进】
/// - 646：`WS_POPUP` + `WS_EX_TOPMOST` 覆盖 Flutter 窗口 → 视频能出，但
///   窗口飘在左上角、Flutter 控件被遮（真机截图）。
/// - 648：改为**独立标准窗口**（`WS_OVERLAPPEDWINDOW`），用户可自由
///   拖动/缩放/最大化/全屏；Flutter 播放页整页退场，退出由本窗口的
///   关闭按钮 / ESC 驱动。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const cppPath =
      'plugins/himi_mpv_windows/windows/himi_mpv_windows_plugin.cpp';
  const hPath = 'plugins/himi_mpv_windows/windows/himi_mpv_windows_plugin.h';
  const dartPath = 'plugins/himi_mpv_windows/lib/himi_mpv_windows.dart';

  group('① C++ 独立标准窗口', () {
    late String cpp;

    setUp(() => cpp = read(cppPath));

    test('用 WS_OVERLAPPEDWINDOW（非 WS_POPUP）', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 2600);
      final callStart = body.indexOf('::CreateWindowEx(');
      expect(callStart, greaterThan(-1));
      final call = body.substring(callStart, callStart + 500);
      expect(call, contains('WS_OVERLAPPEDWINDOW'));
      expect(
        call,
        isNot(contains('WS_POPUP')),
        reason: 'WS_POPUP 无标题栏/边框，用户无法关闭或缩放',
      );
    });

    test('去掉 WS_EX_TOPMOST / NOACTIVATE / TOOLWINDOW', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateHostWindow');
      final body = cpp.substring(start, start + 2600);
      final callStart = body.indexOf('::CreateWindowEx(');
      final call = body.substring(callStart, callStart + 500);
      // 独立窗口：普通 Z 序、可获焦点、任务栏可见。
      expect(call, isNot(contains('WS_EX_TOPMOST')));
      expect(call, isNot(contains('WS_EX_NOACTIVATE')));
      expect(call, isNot(contains('WS_EX_TOOLWINDOW')));
    });

    test('WM_SIZE 让渲染子窗口与 UI 层跟随客户区', () {
      final start = cpp.indexOf('LRESULT CALLBACK HimiMpvWindowsPlugin::HostWndProc');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 2600);
      expect(body, contains('case WM_SIZE:'));
      expect(body, contains('GetClientRect'));
      expect(body, contains('render_hwnd_'));
      expect(body, contains('ui_hwnd_'));
    });

    test('WM_CLOSE 通知 Dart 但仍放行关闭（防关不掉）', () {
      final start = cpp.indexOf('LRESULT CALLBACK HimiMpvWindowsPlugin::HostWndProc');
      final body = cpp.substring(start, start + 2600);
      final closeIdx = body.indexOf('case WM_CLOSE:');
      expect(closeIdx, greaterThan(-1));
      final block = body.substring(closeIdx, closeIdx + 500);
      expect(block, contains('window-close'));
      expect(
        block,
        contains('DefWindowProc'),
        reason: 'Dart 未响应时用户仍需能关闭窗口',
      );
    });

    test('按键转发（ESC/空格/左右/F11）', () {
      final start = cpp.indexOf('LRESULT CALLBACK HimiMpvWindowsPlugin::HostWndProc');
      final body = cpp.substring(start, start + 2600);
      for (final key in [
        'VK_ESCAPE',
        'VK_SPACE',
        'VK_LEFT',
        'VK_RIGHT',
        'VK_F11',
      ]) {
        expect(body, contains(key), reason: '缺少 $key 转发');
      }
      expect(body, contains('window-close'));
      expect(body, contains('toggle-play'));
      expect(body, contains('seek-backward'));
      expect(body, contains('seek-forward'));
      expect(body, contains('toggle-fullscreen'));
    });

    test('点击画面转发 tap（切换控件显隐）', () {
      final start = cpp.indexOf('LRESULT CALLBACK HimiMpvWindowsPlugin::HostWndProc');
      final body = cpp.substring(start, start + 2600);
      expect(body, contains('WM_LBUTTONDOWN'));
      expect(body, contains('"tap"'));
    });

    test('UI 叠加层：透明 + 铺满 + 在渲染层之上', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateUiOverlay()');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 1600);
      expect(body, contains('WS_EX_LAYERED'));
      expect(body, contains('SetLayeredWindowAttributes'));
      expect(body, contains('WS_CHILD'));
    });

    test('createRenderSurface 之后创建 UI 层（保证 Z 序在上）', () {
      final start = cpp.indexOf('if (method == "createRenderSurface")');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 500);
      expect(body, contains('CreateUiOverlay()'));
    });

    test('DestroyHostWindow 先销毁 UI 层再渲染层再主窗口', () {
      final start = cpp.indexOf('void HimiMpvWindowsPlugin::DestroyHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 900);
      final uiIdx = body.indexOf('ui_hwnd_');
      final renderIdx = body.indexOf('render_hwnd_');
      final hostIdx = body.indexOf('host_hwnd_');
      expect(uiIdx, greaterThan(-1));
      expect(renderIdx, greaterThan(uiIdx), reason: '先销毁 UI 叠加层');
      expect(hostIdx, greaterThan(renderIdx), reason: '最后销毁主窗口');
    });

    test('UpdateHostWindow 不再用 HWND_TOPMOST（独立窗口普通 Z 序）', () {
      final start = cpp.indexOf('void HimiMpvWindowsPlugin::UpdateHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 1200);
      // 只看实际 SetWindowPos 调用参数，不把注释里的对比说明算进去。
      final callIdx = body.indexOf('::SetWindowPos(host_hwnd_');
      expect(callIdx, greaterThan(-1));
      final call = body.substring(callIdx, callIdx + 160);
      expect(call, isNot(contains('HWND_TOPMOST')));
    });

    test('头文件声明 UI 层与事件转发', () {
      final h = read(hPath);
      expect(h, contains('HWND CreateUiOverlay()'));
      expect(h, contains('void EmitHostEvent(const char* type)'));
      expect(h, contains('ui_hwnd_'));
    });
  });

  group('② Dart 侧事件流', () {
    late String dart;

    setUp(() => dart = read(dartPath));

    test('会话提供 hostEvents 流', () {
      expect(dart, contains('Stream<Map<Object?, Object?>> get hostEvents'));
      expect(dart, contains('_hostEvents'));
    });

    test('nativeUi 下订阅原生事件并转发到 hostEvents', () {
      final start = dart.indexOf('if (nativeUi) {');
      expect(start, greaterThan(-1));
      final body = dart.substring(start, start + 1600);
      expect(body, contains('_hostEvents.add'));
    });

    test('dispose 关闭 hostEvents', () {
      final start = dart.indexOf('Future<void> dispose() async {');
      expect(start, greaterThan(-1));
      final body = dart.substring(start);
      expect(body, contains('_hostEvents.close()'));
    });
  });

  group('③ 接口与适配器', () {
    test('MpvHostWindowSession 声明 hostEvents', () {
      final src = read('plugins/himi_mpv_core/lib/src/mpv_session.dart');
      final start = src.indexOf('abstract interface class MpvHostWindowSession');
      expect(start, greaterThan(-1));
      final body = src.substring(start);
      expect(body, contains('hostEvents'));
    });

    test('适配器暴露 hostEvents 并做类型判断', () {
      final src = read('lib/services/player/mpv_player_adapter.dart');
      expect(src, contains('Stream<Map<Object?, Object?>> get hostEvents'));
      expect(src, contains('MpvHostWindowSession'));
    });
  });

  group('④ 播放页订阅与退场', () {
    late String screen;

    setUp(() => screen = read('lib/screens/player/player_screen.dart'));

    test('订阅原生窗口事件', () {
      expect(screen, contains('void _attachHostWindowEvents()'));
      expect(screen, contains('_hostEventSub'));
    });

    test('事件映射：关闭/播放/seek/全屏/点击', () {
      final start = screen.indexOf('void _attachHostWindowEvents()');
      expect(start, greaterThan(-1));
      final body = screen.substring(start, start + 1800);
      expect(body, contains("'window-close'"));
      expect(body, contains("'toggle-play'"));
      expect(body, contains("'seek-backward'"));
      expect(body, contains("'seek-forward'"));
      expect(body, contains("'toggle-fullscreen'"));
      expect(body, contains("'tap'"));
    });

    test('window-close 走安全退出（离房确认）', () {
      final start = screen.indexOf('void _attachHostWindowEvents()');
      final body = screen.substring(start, start + 1800);
      final idx = body.indexOf("'window-close'");
      expect(idx, greaterThan(-1));
      final block = body.substring(idx, idx + 200);
      expect(block, contains('_safePopPlayerPage'));
    });

    test('dispose 取消订阅', () {
      final start = screen.indexOf('void dispose() {');
      expect(start, greaterThan(-1));
      // dispose 方法较长，截到下一个顶层方法定义前。
      final next = screen.indexOf('\n  Future<void> _disposePlayerAfterDelay', start);
      final body = screen.substring(
        start,
        next > start ? next : screen.length,
      );
      expect(body, contains('_hostEventSub?.cancel()'));
    });

    test('不再依赖几何同步（独立窗口）', () {
      expect(
        screen,
        isNot(contains('_syncNativeHostGeometry')),
        reason: '648 起窗口独立，无需跟随 Flutter 布局',
      );
    });
  });
}
