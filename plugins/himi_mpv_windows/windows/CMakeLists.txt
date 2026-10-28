cmake_minimum_required(VERSION 3.14)
project(himi_mpv_windows LANGUAGES CXX)

set(PLUGIN_NAME "himi_mpv_windows_plugin")

add_library(${PLUGIN_NAME} SHARED
  "himi_mpv_windows_plugin.cpp"
  "himi_mpv_windows_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../..")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin user32 dwmapi dxgi dbghelp)
