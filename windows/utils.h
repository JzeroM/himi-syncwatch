#include <string>
#include <vector>

std::vector<std::string> ConvertToCommandLineArguments(int argc, char* argv[]);

std::wstring Utf16FromUtf8(const std::string& utf8_string);
