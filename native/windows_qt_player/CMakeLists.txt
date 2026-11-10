cmake_minimum_required(VERSION 3.21)

project(himi_qt_player VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================================
# 656：HIMI Windows 播放器窗口（Qt Quick + libmpv）
#
# 【定位】Flutter 是唯一逻辑权威（Emby / 房间同步 / RTM / 弹幕拉取），
# 本程序只是「播放器窗口 + 控件」：
#   - mpv 用 `wid` 直出到自己的 HWND（HDR 直出）
#   - QML 画顶栏/底栏/面板
#   - 通过**命名管道**与 Flutter 双向通信（Qt 做服务端）
#
# 【协议复用】不重新设计协议，直接消费 Flutter 侧已有的
# `NativePlayerState`（87 字段 JSON）与 `NativePlayerCommand`（35 种）。
# 安卓/鸿蒙原生 UI 用的也是同一份，三端行为天然一致。
#
# 【为什么 mpv 不用 QML 渲染】libmpv 的 render API 只有 OpenGL 与软件
# 后端，没有 D3D11。把视频画进 QML 就得走 OpenGL FBO → mpv 先转 SDR
# RGBA → **HDR 直出必然丢失**。所以 mpv 自己拥有 HWND，QML 只做控件。
# ============================================================================

if(NOT DEFINED LIBMPV_DIR AND DEFINED ENV{LIBMPV_DIR})
    set(LIBMPV_DIR "$ENV{LIBMPV_DIR}")
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Qml Network)

qt_standard_project_setup()

qt_add_executable(himi_qt_player
    src/main.cpp
    src/mpv_window.cpp
    src/pipe_server.cpp
    src/player_state.cpp
)

# 657.1：QML_FILES 的相对路径会**原样保留**在 qrc 里。
#
# 写成 `src/qml/Main.qml` 会被注册成：
#     qrc:/qt/qml/HimiPlayer/src/qml/Main.qml
# 而 main.cpp 加载的是：
#     qrc:/qt/qml/HimiPlayer/Main.qml
# → 差一个 `src/qml/` 前缀 → 真机报
#   「QQmlApplicationEngine failed to load component
#     qrc:/qt/qml/HimiPlayer/Main.qml: 此文件或目录不存在」
#
# 用 QT_RESOURCE_ALIAS 把目录前缀抹掉，让注册路径与加载路径一致。
# （必须在 qt_add_qml_module **之前**设置，否则 CMake 已处理完文件列表。）
foreach(_qml Main TopBar BottomBar SeekBar ControlButton Panel)
    set_source_files_properties("src/qml/${_qml}.qml" PROPERTIES
        QT_RESOURCE_ALIAS "${_qml}.qml")
endforeach()

qt_add_qml_module(himi_qt_player
    URI HimiPlayer
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
        src/qml/TopBar.qml
        src/qml/BottomBar.qml
        src/qml/SeekBar.qml
        src/qml/ControlButton.qml
        src/qml/Panel.qml
    RESOURCES
        fonts/MaterialIcons-Regular.otf
)

# 字体同理：RESOURCES 里的 `fonts/xxx.otf` 也会保留前缀，
# 但 QML 里用的就是 `qrc:/qt/qml/HimiPlayer/fonts/...`，两边一致，无需别名。

if(NOT LIBMPV_DIR)
    message(FATAL_ERROR
        "缺少 LIBMPV_DIR（libmpv 根目录，需含 include/mpv/client.h）。")
endif()

set(_mpv_header "${LIBMPV_DIR}/include/mpv/client.h")
if(NOT EXISTS "${_mpv_header}")
    message(FATAL_ERROR "缺少 mpv 头文件: ${_mpv_header}")
endif()

target_include_directories(himi_qt_player PRIVATE "${LIBMPV_DIR}/include")

# 导入库：shinchiro 包内为 libmpv.dll.a；兼容 MSVC 原生 libmpv.lib。
set(_mpv_implib "")
foreach(_cand
        "${LIBMPV_DIR}/libmpv.dll.a"
        "${LIBMPV_DIR}/lib/libmpv.dll.a"
        "${LIBMPV_DIR}/libmpv.lib"
        "${LIBMPV_DIR}/lib/libmpv.lib")
    if(EXISTS "${_cand}")
        set(_mpv_implib "${_cand}")
        break()
    endif()
endforeach()
if(NOT _mpv_implib)
    message(FATAL_ERROR "缺少 libmpv 导入库（尝试过 libmpv.dll.a / libmpv.lib）")
endif()
message(STATUS "libmpv 导入库: ${_mpv_implib}")

target_link_libraries(himi_qt_player PRIVATE
    "${_mpv_implib}"
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Qml
    Qt6::Network
)

# libmpv-2.dll 拷到输出目录（与 exe 同级才能被加载）。
set(_mpv_dll "")
foreach(_cand
        "${LIBMPV_DIR}/libmpv-2.dll"
        "${LIBMPV_DIR}/bin/libmpv-2.dll")
    if(EXISTS "${_cand}")
        set(_mpv_dll "${_cand}")
        break()
    endif()
endforeach()
if(_mpv_dll)
    add_custom_command(TARGET himi_qt_player POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_mpv_dll}"
            "$<TARGET_FILE_DIR:himi_qt_player>/libmpv-2.dll")
else()
    message(WARNING "未找到 libmpv-2.dll；运行时需手动放到 exe 同级目录。")
endif()
