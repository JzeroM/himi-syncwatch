<div align="center">

# HIMI Sync Watch

**HIMI — 跨平台 Emby 客户端**

全平台 Emby 媒体库客户端 · 原生 MPV 内核 · 弹幕 · 多人同步观影 · TV 模式

[![Release](https://img.shields.io/github/v/release/JzeroM/himi-syncwatch?style=flat-square&color=orange)](https://github.com/JzeroM/himi-syncwatch/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/JzeroM/himi-syncwatch/release.yml?branch=main&style=flat-square)](https://github.com/JzeroM/himi-syncwatch/actions)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-blue?style=flat-square&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-open%20source-green?style=flat-square)](https://github.com/JzeroM/himi-syncwatch)

</div>

---

## 项目简介

HIMI 是一款基于 **[Flutter](https://flutter.dev)** 的跨平台 **[Emby](https://emby.media)** 客户端，覆盖 Android / Android TV / iOS / Windows / HarmonyOS。

核心是完整的 Emby 媒体库体验：登录、浏览、搜索、收藏、选集、多线路播放，以及高品质解码（HDR 全链路、原生位图字幕 PGS、低延迟起播）。多人异地同步观影、弹幕、液态玻璃 UI 是附加增强功能。

## 核心功能

| 功能 | 说明 |
|------|------|
| **Emby 媒体库** | 登录、浏览、搜索、收藏、详情页、选集、播放线路 |
| **高品质播放** | HDR 全链路、原生位图字幕/PGS、低延迟起播 |
| **多人同步房间** | 房间码 / 二维码加入，播放控制全员同步 |
| **房间双窗协作**（Windows） | 视频窗 + 资源面板窗并排，双向跟随移动/缩放 |
| **弹幕** | [弹弹 Play](https://www.dandanplay.com) 协议兼容（免签名），时间轴匹配 + 本地缓存 |
| **液态玻璃 UI** | 真折射 shader，参数可调（强度/折射率/色散），基于 [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) |
| **TV 模式** | 遥控器焦点导航、顶部横排导航、底栏引擎切换 |
| **多图标集** | 默认 / 艺术 / 玻璃 / 霓虹，运行时切换 |

## 播放引擎

各平台引擎已按实际使用场景收敛，**播放器内只在需要时显示切换控件**：

| 平台 | 引擎 | 播放器内切换 | 说明 |
|------|------|-------------|------|
| **Android 手机** | 仅 **MPV** | ❌ | 原生 Surface + HDR 直出，统一体验 |
| **Android TV** | **MDK / Erika / MPV** | ✅ 底栏 | 不同盒子硬解能力差异大，保留三引擎可选 |
| **HarmonyOS** | 仅 **MPV** | ❌ | XComponent + Vulkan（ohosvk） |
| **Windows** | 仅 **MPV** | ❌ | Qt 独立播放窗 + `vo=gpu-next` HDR 直出（单人带原生窗口按钮） |
| **iOS / iPadOS** | 仅 **Erika** | ❌ | Rust 内核，HDR10 + 原生位图字幕 |

引擎说明：

- **MPV**（[mpv](https://mpv.io)）— 主力内核。原生 Surface / 独立窗口直出，HDR 零拷贝，格式覆盖最广。
- **MDK**（[fvp](https://github.com/wang-bin/fvp)）— 备选，兼容性优先（Flutter 纹理）。
- **Erika**（[Erika](https://github.com/AimesSoft/Erika)）— Rust 内核，iOS 唯一选择。

> 设置 → 播放器配置：单引擎平台只显示对应引擎一页（解码 / HDR / 渲染器选项仍可调），多引擎平台（Android TV）显示分页。

## 平台支持

| 平台 | 最低要求 | 播放内核 | 房间模式 |
|------|---------|---------|---------|
| Android | 8.0（API 26） | MPV | ✅ 原生双窗（视频 + 资源面板） |
| Android TV | 8.0+ | MPV / MDK / Erika | ✅ |
| iOS / iPadOS | 12.0+ | Erika | ✅ |
| Windows x64 | 10+ | MPV（Qt 独立窗口 + HDR 直出） | ✅ 双窗并排 + 双向跟随 |
| HarmonyOS | 6.0+（API 26） | MPV（XComponent + Vulkan） | ✅ 原生双窗 |

补充说明：

- Windows 7 不支持（Flutter 桌面运行时基线限制）。
- HarmonyOS 通过 AppGallery 官方分发测试；DoVi P5/P8 依赖内核 RPU 解析，P7 仅解基础层，不做 FEL。
- macOS / Linux 暂停支持（多人观影 RTM 无对应原生实现，已从发版产物移除）。

## 房间模式

多人同步观影的两种形态：

### 通用（全平台）

- 房间码 / 二维码邀请，房主播放/暂停/进度/倍速全员同步
- 心跳纠偏（<0.3s 不动 / <1s 微调倍速 / 其余 seek）
- 房间内资源面板：季-集折叠、当前集高亮、播报板
- 观众权限：不能播放控制、拖进度、切集、标记片头片尾；可调音量/亮度/弹幕/字幕/音轨/全屏

### Windows 双窗协作

Qt 播放窗（左）+ Flutter 资源面板窗（右）并排：

- **双向跟随**：拖任意一窗，另一窗平移并严格等高；拉伸任一窗高度，两窗始终等高
- 面板宽度保持自身宽度（拖动时不抽动），最小 320 / 视频区最小 480
- 面板高度可自由调高或压矮
- 两窗都出现在任务栏，各有独立图标
- 关闭面板窗 = 退出房间（弹确认）；房主解散时观众端播放窗自动关闭并回首页
- 全屏时覆盖面板窗，退出全屏精确回到并排位置

## 液态玻璃 UI

- 真折射 shader（强度 / 折射率 / 色散可调），基于 [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets)
- 房间面板：黑底轻磨砂 + 微透，头部/分组/集行/播报板均为玻璃卡片
- 关闭「液态玻璃」设置时自动降级为深色实底（保证可读性）
- 资源分组展开：220ms 高度渐变 + 淡入 + 箭头旋转 90°

## 下载安装

前往 [Releases](https://github.com/JzeroM/himi-syncwatch/releases) 下载：

- `himi-sync-<版本>-<abi>.apk` — Android / Android TV（arm64-v8a / armeabi-v7a / x86_64）
- `himi-sync-windows-<版本>-setup.exe` — Windows x64 安装包
- `himi-sync-windows-<版本>.zip` — Windows x64 免安装包
- `himi-sync-ios-unsigned-<版本>.ipa` — iOS（需自签工具安装）

HarmonyOS 不在 GitHub Release 提供 HAP，通过 AppGallery 官方分发测试。

## 快速开始

1. 启动 Emby 服务器，确认可访问。
2. 打开 HIMI，进入 **服务器** 页添加 Emby 地址与账号。
3. 浏览媒体库，点击影片进入详情页即可播放。
4. （可选）多人同步观影：详情页 **创建房间**，邀请好友输入房间码或扫描二维码加入，房主播放后全员自动同步。

## 技术栈

| 类别 | 技术 | 来源 |
|------|------|------|
| 框架 | Flutter 3.47（Dart SDK ^3.6） | https://flutter.dev |
| 状态管理 | Riverpod 2 | https://github.com/rrousselGit/riverpod |
| 播放引擎（主力） | MPV（原生 Surface / Qt 独立窗口，HDR 直出） | https://mpv.io |
| 播放引擎（备选，Android TV） | MDK（fvp 插件封装 [Bilibili MDK](https://github.com/bilibili/MDK)） | https://github.com/wang-bin/fvp |
| 播放引擎（iOS / Android TV） | Erika（Rust 播放内核） | https://github.com/AimesSoft/Erika |
| Windows 播放窗 | Qt Quick + libmpv（本仓库 `native/windows_qt_player`） | https://www.qt.io |
| 实时通信 | Agora RTM 2 | https://github.com/AgoraIO-Extensions/Agora-Flutter-RTM-SDK |
| Windows RTM | himi_windows_rtm 插件（本仓库） | 本地插件 |
| 弹幕 | 弹弹 Play 协议兼容 | https://www.dandanplay.com |
| 网络 | Dio | https://pub.dev/packages/dio |
| UI | liquid_glass_widgets（vendored + 本地补丁） | https://github.com/sdegenaar/liquid_glass_widgets |
| 路由 | GoRouter | https://pub.dev/packages/go_router |

## 项目结构

```
lib/
├── core/          # 应用入口、主题、路由、TV 壳层
├── models/        # 数据模型（AppSettings 等）
├── player_core/   # player_core 迁移层（统一引擎抽象 + 适配器）
├── providers/     # Riverpod providers
├── screens/       # 页面（home/detail/player/room/settings/...）
├── services/      # 业务服务
│   ├── player/    #   多引擎抽象与平台会话（mpv_session_platform 等）
│   ├── danmaku/   #   弹弹 Play 弹幕
│   └── rtm/       #   声网 RTM 房间
├── utils/         # 工具
└── widgets/       # 通用组件

native/
└── windows_qt_player/   # Windows Qt + libmpv 独立播放窗（QML 控件 + 玻璃 UI）

plugins/
├── himi_mpv_core/     # MPV 会话接口（跨平台抽象）
├── himi_mpv_android/  # Android MPV（Surface / 原生 UI）
├── himi_mpv_ohos/     # HarmonyOS MPV（XComponent / 原生 UI）
├── himi_mpv_windows/  # Windows MPV（原生窗口 / HDR 直出）
├── himi_ohos_rtm/     # HarmonyOS RTM（NAPI 直连）
└── himi_windows_rtm/  # Windows RTM
```

## 构建

```bash
# 通用
flutter pub get
flutter build apk --release          # Android
flutter build windows --release      # Windows（另需构建 native/windows_qt_player）
flutter build ios --release          # iOS

# HarmonyOS（需 Flutter-OH SDK + HarmonyOS Command Line Tools）
./scripts/build_ohos_local.sh
```

Windows 的 Qt 播放窗由 `.github/workflows/windows-qt-player.yml` 单独构建，产物打进安装包。

## 测试

```bash
flutter test                     # 全量
flutter test test/player_core/   # 播放器 / 房间 / 原生 UI 架构断言
```

## 许可

本项目为公开项目，欢迎 Star 与 Issue 反馈。
