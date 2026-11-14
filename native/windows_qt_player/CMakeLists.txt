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

# ── QML 资源路径的两个坑（657.1 / 658 真机实测）────────────────────
#
# 坑 1：QML_FILES 的相对路径会**原样保留**在 qrc 里。
#   写 `src/qml/Main.qml` → 注册成 `.../HimiPlayer/src/qml/Main.qml`
#   → 用 QT_RESOURCE_ALIAS 抹掉目录前缀。
#
# 坑 2：`RESOURCE_PREFIX` 默认是 **`/`**，不是 `/qt/qml`。
#   不显式设置时，qmldir 里写的是 `prefer :/HimiPlayer/`，
#   实际路径 `qrc:/HimiPlayer/Main.qml`；
#   而 main.cpp 加载 `qrc:/qt/qml/HimiPlayer/Main.qml` → 差 `/qt/qml`
#   → 退出码 -3（QML 加载失败）。
#
#   虽然改代码成 `qrc:/HimiPlayer/...` 也能跑，但 `/qt/qml` 是 Qt 6 的
#   标准约定（QQmlEngine 会自动搜索该前缀，`import HimiPlayer` 的模块
#   解析也依赖它），所以显式设置 RESOURCE_PREFIX 保持标准。
foreach(_qml Main Overlay PlayerShortcuts VideoGestures TopBar BottomBar
             ControlButton Panel Theme Icons PlayerSlider EpisodeLogo
             DisplayAdjustPanel WindowResizeEdges DanmakuLayer DebugPanel)
    set_source_files_properties("src/qml/${_qml}.qml" PROPERTIES
        QT_RESOURCE_ALIAS "${_qml}.qml")
endforeach()

# EvolveUI vendor 组件（third_party/evolveui，MIT）：放进 evolveui/ 子
# 目录，QML 里 `import "evolveui" as EUI` 相对解析。
foreach(_qml ETheme EButton ESlider ECard ELoader EList)
    set_source_files_properties("src/qml/evolveui/${_qml}.qml" PROPERTIES
        QT_RESOURCE_ALIAS "evolveui/${_qml}.qml")
endforeach()

# 单例注册：Theme / Icons 是 `pragma Singleton`，必须显式声明
# QT_QML_SINGLETON_TYPE，否则 `import HimiPlayer` 后拿不到 Theme.xxx。
# 必须在 qt_add_qml_module **之前**设置。
set_source_files_properties(src/qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
set_source_files_properties(src/qml/Icons.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(himi_qt_player
    URI HimiPlayer
    VERSION 1.0
    # 必须显式指定：默认是 `/`，会导致 qrc:/HimiPlayer/... 与代码里的
    # qrc:/qt/qml/HimiPlayer/... 不一致。
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        src/qml/Main.qml
        src/qml/Overlay.qml
        src/qml/PlayerShortcuts.qml
        src/qml/VideoGestures.qml
        src/qml/TopBar.qml
        src/qml/BottomBar.qml
        src/qml/ControlButton.qml
        src/qml/Panel.qml
        src/qml/Theme.qml
        src/qml/Icons.qml
        src/qml/PlayerSlider.qml
        src/qml/EpisodeLogo.qml
        src/qml/DisplayAdjustPanel.qml
        src/qml/WindowResizeEdges.qml
        src/qml/DanmakuLayer.qml
        src/qml/DebugPanel.qml
        src/qml/evolveui/ETheme.qml
        src/qml/evolveui/EButton.qml
        src/qml/evolveui/ESlider.qml
        src/qml/evolveui/ECard.qml
        src/qml/evolveui/ELoader.qml
        src/qml/evolveui/EList.qml
)

# ── EvolveUI 资产（FontAwesome 字体 + loader.gif）────────────────────
#
# 组件内硬编码 `qrc:/new/prefix1/fonts/...`（上游约定，见
# third_party/evolveui/NOTICE.md），这里用 PREFIX + BASE 原样注册，
# 这样 EvolveUI 源码**零修改**可用。
qt_add_resources(himi_qt_player "evolveui-assets"
    PREFIX "/new/prefix1"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/third_party/evolveui/assets"
    FILES
        third_party/evolveui/assets/fonts/loader.gif
        third_party/evolveui/assets/fonts/fontawesome-free-6.7.2-desktop/otfs/Font\ Awesome\ 6\ Free-Solid-900.otf
        third_party/evolveui/assets/fonts/fontawesome-free-6.7.2-desktop/otfs/Font\ Awesome\ 6\ Free-Regular-400.otf
        third_party/evolveui/assets/fonts/fontawesome-free-6.7.2-desktop/otfs/Font\ Awesome\ 6\ Brands-Regular-400.otf
)

# 图标字体路径（与 Main.qml 的 FontLoader source 一致）：
#   qrc:/new/prefix1/fonts/fontawesome-free-6.7.2-desktop/otfs/Font Awesome 6 Free-Solid-900.otf

# ── qt.conf（659 真机全黑的根因）────────────────────────────────────
#
# 【现象】窗口能弹出但全黑，控制台刷满
#   QWARN  QmlComponent: Component is not ready
#
# 【根因】windeployqt 把 qml/ 目录拷到输出目录了，但**没有 qt.conf**。
# Qt 运行时找不到 qt.conf 时会按**编译期写死的绝对路径**去找 QML 模块：
#   D:/a/himi-syncwatch/.../qml
# 用户机器上当然没有这个路径 → `import QtQuick.Controls.Basic` 全部失败
# → 所有子组件创建不出来 → 全黑。
#
# 【修法】在 exe 同级生成 qt.conf，把 Qml2Imports 指到相对目录 ./qml。
# 这是 Qt 官方推荐的部署方式（windeployqt 的 --qml 分支也会这么做）。
file(WRITE "${CMAKE_BINARY_DIR}/qt.conf"
"[Paths]\n"
"Prefix = .\n"
"Plugins = .\n"
"Qml2Imports = ./qml\n")

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
    # 677：房间并排跟随用 DwmGetWindowAttribute 取窗口真实可见边界
    #（GetWindowRect 含 Win10/11 不可见边框 + 阴影 → 两窗重叠一条缝）。
    dwmapi
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
