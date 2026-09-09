cmake_minimum_required(VERSION 3.21)

project(himi_qt_win VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- 第三方库搜索路径（由用户/CI 传入或通过环境变量指定）----
# AGORA_RTM_SDK: 声网 RTM C++ SDK 解压根目录（含 sdk/ 与 include 头）
# LIBMPV_DIR   : libmpv 解压根目录（含 include/mpv/client.h 与 libmpv-2.dll）
if(NOT DEFINED AGORA_RTM_SDK AND DEFINED ENV{AGORA_RTM_SDK})
    set(AGORA_RTM_SDK "$ENV{AGORA_RTM_SDK}")
endif()
if(NOT DEFINED LIBMPV_DIR AND DEFINED ENV{LIBMPV_DIR})
    set(LIBMPV_DIR "$ENV{LIBMPV_DIR}")
endif()

# Qt6 快速应用（QML）
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick QuickControls2)

qt_standard_project_setup()

qt_add_executable(himi_qt_win
    src/main.cpp
    src/rtm_engine.cpp
)

qt_add_qml_module(himi_qt_win
    URI HimiWin
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
)

# ---- M1: Agora RTM C++ SDK ----
# AGORA_RTM_SDK 指向声网 RTM C++ SDK 解压根目录(含 sdk/high_level_api/include 与 sdk/x86_64)
if(NOT AGORA_RTM_SDK)
    message(FATAL_ERROR "缺少 AGORA_RTM_SDK(声网 RTM C++ SDK 根目录)。请设置 CMake 变量或环境变量 AGORA_RTM_SDK。")
endif()

target_include_directories(himi_qt_win PRIVATE
    "${AGORA_RTM_SDK}/sdk/high_level_api/include"
)
target_link_libraries(himi_qt_win PRIVATE
    "${AGORA_RTM_SDK}/sdk/x86_64/agora_rtm_sdk.dll.lib"
)

# 拷贝运行时 DLL 到输出目录
add_custom_command(TARGET himi_qt_win POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${AGORA_RTM_SDK}/sdk/x86_64/agora_rtm_sdk.dll"
        "$<TARGET_FILE_DIR:himi_qt_win>/agora_rtm_sdk.dll")
add_custom_command(TARGET himi_qt_win POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${AGORA_RTM_SDK}/sdk/x86_64/libaosl.dll"
        "$<TARGET_FILE_DIR:himi_qt_win>/libaosl.dll")

# ---- M2 起引入：libmpv ----
# 预留
# if(LIBMPV_DIR)
#     target_include_directories(himi_qt_win PRIVATE "${LIBMPV_DIR}/include")
#     target_link_libraries(himi_qt_win PRIVATE "${LIBMPV_DIR}/lib/libmpv.dll.a")
# endif()

target_link_libraries(himi_qt_win PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
)

# 将运行时第三方 DLL 复制到输出目录（AgoraRtmWrapper 场景类似 libmpv-2.dll）
# 需要时在 M1/M2 打开；DLL 源路径需按实际 SDK 布局填写
# if(WIN32 AND DEFINED LIBMPV_DIR)
#     add_custom_command(TARGET himi_qt_win POST_BUILD
#         COMMAND ${CMAKE_COMMAND} -E copy_if_different
#             "${LIBMPV_DIR}/bin/libmpv-2.dll"
#             "$<TARGET_FILE_DIR:himi_qt_win>/libmpv-2.dll")
# endif()
