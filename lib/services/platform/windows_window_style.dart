import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../log_service.dart';

/// 677：Windows 主窗口标题栏按钮控制（房间模式专用）。
///
/// 【需求】房间模式下面板窗是「播放器的附属面板」，不是独立应用窗口：
/// 最大化会让面板占满屏把 Qt 播放窗挤掉，最小化会让面板从桌面消失
/// （用户会以为房间没了）。所以进房间时去掉这两个按钮，退房恢复。
///
/// 【为什么不用 `window_manager.setMaximizable/setMinimizable`】
/// 插件内部只改 `GWL_STYLE`，**没有发 `SWP_FRAMECHANGED`** ——
/// Windows 不会重绘非客户区，标题栏按钮常常看起来没变（要等下次
/// 触发重排才刷新）。这里自己发一次 `SetWindowPos` 保证立即生效。
///
/// 【为什么保留关闭按钮与拖边缩放】
/// - 关闭 = 退出房间（有确认框），必须保留
/// - 拖边缩放 = 用户调整面板宽度的唯一手段，必须保留
class WindowsWindowStyle {
  const WindowsWindowStyle._();

  /// Flutter Windows runner 注册的窗口类名（`windows/runner/win32_window.cpp`）。
  static const String windowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';

  /// 去掉最大化 / 最小化按钮（纯函数，可单测）。
  ///
  /// `WS_MAXIMIZEBOX` = 0x00010000，`WS_MINIMIZEBOX` = 0x00020000。
  @visibleForTesting
  static int stripMaxMinBoxes(int style) {
    return style & ~(WS_MAXIMIZEBOX | WS_MINIMIZEBOX);
  }

  /// 恢复最大化 / 最小化按钮（纯函数，可单测）。
  @visibleForTesting
  static int restoreMaxMinBoxes(int style) {
    return style | WS_MAXIMIZEBOX | WS_MINIMIZEBOX;
  }

  /// 是否已去掉两个按钮（纯函数，可单测）。
  @visibleForTesting
  static bool hasMaxMinBoxes(int style) {
    return (style & WS_MAXIMIZEBOX) != 0 && (style & WS_MINIMIZEBOX) != 0;
  }

  /// 应用/恢复房间模式的标题栏样式。
  ///
  /// [roomMode] true = 去掉最大化/最小化；false = 恢复。
  /// 失败静默（样式只是观感，不影响房间功能）。
  static Future<void> setRoomChrome(bool roomMode) async {
    if (!Platform.isWindows) return;
    try {
      final hwnd = _findMainWindow();
      if (hwnd == 0) {
        LogService().log('WindowStyle', '未找到主窗口，跳过标题栏调整');
        return;
      }
      final style = GetWindowLongPtr(hwnd, GWL_STYLE);
      final next =
          roomMode ? stripMaxMinBoxes(style) : restoreMaxMinBoxes(style);
      if (next == style) return;
      SetWindowLongPtr(hwnd, GWL_STYLE, next);
      // 关键：不发 FRAMECHANGED 标题栏不会重绘（按钮看起来还在）。
      SetWindowPos(
        hwnd,
        0,
        0,
        0,
        0,
        0,
        SWP_FRAMECHANGED |
            SWP_NOMOVE |
            SWP_NOSIZE |
            SWP_NOZORDER |
            SWP_NOACTIVATE,
      );
      LogService().log(
        'WindowStyle',
        '房间标题栏: ${roomMode ? "去最大化/最小化" : "恢复"}',
      );
    } catch (e) {
      LogService().log('WindowStyle', '标题栏调整失败: $e');
    }
  }

  /// 定位 Flutter 主窗（本进程 + 类名 + 顶层可见）。
  ///
  /// 【682 真机回归：进房间/移动播放器窗口时无响应（Application Hang）】
  ///
  /// 旧实现用 `EnumWindows` + `NativeCallable.isolateLocal` 回调：
  ///   - `EnumWindows` 会遍历**所有顶层窗口**（含其他进程），只要某个
  ///     窗口所属线程卡住，枚举就被拖住 → 主线程跟着卡
  ///   - 回调跨 FFI 边界执行，内部再调 `GetClassNameW` /
  ///     `GetWindowRect` 等 API，出错风险高
  ///   - `callback.close()` 在 `finally` 里立即释放，若枚举仍在飞行，
  ///     回调可能悬空
  ///
  /// 现在改用 `FindWindowExW` 按**类名直接查**：不遍历、不回调、
  /// 不跨 FFI 边界，单次 API 调用即可。类名
  /// `FLUTTER_RUNNER_WIN32_WINDOW` 是 Flutter runner 注册的，
  /// 同一时刻本机通常只有一个这样的窗口；再用 pid 复核一次保证唯一。
  static int _findMainWindow() {
    final myPid = pid;
    final cls = windowClassName.toNativeUtf16();
    final pidBuf = calloc<Uint32>();
    try {
      // 从桌面顶层窗口开始按类名查找（NULL = 桌面）。
      var hwnd = FindWindowEx(0, 0, cls, nullptr);
      while (hwnd != 0) {
        // pid 复核：防误伤其他 Flutter 应用（pid 复用/多实例）。
        GetWindowThreadProcessId(hwnd, pidBuf);
        if (pidBuf.value == myPid &&
            IsWindowVisible(hwnd) != 0 &&
            _hasArea(hwnd)) {
          return hwnd;
        }
        hwnd = FindWindowEx(0, hwnd, cls, nullptr);
      }
    } catch (_) {
      // 查找失败不影响房间功能（样式只是观感）。
    } finally {
      free(cls);
      free(pidBuf);
    }
    return 0;
  }

  /// 是否有有效尺寸（跳过 Flutter 的隐藏辅助窗）。
  static bool _hasArea(int hwnd) {
    final rect = calloc<RECT>();
    try {
      if (GetWindowRect(hwnd, rect) == 0) return false;
      return rect.ref.right - rect.ref.left > 0 &&
          rect.ref.bottom - rect.ref.top > 0;
    } catch (_) {
      return false;
    } finally {
      free(rect);
    }
  }
}
