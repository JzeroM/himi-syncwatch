# HimiSync Windows 客户端（Qt Quick / C++）

目标：用 **Qt Quick (QML) + C++** 从零重构 HimiSync 的 Windows 端，
以便直接使用 **Agora RTM C++ SDK（`agora_rtm_sdk.dll`，官方支持 Windows）**，
与现有 Android/iOS（Flutter + agora_rtm）客户端互通同步观影。

## 为什么这条路可行
- Flutter 的 `agora_rtm` 插件官方**不支持 Windows**（仅 Android/iOS）。
- 但 Agora **原生 C++ RTM SDK for Windows** 是官方支持、可直接集成。
- 用原生 C++ 重写 Windows 端，即可在 Windows 上获得完整 RTM 能力。

## 技术栈
| 模块 | 方案 |
|------|------|
| UI | Qt 6 Quick / QML（本目录 UI 类型 `HimiWin`） |
| 播放(M2) | libmpv client API（与现有 media_kit 同底层） |
| RTM(M1) | Agora C++ SDK `agora_rtm_sdk.dll` |
| HTTP(M3) | libcurl / cpr |

## 目录
```
native/windows_qt_client/
├── CMakeLists.txt
├── src/
│   ├── main.cpp
│   ├── rtm_engine.h / .cpp     # M1: Agora RTM C++ 封装，暴露给 QML
│   └── qml/Main.qml
└── README.md
```

## 构建（Windows 10/11，需 Qt 6.5+ 与 CMake 3.21+）
```powershell
# 1) 安装/定位 Qt 6 与编译器(MSVC)
# 2) 配置（Qt 6 用 qt-cmake 或手动指定路径）
cmake -S . -B build -G "Ninja" `
      -DCMAKE_PREFIX_PATH="C:/Qt/6.7.2/msvc2019_64"
cmake --build build --config Release
# 产物: build/himi_qt_win.exe
```

> 提示：在 Qt Creator 中直接打开 `CMakeLists.txt` 更省事。

## 里程碑状态
- **M0（完成）**：Qt Quick 空窗口骨架，能编译运行。
- **M1（进行中）**：Agora RTM C++ SDK 接入——登录/加入频道/在线人数/收发消息。
  - 需将 SDK 解压路径通过 CMake 变量 `AGORA_RTM_SDK` 或环境变量传入。
  - 完成 M0 在 Windows 构建验证后再继续。
- **M2**：libmpv 播放（播放/暂停/seek/进度）。
- **M3**：Emby 浏览。
- **M4**：与 Flutter 端协议联调互测。

## Agora SDK 位置
声网 RTM C++ SDK for Windows 解压后含：
`sdk/high_level_api/include/*.h` 与 `sdk/x86_64/agora_rtm_sdk.dll(.lib)`。
把根目录设为 `AGORA_RTM_SDK` 即可。
