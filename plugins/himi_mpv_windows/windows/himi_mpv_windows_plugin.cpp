#include "himi_mpv_windows_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <strsafe.h>
#include <dxgi1_6.h>
#include <wrl/client.h>

#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <memory>
#include <string>
#include <variant>

namespace himi_mpv_windows {
namespace {

constexpr char kMethodChannel[] = "himi_mpv_windows";
constexpr char kEventChannel[] = "himi_mpv_windows/surface";

LONG WINAPI LogUnhandledException(EXCEPTION_POINTERS* info) {
  wchar_t temp_path[MAX_PATH] = {};
  const DWORD temp_len = ::GetTempPathW(MAX_PATH, temp_path);
  if (temp_len == 0 || temp_len >= MAX_PATH) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  wchar_t log_path[MAX_PATH] = {};
  if (::StringCchPrintfW(log_path, MAX_PATH, L"%shimi_mpv_windows_crash.log",
                         temp_path) != S_OK) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  FILE* file = nullptr;
  if (_wfopen_s(&file, log_path, L"a, ccs=UTF-8") != 0 || file == nullptr) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  SYSTEMTIME now = {};
  ::GetLocalTime(&now);
  const auto* record = info != nullptr ? info->ExceptionRecord : nullptr;
  const auto address = record != nullptr
                           ? reinterpret_cast<uintptr_t>(record->ExceptionAddress)
                           : 0;
  HMODULE module = nullptr;
  if (address != 0) {
    ::GetModuleHandleExW(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(address), &module);
  }
  wchar_t module_path[MAX_PATH] = {};
  if (module != nullptr) {
    ::GetModuleFileNameW(module, module_path, MAX_PATH);
  }
  const auto module_base = reinterpret_cast<uintptr_t>(module);
  fwprintf(
      file,
      L"[%04u-%02u-%02uT%02u:%02u:%02u][crash] code=0x%08lx address=0x%llx "
      L"module=%ls base=0x%llx offset=0x%llx thread=%lu\n",
      now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
      record != nullptr ? record->ExceptionCode : 0,
      static_cast<unsigned long long>(address),
      module_path[0] != L'\0' ? module_path : L"<unknown>",
      static_cast<unsigned long long>(module_base),
      static_cast<unsigned long long>(address - module_base),
      ::GetCurrentThreadId());
  fflush(file);
  fclose(file);
  return EXCEPTION_CONTINUE_SEARCH;
}

flutter::EncodableMap SurfaceInfo(HWND hwnd, int width, int height) {
  flutter::EncodableMap map;
  map[flutter::EncodableValue("type")] = flutter::EncodableValue("surface");
  map[flutter::EncodableValue("handle")] =
      flutter::EncodableValue(static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd)));
  map[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
  map[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
  return map;
}

}  // namespace

void HimiMpvWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<HimiMpvWindowsPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

HimiMpvWindowsPlugin::HimiMpvWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  static bool crash_handler_installed = false;
  if (!crash_handler_installed) {
    crash_handler_installed = true;
    ::SetUnhandledExceptionFilter(LogUnhandledException);
  }

  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kMethodChannel,
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kEventChannel,
          &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<>>(
          [this](const flutter::EncodableValue* arguments,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<>> {
            event_sink_ = std::move(events);
            if (surface_hwnd_ != nullptr) {
              event_sink_->Success(flutter::EncodableValue(
                  SurfaceInfo(surface_hwnd_, surface_width_, surface_height_)));
            }
            return nullptr;
          },
          [this](const flutter::EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<>> {
            event_sink_ = nullptr;
            return nullptr;
          }));
}

HimiMpvWindowsPlugin::~HimiMpvWindowsPlugin() {
  DestroySurface();
}

void HimiMpvWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();
  if (method == "createSurface") {
    result->Success(flutter::EncodableValue(
        static_cast<int64_t>(reinterpret_cast<intptr_t>(CreateSurface()))));
    return;
  }
  if (method == "getCurrentSurface") {
    if (surface_hwnd_ == nullptr) {
      result->Success();
    } else {
      result->Success(flutter::EncodableValue(
          SurfaceInfo(surface_hwnd_, surface_width_, surface_height_)));
    }
    return;
  }
  if (method == "updateSurface") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args != nullptr) {
      auto value = [&](const char* key) -> int {
        auto it = args->find(flutter::EncodableValue(key));
        if (it == args->end()) return 0;
        if (auto p = std::get_if<int32_t>(&it->second)) return *p;
        if (auto p = std::get_if<int64_t>(&it->second)) return static_cast<int>(*p);
        return 0;
      };
      UpdateSurface(value("left"), value("top"), value("width"),
                    value("height"));
    }
    result->Success();
    return;
  }
  if (method == "hideSurface") {
    HideSurface();
    result->Success();
    return;
  }
  if (method == "destroySurface") {
    DestroySurface();
    result->Success();
    return;
  }
  if (method == "queryHdrCapabilities") {
    result->Success(flutter::EncodableValue(QueryHdrCapabilities()));
    return;
  }
  result->NotImplemented();
}

HWND HimiMpvWindowsPlugin::CreateSurface() {
  if (surface_hwnd_ != nullptr) {
    ::ShowWindow(surface_hwnd_, SW_SHOW);
    if (event_sink_ != nullptr) {
      event_sink_->Success(flutter::EncodableValue(
          SurfaceInfo(surface_hwnd_, surface_width_, surface_height_)));
    }
    return surface_hwnd_;
  }
  HWND flutter_view = registrar_->GetView()->GetNativeWindow();
  parent_hwnd_ = ::GetAncestor(flutter_view, GA_ROOT);
  if (parent_hwnd_ == nullptr) {
    parent_hwnd_ = flutter_view;
  }

  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSEX wc = {};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.lpfnWndProc = DefWindowProc;
    wc.hInstance = ::GetModuleHandle(nullptr);
    wc.lpszClassName = L"HIMI_MPV_SURFACE";
    wc.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
    ::RegisterClassEx(&wc);
    class_registered = true;
  }

  flutter_view_ = flutter_view;
  surface_hwnd_ = ::CreateWindowEx(
      WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, L"HIMI_MPV_SURFACE", L"",
      WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0, 0, 16, 16, parent_hwnd_,
      nullptr, ::GetModuleHandle(nullptr), nullptr);
  if (surface_hwnd_ == nullptr) {
    return nullptr;
  }
  ::ShowWindow(surface_hwnd_, SW_SHOW);
  UpdateSurface(0, 0, 16, 16);
  if (event_sink_ != nullptr) {
    event_sink_->Success(flutter::EncodableValue(
        SurfaceInfo(surface_hwnd_, surface_width_, surface_height_)));
  }
  return surface_hwnd_;
}

void HimiMpvWindowsPlugin::UpdateSurface(int left, int top, int width,
                                         int height) {
  if (surface_hwnd_ == nullptr || flutter_view_ == nullptr) return;
  if (width <= 0 || height <= 0) return;

  RECT view_rect = {};
  ::GetWindowRect(flutter_view_, &view_rect);
  POINT origin = {view_rect.left, view_rect.top};
  ::MapWindowPoints(nullptr, parent_hwnd_, &origin, 1);

  surface_width_ = width;
  surface_height_ = height;
  ::SetWindowPos(surface_hwnd_, flutter_view_, origin.x + left,
                 origin.y + top, width, height,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void HimiMpvWindowsPlugin::HideSurface() {
  if (surface_hwnd_ != nullptr) {
    ::ShowWindow(surface_hwnd_, SW_HIDE);
  }
}

void HimiMpvWindowsPlugin::DestroySurface() {
  if (surface_hwnd_ != nullptr) {
    ::DestroyWindow(surface_hwnd_);
    surface_hwnd_ = nullptr;
    if (event_sink_ != nullptr) {
      flutter::EncodableMap map;
      map[flutter::EncodableValue("type")] =
          flutter::EncodableValue("surfaceDestroyed");
      map[flutter::EncodableValue("handle")] = flutter::EncodableValue(0);
      event_sink_->Success(flutter::EncodableValue(map));
    }
  }
}

flutter::EncodableMap HimiMpvWindowsPlugin::QueryHdrCapabilities() {
  flutter::EncodableList formats;
  Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
  if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND;
         ++i) {
      Microsoft::WRL::ComPtr<IDXGIOutput> output;
      for (UINT j = 0; adapter->EnumOutputs(j, &output) != DXGI_ERROR_NOT_FOUND;
           ++j) {
        Microsoft::WRL::ComPtr<IDXGIOutput6> output6;
        if (SUCCEEDED(output.As(&output6))) {
          DXGI_OUTPUT_DESC1 desc = {};
          if (SUCCEEDED(output6->GetDesc1(&desc)) &&
              desc.ColorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020) {
            formats.push_back(flutter::EncodableValue("hdr10"));
          }
        }
        output.Reset();
      }
      adapter.Reset();
    }
  }
  flutter::EncodableMap map;
  map[flutter::EncodableValue("formats")] = flutter::EncodableValue(formats);
  return map;
}

}  // namespace himi_mpv_windows
