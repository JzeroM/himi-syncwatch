#include "himi_windows_rtm_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace himi_windows_rtm {

// M1 骨架：通道链路 + SDK 链接验证；C++ 核心在 M2 实现。
static constexpr const char* kChannelName = "himi_windows_rtm";

void HimiWindowsRtmPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<HimiWindowsRtmPlugin>(registrar);

  auto method_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
  method_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  auto event_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), std::string(kChannelName) + "/events",
      &flutter::StandardMethodCodec::GetInstance());
  auto plugin_weak = std::weak_ptr<HimiWindowsRtmPlugin>();
  // plugin 由 registrar 持有；用 raw 指针经 lambda 捕获 sink 设置
  auto sink_holder = [plugin_pointer = plugin.get()](
                         const void*, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
      -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
    plugin_pointer->event_sink_ = std::move(events);
    return nullptr;
  };
  auto cancel_holder = [plugin_pointer = plugin.get()](
                           const void*, const void*)
      -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
    std::lock_guard<std::mutex> lock(plugin_pointer->sink_mutex_);
    plugin_pointer->event_sink_.reset();
    return nullptr;
  };
  auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      std::move(sink_holder), std::move(cancel_holder));
  event_channel->SetStreamHandler(std::move(handler));

  registrar->AddPlugin(std::move(plugin));
  // method/event channel 的生命周期由 registrar 管理（messenger 存活期）
  (void)method_channel;
  (void)event_channel;
}

HimiWindowsRtmPlugin::HimiWindowsRtmPlugin(flutter::PluginRegistrarWindows* registrar)
    : method_channel_(registrar->messenger(), kChannelName,
                      &flutter::StandardMethodCodec::GetInstance()) {}

HimiWindowsRtmPlugin::~HimiWindowsRtmPlugin() = default;

void HimiWindowsRtmPlugin::SendEvent(const flutter::EncodableMap& event) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (event_sink_) {
    event_sink_->Success(flutter::EncodableValue(event));
  }
}

void HimiWindowsRtmPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();
  if (method == "getSdkInfo") {
    // M1 探测方法：验证通道与插件加载
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {"sdk", flutter::EncodableValue("Agora RTM C++ SDK 2.2.5")},
        {"plugin", flutter::EncodableValue("himi_windows_rtm 0.1.0")},
    }));
    return;
  }

  // M2 实现：initialize/login/logout/subscribe/unsubscribe/publish/
  //          getOnlineUsers/setChannelMetadata/getChannelMetadata/release
  result->NotImplemented();
}

}  // namespace himi_windows_rtm
