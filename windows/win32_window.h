#pragma once

#include <windows.h>
#include <windowsx.h>
#include <winuser.h>
#include <dwmapi.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_engine_controller.h>

#include <memory>
#include <functional>

class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring& title, Point origin, Size size);

  HWND GetHandle();
  void SetQuitOnClose(bool quit_on_close);
  RECT GetClientArea();

  void SetChildContent(HWND child);

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();
  virtual LRESULT MessageHandler(HWND hwnd, UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

 private:
  friend LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                   WPARAM const wparam,
                                   LPARAM const lparam) noexcept;

  bool quit_on_close_ = false;
  HWND window_handle_ = nullptr;
  HWND child_content_ = nullptr;
  WNDCLASS window_class_;
  HINSTANCE hInstance_;
};

class Runloop {
 public:
  Runloop();
  ~Runloop();

  void Run();
  void Quit();

 private:
  std::function<void()> task_runner_;
  std::unique_ptr<flutter::FlutterEngineController> controller_;
};
