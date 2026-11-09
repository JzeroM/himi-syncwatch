import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 649：两个窗口共存（Flutter 详情页 + 原生播放器窗口）。
///
/// 【真机问题】648 截图显示两个窗口：`HIMI PROBE: layered-alpha`（Flutter
/// 主窗口，标题被改）和 `HIMI Player`（原生播放器）。
///
/// 根因：639 遗留的**透明探测调试代码**在「原生 surface + HDR 播放」时
/// 自动运行，依次尝试 dwm-blur / layered-alpha / region-hole 三种方案
/// （每种 8 秒），期间把 Flutter 窗口设成 WS_EX_LAYERED 全透明并改标题
/// 为 `HIMI PROBE: <mode>`。
///
/// 648 改用独立窗口后，这套探测已完全无用且有害 → 本轮删除，
/// 并让 Flutter 播放页不可见、详情页透出，实现「两个正常窗口共存」。
void main() {
  String read(String p) => File(p).readAsStringSync();

  const dartPlugin = 'plugins/himi_mpv_windows/lib/himi_mpv_windows.dart';
  const cppPlugin =
      'plugins/himi_mpv_windows/windows/himi_mpv_windows_plugin.cpp';
  const hPlugin = 'plugins/himi_mpv_windows/windows/himi_mpv_windows_plugin.h';

  group('① 删除透明探测代码（HIMI PROBE 根因）', () {
    test('Dart 侧无 _runTransparencyProbe / _transparencyProbeStarted', () {
      final src = read(dartPlugin);
      expect(src, isNot(contains('_runTransparencyProbe')));
      expect(src, isNot(contains('_transparencyProbeStarted')));
      expect(src, isNot(contains('setTransparencyProbe')));
    });

    test('C++ 侧无 SetTransparencyProbe / HIMI PROBE', () {
      final src = read(cppPlugin);
      expect(src, isNot(contains('SetTransparencyProbe')));
      expect(src, isNot(contains('CaptureTransparencyState')));
      expect(src, isNot(contains('ClearTransparencyProbe')));
      expect(
        src,
        isNot(contains('HIMI PROBE')),
        reason: '这段逻辑会把 Flutter 窗口标题改成 HIMI PROBE: <mode>',
      );
    });

    test('头文件无探测相关声明与字段', () {
      final h = read(hPlugin);
      expect(h, isNot(contains('SetTransparencyProbe')));
      expect(h, isNot(contains('CaptureTransparencyState')));
      expect(h, isNot(contains('ClearTransparencyProbe')));
      expect(h, isNot(contains('original_window_title_')));
      expect(h, isNot(contains('transparency_state_captured_')));
    });
  });

  group('② 聚焦已有窗口（不重复创建）', () {
    late String cpp;

    setUp(() => cpp = read(cppPlugin));

    test('CreateHostWindow 已存在时 SetForegroundWindow', () {
      final start = cpp.indexOf('HWND HimiMpvWindowsPlugin::CreateHostWindow');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 1200);
      final guardIdx = body.indexOf('if (host_hwnd_ != nullptr)');
      expect(guardIdx, greaterThan(-1));
      final block = body.substring(guardIdx, guardIdx + 400);
      expect(block, contains('SetForegroundWindow'));
      expect(block, contains('SW_RESTORE'));
    });

    test('channel 暴露 focusHostWindow', () {
      expect(cpp, contains('"focusHostWindow"'));
      final start = cpp.indexOf('if (method == "focusHostWindow")');
      expect(start, greaterThan(-1));
      final body = cpp.substring(start, start + 500);
      expect(body, contains('SetForegroundWindow'));
    });

    test('Dart 提供 focusHostWindow 静态方法', () {
      final src = read(dartPlugin);
      expect(src, contains('static Future<bool> focusHostWindow()'));
      expect(src, contains("invokeMethod<bool>('focusHostWindow')"));
    });

    test('MpvSessionPlatform.focusHostWindow 转发（仅 Windows）', () {
      final src = read('lib/services/player/mpv_session_platform.dart');
      expect(src, contains('static Future<bool> focusHostWindow()'));
      expect(src, contains('HimiMpvWindowsSession.focusHostWindow()'));
    });
  });

  group('③ 全局 provider 守卫', () {
    test('nativePlayerActiveProvider 存在', () {
      final src = read('lib/providers/native_player_provider.dart');
      expect(src, contains('nativePlayerActiveProvider'));
      expect(src, contains('StateProvider<bool>'));
    });

    test('PlayerScreen 同步 provider 并在退出时复位', () {
      final src = read('lib/screens/player/player_screen.dart');
      expect(src, contains('_syncNativePlayerActiveFlag()'));
      expect(src, contains('nativePlayerActiveProvider.notifier'));
      // _safePopPlayerPage 里复位。
      final start = src.indexOf('Future<void> _safePopPlayerPage(');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 900);
      expect(body, contains('nativePlayerActiveProvider.notifier'));
    });
  });

  group('④ 播放入口守卫（7 处）', () {
    test('详情页 3 处入口有守卫', () {
      final src = read('lib/screens/detail/detail_screen.dart');
      expect(src, contains('Future<bool> _focusNativePlayerIfActive()'));
      final count = 'await _focusNativePlayerIfActive()'.allMatches(src).length;
      expect(count, 3, reason: '详情页有 3 处播放入口（剧集/电影/房间）');
    });

    test('房间页入口有守卫', () {
      final src = read('lib/screens/room/room_screen.dart');
      expect(src, contains('nativePlayerActiveProvider'));
      expect(src, contains('focusHostWindow'));
    });

    test('房间菜单 3 处入口有守卫', () {
      final src = read('lib/widgets/room_menu_button.dart');
      final count = 'nativePlayerActiveProvider'.allMatches(src).length;
      expect(count, 3, reason: '房间菜单有 3 处入口（扫码/输码/创建）');
      expect(src, contains('focusHostWindow'));
    });
  });

  group('⑤ Flutter 播放页不可见（详情页透出）', () {
    test('Windows + 原生 UI 时返回 SizedBox.shrink', () {
      final src = read('lib/screens/player/player_screen.dart');
      final idx = src.indexOf('if (_nativeUiActive && defaultTargetPlatform == TargetPlatform.windows)');
      expect(idx, greaterThan(-1));
      final block = src.substring(idx, idx + 200);
      expect(block, contains('SizedBox.shrink'));
    });

    test('守卫在所有 ref.watch / ref.listen 之后', () {
      final src = read('lib/screens/player/player_screen.dart');
      final guardIdx = src.indexOf(
          'if (_nativeUiActive && defaultTargetPlatform == TargetPlatform.windows)');
      final listenIdx = src.lastIndexOf('ref.listen(settingsProvider', guardIdx);
      expect(listenIdx, greaterThan(-1));
      expect(guardIdx, greaterThan(listenIdx),
          reason: '过早返回会跳过设置监听');
    });

    test('路由 opaque: false（详情页在下方透出）', () {
      final src = read('lib/core/router.dart');
      final start = src.indexOf("path: '/player/:id'");
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 900);
      expect(body, contains('opaque: false'));
    });
  });
}
