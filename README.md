<div align="center">

# HIMI Sync Watch

**HIMI — 私密多人异地同步观影客户端**

跨平台 Emby 同步观影 · 弹幕 · 房间 · 多播放引擎 · TV 模式

[![Release](https://img.shields.io/github/v/release/JzeroM/himi-syncwatch?style=flat-square&color=orange)](https://github.com/JzeroM/himi-syncwatch/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/JzeroM/himi-syncwatch/release.yml?branch=main&style=flat-square)](https://github.com/JzeroM/himi-syncwatch/actions)
[![Flutter](https://img.shields.io/badge/Flutter-3.47-blue?style=flat-square&logo=flutter)](https://flutter.dev)
[![License](https://img.shields.io/badge/license-open%20source-green?style=flat-square)](https://github.com/JzeroM/himi-syncwatch)

</div>

---

## 项目简介

HIMI 是一款基于 **[Flutter](https://flutter.dev)** 的私密多人异地同步观影客户端，对接 **[Emby](https://emby.media)** 媒体服务器，支持多端（Android / iOS / Windows / macOS / Linux / Android TV）加入同一房间**帧级同步观影**，并内置**弹幕**、**HDR 原生渲染**与**液态玻璃 UI**。

> 私密：仅受邀好友通过房间码/扫码进入，无公开房间。
> 同步：基于声网 RTM 房间信令，播放/暂停/跳转/进度全端对齐。

## 核心功能

| 功能 | 说明 |
|------|------|
| **Emby 媒体库** | 登录、浏览、搜索、收藏、详情页、选集、播放线路 |
| **多人同步房间** | 房间码 / 二维码扫码加入，播放控制全员同步 |
| **弹幕** | [弹弹 Play](https://www.dandanplay.com) 协议兼容（免签名），时间轴匹配 + 本地缓存 |
| **多播放引擎** | [MDK（fvp）](https://github.com/wang-bin/fvp) / [media_kit](https://github.com/media-kit/media-kit)（libmpv）/ [Erika](https://github.com/AimesSoft/Erika)（Rust 内核，HDR10 + 原生位图字幕/PGS） |
| **HDR 路由** | 按内容 HDR 与平台自动路由最优引擎（v1.1.222 起全自动） |
| **TV 模式** | Android TV 遥控器焦点导航、顶部横排导航、仅 MDK 引擎 |
| **液态玻璃 UI** | 真折射 shader，参数可调（强度/折射率/色散），基于 [liquid_glass_widgets](https://github.com/sdegenaar/liquid_glass_widgets) |
| **多图标集** | 默认 / 艺术 / 玻璃 / 霓虹，运行时切换 |
| **局域网助手** | Emby 局域网内网穿透配置辅助 |

## 平台支持

| 平台 | 最低要求 | 播放引擎 |
|------|---------|----------|
| Android | 8.0（API 26） | MDK / Erika |
| Android TV | 8.0+ | MDK（TV 模式锁定） |
| iOS / iPadOS | 12.0+ | MDK / Erika |
| macOS | 10.15+ | MDK / Erika |
| Windows | 10+（64 位） | MDK / media_kit |
| Linux | 现代发行版 | MDK |

> Windows 7 不支持（Flutter 桌面运行时基线限制）。

## 播放引擎自动路由

从 v1.1.222 起，播放器引擎**全自动路由**，无需手动选择：

- **TV 模式** → 恒 MDK
- **非 HDR 内容** → 恒 MDK（省电稳定）
- **HDR + Android/iOS** → Erika（extended-linear scRGB / EDR 协商）
- **HDR + Windows** → media_kit（libmpv）
- **HDR + macOS/Linux/Web** → MDK 兜底

## 下载安装

前往 [Releases](https://github.com/JzeroM/himi-syncwatch/releases) 下载对应平台安装包：

- `app-*-release.apk` — Android / Android TV
- `himi-sync-windows.zip` — Windows x64
- `himi-sync-macos.zip` — macOS（未签名，需 `xattr -cr` 或右键打开）
- `himi-sync-linux.zip` — Linux x64
- `himi-sync-ios-unsigned.ipa` — iOS（需自签工具安装）

## 快速开始

1. 启动 Emby 服务器，确认局域网或公网可访问。
2. 打开 HIMI，进入 **服务器** 页添加 Emby 地址与账号。
3. 点击任意影片 → 详情页 → **创建房间**（或加入好友房间）。
4. 邀请好友输入房间码或扫描二维码加入。
5. 房主播放，全员自动同步。

## 技术栈

| 类别 | 技术 | 来源 |
|------|------|------|
| 框架 | Flutter 3.47（Dart SDK ^3.6） | https://flutter.dev |
| 状态管理 | Riverpod 2 | https://github.com/rrousselGit/riverpod |
| 播放引擎（Android/iOS/macOS） | MDK（fvp 插件封装 [Bilibili MDK](https://github.com/bilibili/MDK)） | https://github.com/wang-bin/fvp |
| 播放引擎（Windows HDR） | media_kit（libmpv） | https://github.com/media-kit/media-kit |
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
│   ├── player/    #   多引擎抽象 + 自动路由
│   ├── danmaku/   #   弹弹 Play 弹幕
│   ├── rtm/       #   声网 RTM 房间
│   └── lan_config/#   局域网配置
├── utils/         # 工具
└── widgets/       # 通用组件
```

## 开发与测试

```bash
# 依赖
flutter pub get

# 静态分析
flutter analyze

# 测试（1475+ 用例）
flutter test

# 运行
flutter run -d windows   # 或 android / ios / macos / linux
```

## 版本历史（精选）

- **v1.1.222** — 引擎全自动路由、房间模式路由、TV seek 修复、MDK 低延迟起播、确定性释放
- **v1.1.221** — Windows 移除 Erika、media_kit 字幕可调、切引擎进度恢复
- **v1.1.220** — 修复引擎热切换闪退与 TrueHD 音频输出
- **v1.1.202–219** — 引擎抽象、Erika 弹幕/字幕/outputMode、CI 全平台打包

完整变更见 [Releases](https://github.com/JzeroM/himi-syncwatch/releases)。

## 许可

本项目为公开项目，欢迎 Star 与 Issue 反馈。
