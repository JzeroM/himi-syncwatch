#include "utils.h"

#include <flutter/dart_project.h>
#include <windows.h>

#include <codecvt>
#include <iostream>
#include <locale>
#include <sstream>
#include <vector>

std::vector<std::string> ConvertToCommandLineArguments(int argc, char* argv[]) {
  std::vector<std::string> command_line_arguments;
  for (int i = 0; i < argc; i++) {
    command_line_arguments.push_back(argv[i]);
  }
  return command_line_arguments;
}

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return L"";
  }
  int size_needed = MultiByteToWideChar(
      CP_UTF8, 0, utf8_string.c_str(), static_cast<int>(utf8_string.length()),
      nullptr, 0);
  std::wstring result(size_needed, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8_string.c_str(),
                      static_cast<int>(utf8_string.length()), &result[0],
                      size_needed);
  return result;
}
