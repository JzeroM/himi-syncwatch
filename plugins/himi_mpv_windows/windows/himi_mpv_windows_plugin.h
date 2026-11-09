#ifndef FLUTTER_PLUGIN_HIMI_MPV_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_HIMI_MPV_WINDOWS_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <memory>
#include <string>

namespace himi_mpv_windows {

class HimiMpvWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit HimiMpvWindowsPlugin(flutter::PluginRegistrarWindows* registrar);
  ~HimiMpvWindowsPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND CreateSurface();
  void UpdateSurface(int left, int top, int width, int height);
  void SetSurfaceZOrder(bool top);
  RECT SurfaceRectInClient(HWND target) const;
  void HideSurface();
  void DestroySurface();
  flutter::EncodableMap QueryHdrCapabilities();

  // ── 646：原生播放器顶层窗口（HDR 直出）──────────────────────
  //
  // 【为什么需要】Windows 上 Flutter 用 DirectComposition 呈现到一个
  // 不透明的顶层窗口，原生子 HWND **不在其合成树里** → 只能被整体遮挡
  // （真机实证：MPV surface 灰屏、texture 崩 flutter_windows.dll 0x1551f）。
  // Flutter 又不提供 Windows PlatformView（platform_views.dart 无 windows
  // 分支），所以无法像安卓/鸿蒙那样把原生视图嵌进 Flutter 布局。
  //
  // 唯一可行路径：**自建顶层窗口**（WS_POPUP + WS_EX_TOPMOST），
  // MPV 用 vo=gpu-next + wid 渲染进去 → 真 HDR 直出；
  // UI 后续用 Direct2D 叠加在同一窗口内（阶段 2+）。
  HWND CreateHostWindow(int x, int y, int width, int height);
  HWND CreateRenderSurface();
  void UpdateHostWindow(int x, int y, int width, int height);
  void DestroyHostWindow();
  flutter::EncodableMap GetHostWindowInfo() const;

  /// 648：创建 UI 叠加层（透明子窗口，阶段 3 用 Direct2D 往里画控件）。
  HWND CreateUiOverlay();

  /// 648：把窗口事件（关闭/按键/点击）转发给 Dart 侧。
  void EmitHostEvent(const char* type);

  static LRESULT CALLBACK HostWndProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_;
  HWND parent_hwnd_ = nullptr;
  HWND flutter_view_ = nullptr;
  HWND surface_hwnd_ = nullptr;
  int surface_left_ = 0;
  int surface_top_ = 0;
  int surface_width_ = 0;
  int surface_height_ = 0;
  bool surface_on_top_ = false;
  // 646：原生播放器顶层窗口。
  HWND host_hwnd_ = nullptr;
  HWND render_hwnd_ = nullptr;
  /// 648：UI 叠加层（透明子窗口，阶段 3 用 Direct2D 画控件）。
  HWND ui_hwnd_ = nullptr;
  int host_x_ = 0;
  int host_y_ = 0;
  int host_width_ = 0;
  int host_height_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace himi_mpv_windows

#endif  // FLUTTER_PLUGIN_HIMI_MPV_WINDOWS_PLUGIN_H_
