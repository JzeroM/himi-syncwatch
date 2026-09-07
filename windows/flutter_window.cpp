#include "flutter_window.h"

#include <flutter/dart_project.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  if (flutter_controller_) {
    flutter_controller_->SetEngine(nullptr);
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  flutter_controller_->GetEngine()->SetNextVSyncCallback(
      [](void* data, uint64_t deadline) {});

  Runloop(run_loop_);

  flutter_controller_->ForceSoftwareRasterization();

  flutter_controller_->GetRenderEventHandler()->SetRenderCallback(
      [](void* data, bool disable) {});

  flutter_controller_->GetEngine()->OnVsync(
      0, []() {}, flutter::FlutterEngine::kFrameRendered, nullptr);

  SetChildContent(flutter_controller_->GetView()->GetNativeWindow());

  flutter_controller_->Engine()->SetInitialRoute(L"/");

  flutter_controller_->GetEngine()->Run(L"");

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE: {
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    }
    case WM_SETTINGCHANGE: {
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
