#pragma once

#include <flutter/dart_project.h>
#include <flutter/flutter_engine_controller.h>

#include <memory>
#include <functional>

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
