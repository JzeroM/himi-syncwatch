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
  void HideSurface();
  void DestroySurface();
  flutter::EncodableMap QueryHdrCapabilities();

  flutter::PluginRegistrarWindows* registrar_;
  HWND parent_hwnd_ = nullptr;
  HWND flutter_view_ = nullptr;
  HWND surface_hwnd_ = nullptr;
  int surface_left_ = 0;
  int surface_top_ = 0;
  int surface_width_ = 0;
  int surface_height_ = 0;
  bool surface_on_top_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
};

}  // namespace himi_mpv_windows

#endif  // FLUTTER_PLUGIN_HIMI_MPV_WINDOWS_PLUGIN_H_
