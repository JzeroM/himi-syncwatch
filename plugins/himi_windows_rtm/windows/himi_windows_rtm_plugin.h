#ifndef FLUTTER_PLUGIN_HIMI_WINDOWS_RTM_PLUGIN_H_
#define FLUTTER_PLUGIN_HIMI_WINDOWS_RTM_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <mutex>

namespace himi_windows_rtm {

class HimiWindowsRtmPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  HimiWindowsRtmPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~HimiWindowsRtmPlugin();

  HimiWindowsRtmPlugin(const HimiWindowsRtmPlugin&) = delete;
  HimiWindowsRtmPlugin& operator=(const HimiWindowsRtmPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // 向 Dart 侧推送事件（SDK 回调线程调用时内部加锁）
  void SendEvent(const flutter::EncodableMap& event);

  flutter::MethodChannel<flutter::EncodableValue> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::mutex sink_mutex_;
};

}  // namespace himi_windows_rtm

#endif  // FLUTTER_PLUGIN_HIMI_WINDOWS_RTM_PLUGIN_H_
