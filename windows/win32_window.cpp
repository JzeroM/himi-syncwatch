#include "win32_window.h"

#include <dwmapi.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_engine_controller.h>

#include <memory>

Win32Window::Win32Window() {}

Win32Window::~Win32Window() {
  Destroy();
}

bool Win32Window::Create(const std::wstring& title, Point origin, Size size) {
  const wchar_t* window_class = L"FlutterWindow";

  const WNDCLASS window_class = {
      .style = CS_HREDRAW | CS_VREDRAW,
      .lpfnWndProc = WndProc,
      .cbClsExtra = 0,
      .cbWndExtra = 0,
      .hInstance = GetModuleHandle(nullptr),
      .hIcon = LoadIcon(nullptr, IDI_APPLICATION),
      .hCursor = LoadCursor(nullptr, IDC_ARROW),
      .hbrBackground = (HBRUSH)(COLOR_WINDOW + 1),
      .lpszMenuName = nullptr,
      .lpszClassName = window_class,
  };

  RegisterClass(&window_class);

  const DWORD window_style =
      WS_OVERLAPPEDWINDOW | WS_VISIBLE | WS_MAXIMIZE;

  RECT window_rect;
  SetRect(&window_rect, origin.x, origin.y, origin.x + size.width,
          origin.y + size.height);
  AdjustWindowRect(&window_rect, window_style, false);

  HWND window = CreateWindow(
      window_class.lpszClassName, title.c_str(), window_style, window_rect.left,
      window_rect.top, window_rect.right - window_rect.left,
      window_rect.bottom - window_rect.top, nullptr, nullptr,
      GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  window_handle_ = window;
  SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  UpdateWindow(window);
  SetFocus(window);

  return OnCreate();
}

void Win32Window::Destroy() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

void Win32Window::SetChildContent(HWND child) {
  child_content_ = child;
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {}

LRESULT
Win32Window::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE: {
      if (child_content_) {
        DestroyWindow(child_content_);
        child_content_ = nullptr;
      }
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;
    }
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      EndPaint(hwnd, &ps);
      return 0;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                          WPARAM const wparam,
                          LPARAM const lparam) noexcept {
  if (message == WM_CREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT*>(lparam);
    auto self = static_cast<Win32Window*>(cs->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }

  auto self = reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  if (self) {
    return self->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}
