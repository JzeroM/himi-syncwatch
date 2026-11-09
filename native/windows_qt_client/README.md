# HimiSync Windows 播放器窗口（Qt Quick + libmpv）

**范围**：只做 Windows 播放器窗口。**不**接管 RTM、不接管房间同步——
那些全部留在 Flutter 进程（Flutter 是唯一逻辑权威）。

## 为什么要这个窗口

Flutter 在 Windows 上有两个绕不过去的限制：

| 限制 | 后果 |
|---|---|
| 不支持 Windows PlatformView（`platform_views.dart` 无 windows 分支） | 无法把原生视图嵌进 Flutter 布局 |
| Flutter 窗口用 DirectComposition 呈现，原生子 HWND 不在其合成树里 | mpv 的 `surface` 路径被整体遮挡 → 灰屏 |
| mpv 走 Flutter 纹理（`VideoController`） | 崩在 `flutter_windows.dll` `0xc0000005 @ 0x1551f` |

实测唯一可行的路径是：**自建顶层窗口 + mpv `wid` 直出**（真 HDR 输出）。

## 为什么是「子 HWND」而不是「画进 QML」

想让 QML 覆盖视频，就得把 mpv 渲染进 QML 场景（`mpv_render_context`）。
但 **libmpv 的 render API 只有 OpenGL 与软件后端，没有 D3D11**：

```
OpenGL FBO 路径 → mpv 转成 SDR RGBA 交给 Qt → HDR 直出丢失
```

所以保 HDR 就必须让 mpv 自己拥有 HWND：

```
Qt 主窗口（不透明）
└─ 原生子 HWND  ← mpv `wid` + vo=gpu-next + d3d11-output-mode=window
```

**代价**：原生子 HWND 永远画在 QML 之上（Win32 硬规则），所以播放器
UI 必须用**独立透明窗口**叠加（655 之后做），不能直接写在主窗 QML 里。

## 654：spike（当前状态）

本轮只验证**一个**致命假设：

> mpv 用 `wid` 直出到 Qt 创建的 HWND 时，HDR 是否还在？

刻意保持最小：不接 Flutter、不接 IPC、不接 RTM，片源从命令行传入。

### 构建

```powershell
# 需要 Qt 6.8+ 与 libmpv dev 包（含 include/mpv/client.h）
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
      -DCMAKE_PREFIX_PATH="C:/Qt/6.8.3/msvc2022_64" `
      -DLIBMPV_DIR="C:/libmpv"
cmake --build build --config Release --parallel
```

`LIBMPV_DIR` 应含：

```
include/mpv/client.h
libmpv.dll.a        （或 libmpv.lib）
libmpv-2.dll
```

### 运行

```powershell
build/Release/himi_qt_win.exe "https://example.com/hdr-sample.mkv"
build/Release/himi_qt_win.exe --no-hdr "https://..."   # 以 SDR 启动，做 A/B 对比
```

### 按键

| 键 | 作用 |
|---|---|
| `空格` | 暂停 / 播放 |
| `F` / 双击 | 全屏切换 |
| `H` | 切换 HDR 开关（A/B 对比） |
| `S` | 打印验证步骤 |
| `Esc` | 退出全屏 / 关闭窗口 |

## 怎么判断 HDR 到底有没有直出

标题栏会实时显示一行摘要：

```
HIMI Qt Spike — HDR10 ✓ (BT.2020/PQ) | 片源 bt.2020/pq | 显示器 HDR 开 | HDR请求:开 | 播放
HIMI Qt Spike — SDR ✗ (BT.709)       | 片源 bt.2020/pq | 显示器 HDR 开 | HDR请求:开 | 播放
```

判据来自 **`video-out-params`**（不是 `video-params`）：

| 属性 | 含义 |
|---|---|
| `video-params` | **片源**参数。HDR 片源永远是 pq/bt.2020，用它判断会把「tone map 成 SDR」误判成功 |
| `video-out-params` | mpv 真正交给 swapchain 的参数。**直出 = pq/bt.2020；tone map = bt.1886/bt.709** |

辅助判据（截图法，最可靠）：HDR 直出时按 `Win+Shift+S` 截图会**明显过曝**
（屏幕 1000nit 被压到 100nit）；降成 SDR 时截图与屏幕基本一致。

## 后续路线

| 轮次 | 内容 |
|---|---|
| 655 | 透明覆盖窗口 + QML 底栏 + 鼠标命中/穿透 |
| 656 | 命名管道 IPC + `QtPlayerAdapter` + 进程生命周期 |
| 657 | 顶栏 + 面板（选集/音轨/字幕/倍速） |
| 658 | QML 弹幕渲染 |
| 659 | Windows 引擎矩阵收敛为 `[mpv]` + 清理旧 Win32 窗口代码 |
| 660 | CI 集成（windeployqt + 打进 release zip） |

## 授权注意

Qt 6 开源版是 **LGPLv3**。必须**动态链接** + `windeployqt` 收集 DLL +
附授权声明；**静态链接会让整个程序变成 GPL**。

## 历史

- M0：Qt Quick 客户端骨架
- M1：Agora RTM C++ SDK 接入 —— **654 移除**（RTM 留在 Flutter）
