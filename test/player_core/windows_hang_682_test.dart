import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 682：Windows 11 上「进房间 / 单人移动播放器窗口」无响应（Application Hang）。
///
/// ## 事件日志
///
/// ```
/// 程序 himi_syncwatch.exe 版本 1.5.91.671 停止与 Windows 交互并已关闭
/// 来源: Application Hang (事件 ID 1002)
/// TerminationTime: 215
/// ```
///
/// 真机表现：**Qt 视频窗还在播放**，Flutter 面板窗白屏/透明、点不动、
/// 不显示 —— 这是「UI 线程被同步阻塞」的典型特征（Qt 是独立进程，
/// 它的消息循环不受影响）。
///
/// ## 三条根因（都在主线程上）
///
/// 1. **日志同步 fsync**：`LogService` 每次 `log()` 都
///    `writeAsStringSync(flush: true)`——open + write + **fsync** 全在
///    UI 线程。拖动窗口时 Qt 每 80ms 回一帧 `windowMoved`，Dart 跟随 +
///    `setBounds` 又连带多次日志 → fsync 排队累积 → 秒级卡死。
/// 2. **EnumWindows 跨进程枚举**：`WindowsWindowStyle._findMainWindow`
///    用 `NativeCallable.isolateLocal` + `EnumWindows` 遍历**所有**顶层
///    窗口（含其他进程）。任一窗口所属线程卡住，枚举就被拖住，主线程
///    跟着卡。而且回调跨 FFI 边界、`callback.close()` 可能与飞行中的
///    枚举竞争。
/// 3. **窗口跟随回环**：`_applyingFollowBounds` 只覆盖
///    `await setBounds` 期间，但 Windows 的 `WM_MOVE`/`WM_SIZE` 是
///    **异步投递**的——标志复位后才到达 → 被当成用户拖动 → 再跟随
///    → 无限回环。
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// 去掉注释行（`//` 与 `///`）——注释里会提到旧写法「说明为什么改」，
  /// 直接用 `contains` 会误判成「代码里还在用」。
  String codeOnly(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  late String logService;
  late String windowStyle;
  late String playerScreen;

  setUpAll(() {
    logService = read('lib/services/log_service.dart');
    windowStyle = read('lib/services/platform/windows_window_style.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
  });

  String extract(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    var i = start;
    while (i < src.length && src[i] != '(') {
      i++;
    }
    var paren = 0;
    for (; i < src.length; i++) {
      if (src[i] == '(') paren++;
      if (src[i] == ')') {
        paren--;
        if (paren == 0) {
          i++;
          break;
        }
      }
    }
    while (i < src.length && src[i] != '{') {
      i++;
    }
    var depth = 0;
    for (; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    return src.substring(start);
  }

  // ═══════════════════════════════════════════════════════════════
  // A. 日志落盘不得阻塞 UI 线程
  // ═══════════════════════════════════════════════════════════════

  group('A 日志同步 fsync 是主线程卡死源', () {
    test('A1 不再有 writeAsStringSync（同步 open+write+fsync）', () {
      expect(codeOnly(logService), isNot(contains('writeAsStringSync')));
    });

    test('A2 改为内存缓冲 + 单飞异步写', () {
      final body = extract(logService, 'void _appendToRuntime(');
      // 纯内存入队，零 IO
      expect(body, contains('_runtimeBuffer.add(entry)'));
      expect(body, contains('_scheduleRuntimeFlush()'));
      // 单飞闸
      expect(logService, contains('bool _runtimeFlushing'));
      final flush = extract(logService, 'void _scheduleRuntimeFlush(');
      expect(flush, contains('if (_runtimeFlushing) return;'));
      // 异步写（不是 Sync）
      expect(flush, contains('writeAsString('));
      expect(flush, isNot(contains('writeAsStringSync')));
    });

    test('A3 批量合并（同帧内多条日志一次写）', () {
      final flush = extract(logService, 'void _scheduleRuntimeFlush(');
      // 16ms 让出一帧后整批写
      expect(flush, contains('Future<void>.delayed'));
      expect(flush, contains('batch.join'));
      // 写盘期间新日志继续排下一轮（不丢）
      expect(flush, contains('if (_runtimeBuffer.isNotEmpty)'));
    });

    test('A4 启动早期日志不丢（文件就绪后补写）', () {
      final init = extract(logService, 'Future<void> _initRuntimeFile(');
      expect(init, contains('_runtimeBuffer.isNotEmpty'));
      expect(init, contains('_scheduleRuntimeFlush()'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 窗口查找不得跨进程枚举
  // ═══════════════════════════════════════════════════════════════

  group('B EnumWindows 跨进程枚举会拖死主线程', () {
    test('B1 不再用 EnumWindows + NativeCallable 回调', () {
      final code = codeOnly(windowStyle);
      expect(code, isNot(contains('EnumWindows')));
      expect(code, isNot(contains('NativeCallable')));
      expect(code, isNot(contains('isolateLocal')));
    });

    test('B2 改用 FindWindowEx 按类名直查', () {
      final body = extract(windowStyle, 'static int _findMainWindow()');
      expect(body, contains('FindWindowEx'));
      // 不再需要跨 FFI 回调
      expect(body, isNot(contains('nativeFunction')));
    });

    test('B3 仍用 pid 复核（防误伤其他 Flutter 应用）', () {
      final body = extract(windowStyle, 'static int _findMainWindow()');
      expect(body, contains('GetWindowThreadProcessId'));
      expect(body, contains('pidBuf.value == myPid'));
    });

    test('B4 循环查找不无限（hwnd 递进 + 0 结束）', () {
      final body = extract(windowStyle, 'static int _findMainWindow()');
      expect(body, contains('while (hwnd != 0)'));
      expect(body, contains('hwnd = FindWindowEx(0, hwnd, cls, nullptr)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 窗口跟随回环
  // ═══════════════════════════════════════════════════════════════

  group('C 窗口跟随回环会打满主线程', () {
    test('C1 目标矩形与当前一致时直接跳过（防迟到事件回环）', () {
      final body = extract(playerScreen, 'Future<void> _followQtWindow(');
      expect(body, contains('final target = Rect.fromLTWH('));
      expect(body, contains('(target.left - cur.left).abs() < 1'));
      expect(body, contains('return;'));
    });

    test('C2 16ms 节流合并拖动抖动', () {
      final body = extract(playerScreen, 'Future<void> _followQtWindow(');
      expect(body, contains('_lastFollowAt'));
      expect(body, contains('inMilliseconds < 16'));
    });

    test('C3 面板驱动 Qt 方向也去重（防反向回环）', () {
      final body = extract(playerScreen, 'Future<void> _pushPanelRectToQt(');
      expect(body, contains('_lastQtRect'));
      expect(body, contains('return;'));
      // 目标矩形与上次相同则不发命令
      expect(body, contains('(target.left - last.left).abs() < 1'));
    });

    test('C4 程序性移动仍用标志过滤（双向都保留）', () {
      expect(playerScreen, contains('_applyingFollowBounds'));
      final changed = extract(playerScreen, 'void _onPanelWindowChanged()');
      expect(changed, contains('if (_applyingFollowBounds) return;'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 三个场景的共同点：都在主线程
  // ═══════════════════════════════════════════════════════════════

  group('D 进房间与移动窗口的共同阻塞路径', () {
    test('D1 进房间会调 setRoomChrome（曾用 EnumWindows）', () {
      expect(playerScreen, contains('WindowsWindowStyle.setRoomChrome(true)'));
      // 现在走 FindWindowEx，不再枚举
      expect(windowStyle, contains('FindWindowEx'));
    });

    test('D2 拖动窗口会高频触发 windowMoved 日志', () {
      // Qt 侧 80ms 节流回传；Dart 侧每条日志都曾同步 fsync
      final mainCpp =
          File('native/windows_qt_player/src/main.cpp').readAsStringSync();
      expect(mainCpp, contains('sendWindowMoved'));
      expect(mainCpp, contains('用户移动/缩放'));
      // 日志侧已改为异步批量
      expect(codeOnly(logService), isNot(contains('writeAsStringSync')));
    });
  });
}
