<div align="center">

# HIMI Sync Watch

**HIMI — 跨平台 Emby 客户端**

全平台 Emby 媒体库客户端 · 多播放引擎 · 弹幕 · 多人同步观影 · TV 模式

[![Release](https://img.shields.io/github/v/release/JzeroM/himi-syncwatch?style=flat-square&color=orange)](https://github.com/JzeroM/himi-syncwatch/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/JzeroM/himi-syncwatch/release.yml?branch=main&style=flat-square)](https://github.com/JzeroM/himi-syncwatch/actions)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-blue?style=flat-square&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-open%20source-green?style=flat-square)](https://github.com/JzeroM/himi-syncwatch)

</div>

---

## 项目简介

HIMI 本质是一款基于 **[Flutter](https://flutter.dev)** 的跨平台 **[Emby](https://emby.media)** 客户端，覆盖 Android / iOS / Windows / Android TV（HarmonyOS 规划中）。核心能力是完整的 Emby 媒体库体验：登录、浏览、搜索、收藏、选集、多线路播放，以及本地化高品质解码（多播放引擎、HDR 全链路、原生位图字幕/PGS、低延迟起播）。多人异地同步观影房间、弹幕、液态玻璃 UI 等仅是附加增强功能。

## 核心功能

| 功能 | 说明 |
|------|------|
| **Emby 媒体库** | 登录、浏览、搜索、收藏、详情页、选集、播放线路 |
| **高品质播放** | 三播放引擎、HDR 全链路、原生位图字幕/PGS、低延迟起播 |
| **多人同步房间** | 房间码 / 二维码扫码加入，播放控制全员同步（可选功能） |
| **弹幕** | [弹弹 Play](https://www.dandanplay.com) 协议兼容（免签名），时间轴匹配 + 本地缓存 |
| **多播放引擎** | [MDK（fvp）](https://github.com/wang-bin/fvp) / [media_kit](https://github.com/media-kit/media-kit)（libmpv）/ [Erika](https://github.com/AimesSoft/Erika)（Rust 内核，HDR10 + 原生位图字幕/PGS） |
| **TV 模式** | Android TV 遥控器焦点导航、顶部横排导航，支持 MDK / Erika / Media Kit |
| **液态玻璃 UI** | 真折射 shader，参数可调（强度/折射率/色散），基于 [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) |
| **多图标集** | 默认 / 艺术 / 玻璃 / 霓虹，运行时切换 |

## 平台支持

| 平台 | 最低要求 | 默认引擎 | 可选引擎 |
|------|---------|----------|----------|
| Android | 8.0（API 26） | MDK | Erika / Media Kit（libmpv） |
| Android TV | 8.0+ | MDK | Erika / Media Kit（libmpv） |
| iOS / iPadOS | 12.0+ | Erika | — |
| Windows x64 | 10+ | MDK | Erika / Media Kit（libmpv） |
| HarmonyOS | 规划中 | — | Erika / MDK（规划中） |

> 平台内核能力与默认值对齐 [NipaPlay 平台能力矩阵](https://github.com/AimesSoft/NipaPlay-Reload/blob/main/Documentation/platform-matrix.md)。Windows 发布包附带完整 libmpv。
> Windows 7 不支持（Flutter 桌面运行时基线限制）。
> macOS / Linux 暂停支持（多人观影 RTM 无对应原生实现，已从发版产物中移除）。

## 下载安装

前往 [Releases](https://github.com/JzeroM/himi-syncwatch/releases) 下载对应平台安装包：

- `himi-sync-<版本>-<abi>.apk` — Android / Android TV（arm64-v8a / armeabi-v7a / x86_64）
- `himi-sync-windows-<版本>-setup.exe` — Windows x64 安装包
- `himi-sync-windows-<版本>.zip` — Windows x64 免安装包
- `himi-sync-ios-unsigned-<版本>.ipa` — iOS（需自签工具安装）

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
| 播放引擎（Android/iOS） | MDK（fvp 插件封装 [Bilibili MDK](https://github.com/bilibili/MDK)） | https://github.com/wang-bin/fvp |
| 播放引擎（Windows） | media_kit（libmpv） | https://github.com/media-kit/media-kit |
| 播放引擎（手机 HDR/字幕） | Erika（Rust 播放内核） | https://github.com/AimesSoft/Erika |
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
├── providers/     # Riverpod providers
├── screens/       # 页面（home/detail/player/room/settings/...）
├── services/      # 业务服务
│   ├── player/    #   多引擎抽象
│   ├── danmaku/   #   弹弹 Play 弹幕
│   └── rtm/       #   声网 RTM 房间
├── utils/         # 工具
└── widgets/       # 通用组件
```

## 许可

本项目为公开项目，欢迎 Star 与 Issue 反馈。
