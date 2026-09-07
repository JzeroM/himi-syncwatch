#include "my_application.h"

#include <flutter/flutter_engine.h>
#include <flutter/main.h>
#include <flutter/dart_project.h>
#include <flutter/plugin_registrar.h>

#include <memory>

int main(int argc, char** argv) {
  flutter::DartProject project("data");

  std::vector<std::string> command_line_arguments =
      flutter::ConvertToCommandLineArguments(argc, argv);

  flutter::FlutterEngine engine(project);
  engine.Run(command_line_arguments, "");
  flutter::FlutterEngineRelease(engine);
  return 0;
}
