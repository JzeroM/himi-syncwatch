#ifndef FLUTTER_PLUGIN_HIMI_WINDOWS_RTM_PLUGIN_H_
#define FLUTTER_PLUGIN_HIMI_WINDOWS_RTM_PLUGIN_H_

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <mutex>
#include <string>

#include "rtm_client.h"

namespace himi_windows_rtm {

class HimiWindowsRtmPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  HimiWindowsRtmPlugin(flutter::PluginRegistrarWindows* registrar);
  ~HimiWindowsRtmPlugin() override;

  HimiWindowsRtmPlugin(const HimiWindowsRtmPlugin&) = delete;
  HimiWindowsRtmPlugin& operator=(const HimiWindowsRtmPlugin&) = delete;

 private:
  static constexpr UINT kRtmEventMessage = WM_APP + 41;
  static constexpr wchar_t kWindowClassName[] = L"HimiWindowsRtmEventWindow";

  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool CreateEventWindow();
  void DestroyEventWindow();
  // SDK 工作线程 → PostMessage → 平台线程 WindowProc → event sink
  void PostRtmEvent(RtmEvent event);
  void SendEvent(const flutter::EncodableMap& event);

  flutter::MethodChannel<flutter::EncodableValue> method_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::mutex sink_mutex_;
  std::unique_ptr<RtmClient> rtm_;
  HWND event_hwnd_ = nullptr;
};

}  // namespace himi_windows_rtm

#endif  // FLUTTER_PLUGIN_HIMI_WINDOWS_RTM_PLUGIN_H_
