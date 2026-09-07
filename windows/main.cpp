#include <flutter/flutter_engine_controller.h>
#include <flutter/dart_project.h>
#include <flutter/view.h>
#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>

#include <memory>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  ::CreateMutexW(0, TRUE, L"himi_syncwatch_app");
  const DWORD last_error = ::GetLastError();
  if (last_error == ERROR_ALREADY_EXISTS) {
    ::MessageBoxW(nullptr, L"应用已在运行中", L"HimiSync", MB_OK);
    return 0;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      flutter::ConvertToCommandLineArguments(GetCommandLineW());

  project.set_dart_entrypoint_arguments(std::vector<std::string>());

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"HimiSync", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
