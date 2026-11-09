cmake_minimum_required(VERSION 3.21)

project(himi_qt_win VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================================
# 654：Windows 播放器窗口 spike（Qt Quick + libmpv 直出）
#
# 【本轮目的】只验证**一个**致命假设：
#   mpv 用 `wid` 直出到 Qt 创建的 HWND 时，HDR 是否还在？
#
# 若成立 → 继续 655~660 用 QML 做播放器 UI（底栏/顶栏/面板/弹幕）。
# 若不成立 → 立刻改走路线 B（mpv 渲染进 QML 单窗，丢 HDR 换单窗）。
#
# 【为什么不接 RTM】用户已明确：RTM 与房间同步**全部留在 Flutter**，
# Qt 只做播放器窗口。故本轮删除了 M1 的声网 RTM 强制依赖
# （旧版缺该变量直接 FATAL_ERROR，会让 spike 无法独立构建）。
# 旧的 rtm_engine.{h,cpp} 已从仓库删除，等后续需要时再重新引入。
# ============================================================================

# ---- libmpv 定位 ----
# LIBMPV_DIR 应指向含 include/mpv/client.h 与 libmpv.dll.a 的根目录
# （CI 从 shinchiro mpv-dev-x86_64.7z 解压得到）。
if(NOT DEFINED LIBMPV_DIR AND DEFINED ENV{LIBMPV_DIR})
    set(LIBMPV_DIR "$ENV{LIBMPV_DIR}")
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick QuickControls2 Qml)

qt_standard_project_setup()

qt_add_executable(himi_qt_win
    src/main.cpp
    src/mpv_window.cpp
)

qt_add_qml_module(himi_qt_win
    URI HimiWin
    VERSION 1.0
    QML_FILES
        src/qml/Main.qml
)

if(NOT LIBMPV_DIR)
    message(FATAL_ERROR
        "缺少 LIBMPV_DIR（libmpv 根目录，需含 include/mpv/client.h）。"
        "请设置 CMake 变量或环境变量 LIBMPV_DIR。")
endif()

set(_mpv_header "${LIBMPV_DIR}/include/mpv/client.h")
if(NOT EXISTS "${_mpv_header}")
    message(FATAL_ERROR "缺少 mpv 头文件: ${_mpv_header}(LIBMPV_DIR=${LIBMPV_DIR})")
endif()

target_include_directories(himi_qt_win PRIVATE "${LIBMPV_DIR}/include")

# 导入库：shinchiro 包内为 libmpv.dll.a；兼容 libmpv.lib（MSVC 原生）。
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
    message(FATAL_ERROR
        "缺少 libmpv 导入库（尝试过 libmpv.dll.a / libmpv.lib）。LIBMPV_DIR=${LIBMPV_DIR}")
endif()
message(STATUS "libmpv 导入库: ${_mpv_implib}")

target_link_libraries(himi_qt_win PRIVATE
    "${_mpv_implib}"
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Qml
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
    add_custom_command(TARGET himi_qt_win POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${_mpv_dll}"
            "$<TARGET_FILE_DIR:himi_qt_win>/libmpv-2.dll")
else()
    message(WARNING
        "未找到 libmpv-2.dll（LIBMPV_DIR=${LIBMPV_DIR}）；"
        "运行时需手动把 DLL 放到 exe 同级目录。")
endif()
