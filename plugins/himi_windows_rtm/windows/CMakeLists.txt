cmake_minimum_required(VERSION 3.21)
set(PROJECT_NAME "himi_windows_rtm")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "himi_windows_rtm_plugin")

# ---- Agora RTM C++ SDK 2.2.5（与移动端 agora_rtm 2.2.5 同版本，协议互通）----
# 优先级：-DAGORA_RTM_SDK= > 环境变量 AGORA_RTM_SDK > 自动下载解压
if(NOT DEFINED AGORA_RTM_SDK)
  if(DEFINED ENV{AGORA_RTM_SDK})
    set(AGORA_RTM_SDK "$ENV{AGORA_RTM_SDK}")
  else()
    set(_agora_zip "${CMAKE_CURRENT_BINARY_DIR}/Agora_RTM_SDK.zip")
    set(_agora_root "${CMAKE_CURRENT_BINARY_DIR}/agora_rtm_sdk_extract")
    set(_agora_marker "${_agora_root}/Agora_Native_SDK_for_Windows_MINI_RTM/sdk/x86_64/agora_rtm_sdk.dll.lib")
    if(NOT EXISTS "${_agora_marker}")
      message(STATUS "Downloading Agora RTM C++ SDK 2.2.5 ...")
      file(DOWNLOAD
        "https://download.agora.io/rtm2/release/Agora_RTM_C%2B%2B_SDK_for_Windows_v2.2.5.zip"
        "${_agora_zip}"
        SHOW_PROGRESS
        STATUS _agora_dl_status)
      list(GET _agora_dl_status 0 _agora_dl_code)
      if(NOT _agora_dl_code EQUAL 0)
        list(GET _agora_dl_status 1 _agora_dl_msg)
        message(FATAL_ERROR "下载 Agora RTM SDK 失败: ${_agora_dl_msg}")
      endif()
      file(ARCHIVE_EXTRACT INPUT "${_agora_zip}" DESTINATION "${_agora_root}")
      if(NOT EXISTS "${_agora_marker}")
        message(FATAL_ERROR "Agora RTM SDK 解压后缺少 ${_agora_marker}")
      endif()
    endif()
    set(AGORA_RTM_SDK "${_agora_root}/Agora_Native_SDK_for_Windows_MINI_RTM")
  endif()
endif()

set(_agora_include "${AGORA_RTM_SDK}/sdk/high_level_api/include")
set(_agora_lib "${AGORA_RTM_SDK}/sdk/x86_64/agora_rtm_sdk.dll.lib")
if(NOT EXISTS "${_agora_lib}")
  message(FATAL_ERROR "缺少 Agora RTM SDK 导入库: ${_agora_lib}(AGORA_RTM_SDK=${AGORA_RTM_SDK})")
endif()

add_library(${PLUGIN_NAME} SHARED
  "himi_windows_rtm_plugin.cpp"
  "himi_windows_rtm_plugin_c_api.cc"
  "rtm_client.cpp"
  "include/himi_windows_rtm/himi_windows_rtm_plugin_c_api.h"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_STANDARD 17)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE "${_agora_include}")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  "${_agora_lib}"
)

# 运行时 DLL 随插件一起打进 Release（flutter 构建系统收集此变量）
set(himi_windows_rtm_bundled_libraries
  "${AGORA_RTM_SDK}/sdk/x86_64/agora_rtm_sdk.dll"
  "${AGORA_RTM_SDK}/sdk/x86_64/libaosl.dll"
  PARENT_SCOPE
)
