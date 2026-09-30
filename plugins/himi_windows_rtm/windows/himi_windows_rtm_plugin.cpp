#include "himi_windows_rtm_plugin.h"

#include <flutter/standard_method_codec.h>

#include <memory>
#include <utility>
#include <vector>

namespace himi_windows_rtm {

static constexpr const char* kChannelName = "himi_windows_rtm";

namespace {

flutter::EncodableMap EventToMap(const RtmEvent& event) {
  flutter::EncodableMap map;
  map["event"] = flutter::EncodableValue(event.type);

  if (event.type == "result") {
    map["requestId"] = flutter::EncodableValue(static_cast<int64_t>(event.request_id));
    map["method"] = flutter::EncodableValue(event.method);
    map["ok"] = flutter::EncodableValue(event.ok);
    map["reason"] = flutter::EncodableValue(event.reason);
    if (event.online_count >= 0) {
      map["count"] = flutter::EncodableValue(event.online_count);
      flutter::EncodableList ids;
      ids.reserve(event.user_ids.size());
      for (const auto& id : event.user_ids) {
        ids.emplace_back(id);
      }
      map["userIds"] = flutter::EncodableValue(ids);
    }
    if (!event.metadata.empty()) {
      flutter::EncodableMap metadata;
      for (const auto& item : event.metadata) {
        metadata[flutter::EncodableValue(item.first)] =
            flutter::EncodableValue(item.second);
      }
      map["metadata"] = flutter::EncodableValue(metadata);
      map["majorRevision"] = flutter::EncodableValue(event.major_revision);
    }
  } else if (event.type == "message") {
    map["publisher"] = flutter::EncodableValue(event.publisher);
    map["message"] = flutter::EncodableValue(event.message);
  } else if (event.type == "presence") {
    map["type"] = flutter::EncodableValue(event.presence_type);
    map["publisher"] = flutter::EncodableValue(event.publisher);
  } else if (event.type == "connection") {
    map["state"] = flutter::EncodableValue(event.reason);
  }
  return map;
}

std::string GetStringArg(const flutter::EncodableMap* args, const char* key) {
  if (!args) {
    return "";
  }
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end() || !std::holds_alternative<std::string>(it->second)) {
    return "";
  }
  return std::get<std::string>(it->second);
}

}  // namespace

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
  auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_pointer = plugin.get()](
          const void* /*arguments*/,
          std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        std::lock_guard<std::mutex> lock(plugin_pointer->sink_mutex_);
        plugin_pointer->event_sink_ = std::move(events);
        return nullptr;
      },
      [plugin_pointer = plugin.get()](const void* /*arguments*/)
          -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        std::lock_guard<std::mutex> lock(plugin_pointer->sink_mutex_);
        plugin_pointer->event_sink_.reset();
        return nullptr;
      });
  event_channel->SetStreamHandler(std::move(handler));

  registrar->AddPlugin(std::move(plugin));
}

HimiWindowsRtmPlugin::HimiWindowsRtmPlugin(flutter::PluginRegistrarWindows* registrar)
    : method_channel_(registrar->messenger(), kChannelName,
                      &flutter::StandardMethodCodec::GetInstance()) {
  CreateEventWindow();
  rtm_ = std::make_unique<RtmClient>();
  rtm_->SetEventHandler([this](const RtmEvent& event) { PostRtmEvent(event); });
}

HimiWindowsRtmPlugin::~HimiWindowsRtmPlugin() {
  rtm_.reset();
  DestroyEventWindow();
}

bool HimiWindowsRtmPlugin::CreateEventWindow() {
  static bool class_registered = []() {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = &HimiWindowsRtmPlugin::WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = kWindowClassName;
    return RegisterClassExW(&wc) != 0 ||
           GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
  }();
  if (!class_registered) {
    return false;
  }
  event_hwnd_ = CreateWindowExW(0, kWindowClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                GetModuleHandleW(nullptr), nullptr);
  if (event_hwnd_) {
    SetWindowLongPtrW(event_hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
  }
  return event_hwnd_ != nullptr;
}

void HimiWindowsRtmPlugin::DestroyEventWindow() {
  if (event_hwnd_) {
    DestroyWindow(event_hwnd_);
    event_hwnd_ = nullptr;
  }
}

void HimiWindowsRtmPlugin::PostRtmEvent(RtmEvent event) {
  if (!event_hwnd_) {
    return;
  }
  auto* heap_event = new RtmEvent(std::move(event));
  if (!PostMessageW(event_hwnd_, kRtmEventMessage, 0, reinterpret_cast<LPARAM>(heap_event))) {
    delete heap_event;
  }
}

void HimiWindowsRtmPlugin::SendEvent(const flutter::EncodableMap& event) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (event_sink_) {
    event_sink_->Success(flutter::EncodableValue(event));
  }
}

LRESULT CALLBACK HimiWindowsRtmPlugin::WindowProc(HWND hwnd, UINT msg, WPARAM wparam,
                                                  LPARAM lparam) {
  if (msg == kRtmEventMessage) {
    auto* self = reinterpret_cast<HimiWindowsRtmPlugin*>(
        GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    auto* event = reinterpret_cast<RtmEvent*>(lparam);
    if (self && event) {
      self->SendEvent(EventToMap(*event));
    }
    delete event;
    return 0;
  }
  if (msg == WM_NCDESTROY) {
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

void HimiWindowsRtmPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());

  auto rid_result = [result = std::move(result)](uint64_t rid) mutable {
    if (rid == 0) {
      result->Error("rtm_error", "客户端未就绪");
      return;
    }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {"rid", flutter::EncodableValue(static_cast<int64_t>(rid))},
    }));
  };

  if (method == "initialize") {
    const auto appId = GetStringArg(args, "appId");
    const auto userId = GetStringArg(args, "userId");
    const bool ok = !appId.empty() && !userId.empty() && rtm_ &&
                    rtm_->Initialize(appId, userId);
    result->Success(flutter::EncodableValue(ok));
    return;
  }
  if (method == "login") {
    rid_result(rtm_->Login(GetStringArg(args, "token")));
    return;
  }
  if (method == "logout") {
    rtm_->Logout();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "subscribe") {
    rid_result(rtm_->Subscribe(GetStringArg(args, "channel")));
    return;
  }
  if (method == "unsubscribe") {
    rtm_->Unsubscribe(GetStringArg(args, "channel"));
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "publish") {
    rid_result(rtm_->Publish(GetStringArg(args, "channel"), GetStringArg(args, "message")));
    return;
  }
  if (method == "getOnlineUsers") {
    rid_result(rtm_->GetOnlineUsers(GetStringArg(args, "channel")));
    return;
  }
  if (method == "setChannelMetadata") {
    std::vector<std::pair<std::string, std::string>> items;
    if (args) {
      auto it = args->find(flutter::EncodableValue("metadata"));
      if (it != args->end() && std::holds_alternative<flutter::EncodableMap>(it->second)) {
        const auto& metadata = std::get<flutter::EncodableMap>(it->second);
        for (const auto& entry : metadata) {
          if (std::holds_alternative<std::string>(entry.first) &&
              std::holds_alternative<std::string>(entry.second)) {
            items.emplace_back(std::get<std::string>(entry.first),
                               std::get<std::string>(entry.second));
          }
        }
      }
    }
    rid_result(rtm_->SetChannelMetadata(GetStringArg(args, "channel"), items));
    return;
  }
  if (method == "getChannelMetadata") {
    rid_result(rtm_->GetChannelMetadata(GetStringArg(args, "channel")));
    return;
  }
  if (method == "release") {
    rtm_->Release();
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (method == "getSdkInfo") {
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {"sdk", flutter::EncodableValue("Agora RTM C++ SDK 2.2.5")},
        {"plugin", flutter::EncodableValue("himi_windows_rtm 0.1.0")},
    }));
    return;
  }

  result->NotImplemented();
}

}  // namespace himi_windows_rtm
