#include "run_loop.h"

#include <flutter/dart_project.h>
#include <flutter/flutter_engine_controller.h>

#include <memory>

Runloop::Runloop() : controller_(std::make_unique<flutter::FlutterEngineController>()) {}

Runloop::~Runloop() {
  Quit();
}

void Runloop::Run() {
  MSG msg;
  while (GetMessage(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
}

void Runloop::Quit() {
  PostQuitMessage(0);
}
