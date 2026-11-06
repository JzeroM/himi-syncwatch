# HIMI 双端原生播放器详细计划书

> 状态：**仅计划，不实施**。等待用户在新会话中明确要求后再执行。
> 适用平台：HarmonyOS（手机触控）+ Android（手机 + TV）。
> 不包含：Windows、iOS、鸿蒙 TV。
> 版本基线：`1.5.3+530`。正式开工后每个交付批次递增 build 号，保持 `+N` 单调。

---

## 0. 执行约束

1. 新会话开工前先读本文件，不要重新做选型调研；关键结论已核实。
2. 本轮**不做** Windows / iOS 改造，不影响现有三平台。
3. Texture 模式必须保持现有 Flutter UI，不得回归。
4. 原生 UI 只负责显示、输入、本地进度插值；播放业务与权威状态仍在 Dart。
5. 不改动 `deps-mirror`、不删除任何 release 依赖。
6. 每个阶段完成后必须补测试并跑通，再进入下一阶段。

---

## 1. 背景与已确认事实

### 1.1 鸿蒙

- 鸿蒙 MPV 会话已经由 `plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvOhosPlugin.ets` 持有，`MpvLib` 的 `create → setOption → initialize → attachSurface` 链路可用。
- 视频渲染依赖 `XComponent` 提供的真实 `OHNativeWindow`，mpv 的 `ohosvk` 后端不接受 Flutter 纹理。
- 当前 Surface 模式仍走 Flutter PlatformView（`HimiMpvPlatformView` / `HimiMpvSurfaceView`）。最近一次修复让 `surfaceFactory` 返回 `PlatformViewSurface`，但真机仍出现白屏，说明 PlatformView 合成链路不可靠。
- 改用**全屏原生子窗口**可以彻底绕开 PlatformView 合成：
  - `HimiMpvOhosPlugin` 实现 `AbilityAware`，通过 `FlutterManager.getInstance().getWindowStage(ability)` 拿到 `WindowStage`。
  - `@ohos/flutter_ohos` 已导出 `AbilityAware`、`FlutterManager`。
  - `WindowStage.createSubWindow()` / `Window.setUIContent()` 可用。
- 新增页面路由**不需要重新生成 `resources.index`**：
  - 索引文件只记录 `main_pages.json` 的路径；
  - 路由内容在独立的 `main_pages.json` 文件中；
  - 只需同时更新 `ohos/entry/.../main_pages.json` 与 `ohos/template/resources/base/profile/main_pages.json`。
- `ohos_pack.sh` 从本次 Flutter 构建产物复制 `ets/modules.abc`，因此新页面会随构建进入 HAP。

### 1.2 Android

- Android MPV 由 Dart 的 media_kit 驱动，`wid` 使用 `HimiMpvSurfaceView` 的 Java Surface 全局引用。
- `HimiMpvAndroidPlugin` 通过 `himi_mpv_android/surface` EventChannel 回传 surface handle。
- 当前 SurfaceView 位于 Flutter 视图树内，真机黑屏，已确认是层级/遮挡问题。
- 全屏原生 Dialog 的独立窗口可以绕开 Flutter 视图层级，与鸿蒙子窗口思路一致。
- 现有插件已具备 JNI surface 转换能力，可复用到 Dialog 内。

### 1.3 共享

- `MpvSession` 抽象已存在：`plugins/himi_mpv_core/lib/src/mpv_session.dart`。
- `MpvSessionPlatform` 已按平台分派：`lib/services/player/mpv_session_platform.dart`。
- `MpvPlayerAdapter` 已具备 Surface/Texture 决策、HDR gating、轮询与诊断字段。
- 退出/切内核/切输出路径时必须销毁原生宿主，避免悬浮窗口残留。

---

## 2. 目标与非目标

### 2.1 目标

- 鸿蒙 Surface 模式：全屏原生子窗口 + ArkUI 控件 + XComponent，SDR/HDR 正常出画面。
- Android Surface 模式：全屏原生 Dialog + SurfaceView + Compose，SDR/HDR 正常出画面。
- 双端原生 UI 覆盖播放页全部控件、面板、弹幕、房间同步、截图、调试面板。
- Android 同时适配手机触控与 TV 遥控器焦点导航，保留现有 Flutter TV 全部按键语义。
- Texture 模式完全保留现有 Flutter 播放 UI。

### 2.2 非目标

- 鸿蒙 TV / 遥控器。
- Windows / iOS 原生播放器。
- 重写播放业务、房间同步、弹幕协议。
- 改动 mpv 内核或 libmpv 构建脚本（除非原生播放器验证发现必须）。

---

## 3. 总体架构

```text
Flutter/Dart（权威状态）
├── 播放业务 / 房间 / 弹幕 / 设置 / HDR 决策
├── Texture 模式：现有 Flutter UI
└── Surface 模式：隐藏 Flutter 播放 UI
        ↕ MethodChannel + EventChannel
原生播放器宿主
├── Android：MainActivity → 全屏 Dialog → SurfaceView + Compose
└── HarmonyOS：Plugin → WindowStage 子窗口 → XComponent + ArkUI
```

### 3.1 通道

| 通道 | 方向 | 用途 |
|---|---|---|
| `himi_mpv` | Dart → 鸿蒙 | 现有 mpv 控制 |
| `himi_mpv/events` | 鸿蒙 → Dart | 现有 mpv 事件 |
| `himi_mpv/native_ui` | 双向 | 鸿蒙原生 UI 状态与命令 |
| `himi_mpv_android` | Dart → Android 插件 | 现有 Surface/HDR 查询 |
| `himi_mpv_android/surface` | Android → Dart | 现有 Surface handle |
| `himi_native_player` | 双向 | Android 原生 UI 状态与命令 |

### 3.2 状态所有权

- Dart 是唯一权威状态源。
- 原生 UI 每次收到快照后覆盖本地状态，并对 `positionMs` 做本地插值：
  - 播放中：`position + (now - snapshotAt) * speed`
  - 暂停：保持不变
- 原生命令先乐观更新 UI，再发回 Dart；Dart 应用后推回权威快照。

### 3.3 快照频率

- 周期性：250–500ms（复用现有 500ms 轮询）。
- 事件驱动：播放/暂停、seek、切换轨道、切换集数、HDR 状态变化时立即推送。
- 弹幕列表：按分片推送，避免每次全量。

---

## 4. 共享协议

### 4.1 `NativePlayerState`

建议文件：`lib/services/player/native/native_player_state.dart`

```dart
class NativePlayerState {
  // 输出与 HDR
  final String engine;              // mpv / mdk / erika / media_kit
  final String videoOutputRequested;// surface / texture
  final String videoOutputActual;   // surface / texture
  final bool nativeSurface;
  final int textureId;
  final bool hdrOutput;
  final bool displayHdr;
  final String targetTrc;           // pq / hlg / auto
  final String? voConfigured;
  final String? currentVo;
  final String? hwdecCurrent;

  // Surface 诊断
  final bool surfaceAttached;
  final String? surfaceId;
  final String? surfaceError;
  final int surfaceWidth;
  final int surfaceHeight;

  // 播放
  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final bool paused;
  final bool buffering;
  final bool ended;
  final double volume;              // 0..1
  final double speed;

  // 媒体
  final String? title;
  final String? mediaTitle;
  final String? videoParams;
  final String? audioParams;
  final List<NativeTrack> tracks;
  final int selectedAudioId;
  final int selectedSubtitleId;
  final double subtitleDelayMs;
  final NativeSubtitleStyle subtitleStyle;

  // 选集 / 版本
  final List<NativeEpisode> episodes;
  final int currentEpisodeIndex;
  final List<NativeVersion> versions;
  final int currentVersionIndex;

  // 弹幕
  final bool danmakuEnabled;
  final double danmakuOpacity;
  final double danmakuFontSize;
  final double danmakuSpeed;
  final String danmakuArea;         // scroll / top / bottom
  final List<String> danmakuBlockWords;
  final List<NativeDanmakuItem> danmakuItems;

  // 房间
  final String? roomCode;
  final bool isHost;
  final List<NativeRoomMember> roomMembers;
  final List<NativeRoomChat> roomChat;
  final String roomSyncState;

  // 其他
  final int? segmentIntroEndMs;
  final int? segmentOutroStartMs;
  final bool locked;
  final bool tvMode;
  final bool canControl;
  final List<String> debugLines;
}
```

### 4.2 `NativePlayerCommand`

```dart
sealed class NativePlayerCommand {}

class TogglePlay extends NativePlayerCommand {}
class SeekTo extends NativePlayerCommand { final int positionMs; }
class SeekRelative extends NativePlayerCommand { final int deltaMs; }
class SetVolume extends NativePlayerCommand { final double volume; }
class SetSpeed extends NativePlayerCommand { final double speed; }
class SelectAudio extends NativePlayerCommand { final int id; }
class SelectSubtitle extends NativePlayerCommand { final int id; }
class AddSubtitle extends NativePlayerCommand { final String url; final String title; final String lang; }
class SetSubtitleStyle extends NativePlayerCommand { final NativeSubtitleStyle style; }
class SetSubtitleDelay extends NativePlayerCommand { final double delayMs; }
class SelectEpisode extends NativePlayerCommand { final int index; }
class SelectVersion extends NativePlayerCommand { final int index; }
class SwitchEngine extends NativePlayerCommand { final String engine; }
class SetDecodeMode extends NativePlayerCommand { final String mode; }
class AdjustDisplay extends NativePlayerCommand { final String key; final double value; }
class ToggleDanmaku extends NativePlayerCommand {}
class UpdateDanmakuSettings extends NativePlayerCommand { final Map<String, Object?> values; }
class ToggleRoomSync extends NativePlayerCommand {}
class SendRoomChat extends NativePlayerCommand { final String text; }
class TakeScreenshot extends NativePlayerCommand {}
class ToggleDebug extends NativePlayerCommand {}
class SetSegmentMark extends NativePlayerCommand { final String kind; final int positionMs; }
class RequestBack extends NativePlayerCommand {}
class RequestExit extends NativePlayerCommand {}
```

### 4.3 Dart 控制器

建议文件：`lib/services/player/native/native_player_controller.dart`

职责：

- `open(platform, initialState)` / `update(state)` / `close()`。
- 监听 `himi_mpv/native_ui/commands` 与 `himi_native_player/commands`。
- 把命令转成 `PlayerScreen` / `MpvPlayerAdapter` 可执行的动作。
- 防抖：状态推送至少间隔 200ms，但暂停/seek/切换内容立即推送。
- 幂等：重复 open/close 不产生多个窗口。

---

## 5. HarmonyOS 详细设计

### 5.1 文件清单

新增：

| 文件 | 作用 |
|---|---|
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/HimiMpvNativeHost.ets` | 单例桥：会话引用、状态快照、surface 绑定、命令回调 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerState.ets` | `@ObservedV2` + `@Trace` 状态模型 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/HimiNativePlayerView.ets` | 全屏 ArkUI 播放器（XComponent + 控件 + 面板 + 弹幕） |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerControls.ets` | 顶部/底部控制条 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerPanels.ets` | 音轨/字幕/选集/版本/内核/解码/显示/设置面板 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativeDanmakuLayer.ets` | Canvas 弹幕 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativeDebugPanel.ets` | 调试面板 |
| `ohos/entry/src/main/ets/pages/NativePlayer.ets` | 薄页面，只渲染 HAR 导出的视图 |

修改：

| 文件 | 改动 |
|---|---|
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvOhosPlugin.ets` | 实现 `AbilityAware`；子窗口生命周期；`himi_mpv/native_ui`；创建/销毁原生宿主；surface 桥接 |
| `plugins/himi_mpv_ohos/ohos/index.ets` | 导出 `HimiNativePlayerView`、`HimiMpvNativeHost`、状态类型 |
| `ohos/entry/src/main/resources/base/profile/main_pages.json` | 增加 `pages/NativePlayer` |
| `ohos/template/resources/base/profile/main_pages.json` | 增加 `pages/NativePlayer`（打包用） |
| `ohos/entry/oh-package.json5` | 如构建未自动注入，显式加入 `himi_mpv_ohos` |
| `plugins/himi_mpv_ohos/lib/himi_mpv_ohos.dart` | `create(nativeUi: true)`、状态推送、命令流、`close` |
| `plugins/himi_mpv_core/lib/src/mpv_session.dart` | 工厂增加 `nativeUi` 参数 |
| `lib/services/player/mpv_player_adapter.dart` | Surface 模式创建会话时启用原生 UI；状态推送 |
| `lib/screens/player/player_screen.dart` | Surface 模式不再挂 PlatformView；隐藏 Flutter 播放层；关闭时恢复 |

### 5.2 子窗口生命周期

1. Dart 决定 Surface 模式，调用 `MpvSessionPlatform.create(nativeSurface: true, nativeUi: true)`。
2. `HimiMpvPlayer.create` 调插件 `create`，插件创建并初始化 mpv 会话。
3. 插件创建子窗口：
   - `const win = await windowStage.createSubWindow('himi_native_player')`
   - `await win.setWindowLayoutFullScreen(true)`
   - `await win.setWindowSystemBarEnable([])`
   - `await win.setWindowBackgroundColor('#000000')`
   - `await win.setUIContent('pages/NativePlayer', storage)`
   - `win.showWindow()`
4. 页面内 `XComponent` 创建 surface，回调 `HimiMpvNativeHost.instance.attachSurface(surfaceId)`。
5. 插件把 surfaceId 交给现有 `tryBindSurface()`；若媒体 URL 已缓存，则自动加载。
6. 关闭流程：
   - Dart 调 `HimiMpvPlayer.closeNativeUi()` 或 `dispose()`。
   - 插件 `win.destroyWindow()`，清空引用。
   - 恢复主窗口系统栏：`getMainWindow().setWindowSystemBarEnable(['status', 'navigation'])`。

### 5.3 生命周期与窗口事件

- `AbilityAware.onAttachedToAbility(binding)`：保存 `UIAbility`，取 `WindowStage`。
- `onDetachedFromAbility()`：销毁子窗口，清空引用。
- `windowStage.on('windowStageEvent')`：
  - HIDDEN → 子窗口隐藏，通知 Dart 暂停（可选）。
  - SHOWN → 按播放状态恢复子窗口。
- 子窗口 `on('windowSizeChange')`：更新 XComponent 尺寸；通知 mpv。
- 旋转：系统旋转后重新计算全屏尺寸；XComponent 自适应父容器。
- 多窗口/分屏：检测到非全屏时关闭原生播放器并回退 Flutter UI（或提示）。

### 5.4 页面与资源

- `ohos/entry/src/main/ets/pages/NativePlayer.ets`：

```ts
import { HimiNativePlayerView } from 'himi_mpv_ohos';

@Entry
@Component
struct NativePlayer {
  build() {
    HimiNativePlayerView();
  }

  onBackPress(): boolean {
    // 交给原生宿主处理：先关面板 → 再隐藏控件 → 再退出
    return HimiMpvNativeHost.handleBack();
  }
}
```

- `main_pages.json` 两个位置都要加：

```json
{"src":["pages/Index","pages/NativePlayer"]}
```

- 不需要重新生成 `resources.index`；已核实索引只记录路径。
- 打包脚本无需改结构与版本逻辑；继续使用 `scripts/build_ohos_local.sh`。

### 5.5 Surface 绑定

- `HimiNativePlayerView` 内使用 `XComponentController` 子类或复用 `MpvXComponentController`。
- `onSurfaceCreated` → `HimiMpvNativeHost.attachSurface(surfaceId)`。
- `onSurfaceChanged` → 记录 `surfaceWidth/surfaceHeight`，用于诊断与 mpv 尺寸同步。
- `onSurfaceDestroyed` → `HimiMpvNativeHost.detachSurface()`。
- 插件内部复用现有 `handleSurfaceCreated/Changed/Destroyed`，避免重复实现。

### 5.6 原生 UI 范围（手机触控）

- 顶部：返回、标题、时钟、房间状态。
- 底部：播放/暂停、上一集/下一集、进度条、时间、音量、倍速、音轨、字幕、弹幕、锁定、旋转/全屏、选集、版本、内核、解码、显示、设置、截图、调试。
- 面板：
  - 音轨
  - 字幕轨 / 外挂字幕
  - 字幕样式 / 延迟
  - 倍速
  - 选集 / 版本
  - 内核切换
  - 解码模式
  - 显示调节
  - 弹幕设置 / 屏蔽词
  - 片头片尾标记
  - 房间成员 / 聊天 / 同步
- 手势：点屏显隐、双击播放/暂停、左右拖动 seek、上下调亮度/音量、长按倍速。
- 自动隐藏、锁定后禁止误触。
- 返回：先关面板 → 再隐藏控件 → 再请求退出。

### 5.7 诊断字段

调试面板显示：

- 请求路径 / 实际路径
- `nativeSurface` / `textureId`
- `surfaceAttached` / `surfaceId` / `surfaceError`
- `surfaceWidth x surfaceHeight`
- `vo-configured` / `current-vo` / `hwdec-current`
- `target-trc` / `hdrOutput` / `displayHdr`
- `gpu-context`

验收：Surface 模式 `textureId=0`、`surfaceAttached=true`、`vo-configured=yes`、HDR 内容 `target-trc=pq|hlg`。

### 5.8 弹幕

- 使用 ArkUI `Canvas` + `CanvasRenderingContext2D`。
- 维护轨道分配、滚动/顶部/底部三种模式。
- 从 Dart 接收时间轴分片；本地按 `positionMs` 调度。
- 支持透明度、字号、速度、显示区域、屏蔽词。

---

## 6. Android 详细设计

### 6.1 文件清单

新增：

| 文件 | 作用 |
|---|---|
| `android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerHost.kt` | 全屏 Dialog、Window flags、生命周期 |
| `.../nativeplayer/NativePlayerScreen.kt` | Compose 控件层 + `AndroidView(HimiMpvSurfaceView)` |
| `.../nativeplayer/NativePlayerState.kt` | Android 侧状态模型 |
| `.../nativeplayer/NativePlayerCommands.kt` | 命令解析 |
| `.../nativeplayer/NativeDanmakuLayer.kt` | Compose Canvas 弹幕 |
| `.../nativeplayer/NativePlayerPanels.kt` | 面板 |
| `.../nativeplayer/NativeDebugPanel.kt` | 调试面板 |
| `.../nativeplayer/TvKeyRouter.kt` | TV 遥控器按键与焦点 |
| `lib/services/player/native/android_native_player.dart` | `himi_native_player` 通道 |

修改：

| 文件 | 改动 |
|---|---|
| `android/app/src/main/kotlin/com/himi/syncwatch/MainActivity.kt` | 注册 `himi_native_player` 通道与原生宿主 |
| `android/app/build.gradle` | 开启 Compose，加入 Compose 依赖 |
| `android/settings.gradle` | 加入 Compose compiler plugin（Kotlin 2.1.0） |
| `plugins/himi_mpv_android/.../HimiMpvSurfaceView.kt` | 增加 Dialog 模式构造参数，避免 `setZOrderMediaOverlay` 副作用 |
| `plugins/himi_mpv_android/lib/himi_mpv_android.dart` | surface handle 变化时重建播放器；`nativeUi` 参数 |
| `lib/services/player/mpv_session_platform.dart` | 传 `nativeUi` |
| `lib/services/player/mpv_player_adapter.dart` | 状态推送、命令处理 |
| `lib/screens/player/player_screen.dart` | Surface 模式隐藏 Flutter 播放层 |

### 6.2 全屏 Dialog

- 使用 `Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)`。
- `window.setLayout(MATCH_PARENT, MATCH_PARENT)`。
- `WindowCompat.setDecorFitsSystemWindows(window, false)`。
- `FLAG_KEEP_SCREEN_ON`、`FLAG_FULLSCREEN`。
- `setCanceledOnTouchOutside(false)`。
- 内容：`ComposeView` + `AndroidView(factory = { HimiMpvSurfaceView(it, viewId, useMediaOverlay = false) })`。
- 退出：`dialog.dismiss()` 并通知 Dart。

### 6.3 Surface handle 顺序

正常路径：

1. Dart 决定 Surface 模式。
2. `HimiMpvAndroidSession.create(nativeSurface: true, nativeUi: true)`。
3. `_start()` 先订阅 `himi_mpv_android/surface`，再调用 `himi_native_player.open`。
4. 原生宿主创建 Dialog 与 SurfaceView。
5. `HimiMpvSurfaceView` 创建 Surface → 插件 EventChannel 回传 handle。
6. Dart 收到 handle → 用该 handle 作为 `wid` 创建 media_kit 播放器。
7. `prepare` 打开媒体（暂停态），随后由 Dart 推状态给原生 UI。

异常路径：

- 旋转/窗口重建导致 handle 变化：
  - 记录当前 position；
  - 销毁旧 player；
  - 用新 handle 重建；
  - 恢复 position 与播放状态。
- Dialog 提前关闭：
  - 停止并释放 player；
  - 清除 pending URL；
  - 回到 Flutter UI 或退出播放页。

### 6.4 Compose 依赖

`android/app/build.gradle`：

```gradle
plugins {
    id "org.jetbrains.kotlin.plugin.compose"
}

android {
    buildFeatures { compose true }
}

dependencies {
    implementation platform("androidx.compose:compose-bom:2024.12.01")
    implementation "androidx.compose.ui:ui"
    implementation "androidx.compose.foundation:foundation"
    implementation "androidx.compose.material3:material3"
    implementation "androidx.activity:activity-compose:1.9.3"
    implementation "androidx.lifecycle:lifecycle-runtime-compose:2.8.7"
}
```

`android/settings.gradle`：

```gradle
plugins {
    id "org.jetbrains.kotlin.plugin.compose" version "2.1.0" apply false
}
```

注意：原生 UI 放 app 模块，避免与插件自身 AGP/Kotlin 版本冲突；插件继续只提供 Surface/JNI。

### 6.5 原生 UI 范围

与鸿蒙同一套功能清单，另加：

- TV 遥控器焦点导航
- TV 专属布局与过扫描安全区
- 手机手势

### 6.6 TV 按键语义（必须与现有 Flutter 一致）

- 方向键移动焦点，OK/Enter/Select 确认。
- 媒体播放/暂停键。
- 隐藏态左右键 ±10 秒。
- 进度条单击 ±5 秒，长按每步 ±10 秒。
- 滑杆按下定向到播放按钮。
- 返回：关面板 → 隐藏控件 → 2 秒内二次确认退出。
- 左右组 hop、焦点恢复、自动隐藏计时。
- 焦点描边、overscan 安全区。

实现建议：

- Compose 根节点 `focusRequester` + `focusable` + `onPreviewKeyEvent`。
- Dialog `setOnKeyListener` 处理 BACK / MEDIA 键。
- `TvKeyRouter` 统一映射按键到命令，避免散落。
- 焦点状态用 `FocusRequester` 链式管理，面板关闭后恢复到来源控件。

### 6.7 HDR

- 沿用现有 Android 会话配置：`vo=gpu-next`、`gpu-api=opengl`、`gpu-context=android`。
- HDR 内容：`target-colorspace-hint=yes`、`target-prim=bt.2020`、`target-trc=pq|hlg`、`hdr-compute-peak=auto`、`tone-mapping=clip`。
- Dialog 的 Surface 是正常窗口 Surface，需验证 HDR metadata 是否正常下发。
- 若 `gpu-next` 在 Dialog 下异常，回退 `vo=gpu` 并记录。
- 调试面板显示 `current-vo`、`hwdec-current`、`target-trc`、实际 HDR 状态。

---

## 7. Dart 集成设计

### 7.1 门控

```text
启用原生 UI 的条件：
- 引擎 == mpv
- 实际输出路径 == surface
- 平台 == Android 或 HarmonyOS
- 设置中未关闭「原生播放器」
```

不满足则保持 Flutter UI / Texture。

### 7.2 `MpvPlayerAdapter`

- 新增字段：
  - `nativeUiEnabled`
  - `nativeSurfaceAttached`
  - `nativeSurfaceSize`
- `prepare()`：
  - 决定 `nativeSurface`；
  - 创建会话时传 `nativeUi`；
  - 会话创建成功且 `player.usesNativeSurface == true` 时启用原生 UI；
  - 若请求 Surface 但返回 Texture，记录并回退，不打开原生 UI。
- `_applyPolledState()`：
  - 更新诊断字段；
  - 生成 `NativePlayerState`；
  - 调 `NativePlayerController.update()`。
- 命令处理：
  - `togglePlay` / `seek` / `volume` / `speed` / 轨道 / 选集 / 版本等；
  - 复用现有 adapter 方法；
  - 执行后立即推送状态。

### 7.3 `PlayerScreen`

- `_usesMpvNativeSurface` 为 true 且原生 UI 启用时：
  - 不挂 `HimiMpvSurfaceView` / `HimiMpvAndroidSurfaceView`；
  - 视频区域显示透明占位；
  - Flutter 控件层隐藏或完全透传；
  - 打开原生宿主。
- 退出、切内核、切 Texture、页面销毁时关闭原生宿主。
- 房间/弹幕/截图等回调通过控制器转发。
- 保留现有 TV 按键逻辑作为 Texture 模式路径。

### 7.4 状态映射

- 现有 `MpvPollResult` + adapter 字段 → `NativePlayerState`。
- 现有 `track-list` JSON → `List<NativeTrack>`。
- 现有设置 Provider → 弹幕、字幕、显示、内核等。
- 房间状态 → `NativeRoomMember/Chat`。

---

## 8. 分阶段执行

### Phase 0：共享协议与门控

- [x] 新增 `NativePlayerState` / `NativePlayerCommand` / `NativePlayerController`。
- [x] `MpvSession` 工厂增加 `nativeUi`。
- [x] 门控逻辑与日志。
- [x] 单元测试：序列化、门控、命令路由（45 项）。
- [x] 验收：Texture 模式无变化；Surface 模式不打开原生 UI（阶段 0 仅门控）。

### Phase 1：双端最小原生壳（一起做）

**鸿蒙**

- [x] 插件实现 `AbilityAware`。
- [x] 创建/销毁全屏子窗口。
- [x] 新增 `NativePlayer` 页面与 `main_pages.json`。
- [x] XComponent + surface 绑定。
- [x] 最小控件：播放/暂停、进度、时间、返回、诊断行。
- [x] ArkTS 编译通过（hvigor `CompileArkTS`，随 HAP 构建验证）。
- [x] `himi_mpv/native_ui` 状态与命令。

**Android**

- [x] 全屏 Dialog + SurfaceView 最小壳。
  > 实现说明：用**经典 View**（`FrameLayout` + `SeekBar` + `TextView`）而非
  > Compose。原因：Compose 需新增 compose-bom / compiler 插件，本机与 CI
  > 都缺少可验证的构建回路；经典 View 零新增依赖、与现有 AGP/Kotlin 配置
  > 兼容，且能用 `android.jar` 在本机编译校验。Dart 仍是唯一权威状态源，
  > 后续换实现不影响协议。
  > 代码：`android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/`
  > （`AndroidNativePlayerState` / `NativePlayerScreenView` /
  > `AndroidNativePlayerHost` / `AndroidNativePlayerChannel`）。
- [x] `himi_native_player` 通道。
- [x] Surface handle 顺序与重建。
  > `HimiMpvAndroidSession` 记住地址与播放点，`surfaceDestroyed` 后清空
  > player，新 surface 到达时用同一地址 + 当前位置重建并保持暂停态。
- [x] 最小控件：播放/暂停、进度、时间、返回、诊断行。
- [x] 状态层纯 JVM 单测（`android/app/src/test`，11 项，本机 kotlinc 实测）。

**验收**

- [ ] 鸿蒙 SDR/HDR 均有画面，`surfaceAttached=true`、`vo-configured=yes`。
- [ ] Android SDR/HDR 均有画面，无黑屏。
- [ ] 播放/暂停/seek/返回可用。
- [ ] Texture 模式回归正常。
- [ ] 输出 signed HAP + signed APK。

**已完成的本地验证（无真机/无 Android SDK 环境下能做的部分）**

- [x] 鸿蒙 ArkTS 编译通过（hvigor `CompileArkTS`），signed HAP 构建并
  `hap-sign-tool verify-app` 通过。
- [x] Android Kotlin 全量编译通过（`android.jar` API 36 + Flutter 桩）。
- [x] Android 原生播放器状态层 11 项 JVM 单测通过。

### Phase 2.5：控制层重画（照 Flutter 观感）+ 第二批面板

本轮目标：把原生控制层从「文本按钮壳」重画为与 Flutter 播放页一致的
手机横屏 / TV 两套排布，并补齐第二批面板。

**单一来源机制（防止三端漂移）**

| 资产 | 单一来源 | 校验测试 |
|---|---|---|
| 图标码点（44 个） | `tool/native_icons.json` | `test/native_player_icons_test.dart` |
| 视觉常量 | `lib/services/player/native/native_player_theme.dart` | `test/native_player_theme_test.dart` |
| 控制层状态字段 | `lib/services/player/native/native_player_state.dart` | `test/services/native_player_state_test.dart` + `AndroidNativePlayerStateTest.kt` |

一致性测试做三层比对：Dart 常量 ↔ `Icons.xxx.codePoint`（保证与 Flutter
同款）↔ Kotlin `NPTheme` / ArkTS 源码字面量（保证原生真用同一套数值）。

**鸿蒙字体打包陷阱（踩过一次，务必按此放置）**

图标字体 `MaterialIcons-Regular.otf`（1.6MB）必须放在
`ohos/entry/src/main/resources/rawfile/`，两处原因缺一不可：

1. `$rawfile('MaterialIcons-Regular.otf')` 只解析到 **entry 模块**的
   rawfile；插件 HAR 的 `resources/` 不会合并进应用包；
2. `scripts/ohos_pack.sh` 重建 HAP 时按**白名单**拷贝 rawfile 项，目前只拷
   `flutter_assets` / `buildinfo.json5` / `MaterialIcons-Regular.otf`。
   新增 rawfile 资源时若忘了同步加白名单，资源不会进包。

曾经的 bug：字体放在插件 HAR 的 rawfile → 既不合并、又没进白名单 →
HAP 里根本没有字体 → `EntryAbility` 注册失败 → 原生控制层所有图标渲染成
空框。`test/native_player_icons_test.dart` 已加两条断言锁死（字体位于
entry rawfile、打包脚本含字体拷贝），改路径或删白名单会直接测试失败。

Android 侧字体位于 `android/app/src/main/assets/fonts/`，由
`NativePlayerIcons.typeface()` 用 `Typeface.createFromAsset` 加载。

**协议扩展（Phase 2.5）**

- `NativePlayerState` 新增 18 字段：`logoUrl` / `networkSpeedText` /
  `clockFormat` / `glassUi` / `engineLabel` / `engineOptions` / `videoFit` /
  `decodeMode` / `subtitleScale` / `subtitleMarginY` /
  `subtitleDelayEnabled` / `subtitleStyleDisabled` / `segmentEnabled` /
  `showDebug` / `isRoom` / `canScreenshot` / `audioStreamCount` /
  `subtitleStreamCount`。
- 新命令：`toggleLock` / `cycleVideoFit` / `toggleOrientation` /
  `clearSegmentMark`；`switchEngine` 接入路由（内核热切换）。
- `NativePlayerUiExtras` 承载低频快照，`PlayerScreen._syncNativePanelData`
  在锁定、网速采样、设置变更、字幕样式、画面比例、弹幕开关、片头片尾、
  内核切换等时机整体重推。

**视觉规格（已从 Flutter 源码 + 截图确认）**

- 手机顶栏：返回 / 标题 16 w600 / 网速 12 white70 / 倍速（speed20 +
  `1.0x`）/ 内核胶囊 / 字幕样式胶囊（tune18）/ 解码胶囊（memory18）/
  画面比例 22 / 转屏 22。
- 手机底栏：Logo 240×44；时间 12 white70（56/78 格）；滑杆 track6 /
  thumb8 / `#6366F1`；锁钮 22；播放组精确居中（28/36/28）；右侧图标 24、
  间距 20（弹幕 / 版本 HQ+n / 字幕+n / 音轨+n / 选集+n），角标 9px
  `#6366F1` 圆底。
- TV 顶栏：返回 / 标题 / 网速 / 内核胶囊 / 时钟（右 12、100×48、13
  white70）。
- TV 底栏：Logo；进度条焦点环 3px `#C1C2FE` + blur14 / spread1.5；播放组
  置左；右侧增加显示调节与倍速，隐藏锁、转屏、画面比例、解码入口。
- 右侧浮层：宽 `clamp(0.42×屏宽, 260, 320)`、`right:12`、
  `top = safeTop+48`、`bottom = 116+safeBottom`、圆角 16、着色
  `0x1F1A1D23`、rim `0x4DFFFFFF`；选中 `#6366F1` + 加粗 + 对勾占 18px 槽；
  标题 15 加粗、选项行 14、padding h16 v12。
- 显示调节：字幕 3 行（大小 0.5–3.0/0.05、位置 0–200/2、延迟
  -5000–5000/100）+ 弹幕 3 行（速度 0.5–2.0/0.05、大小 0.5–2.0/0.05、
  透明度 0.1–1.0/0.05）；行 = 标签 44 / 滑杆 / 数值 48、padding h16 v10；
  段标题 11 white38。
- 解码模式：180 宽、`#1E1E2E`、圆角 8；标题 13 加粗 + 当前值 12
  `#A5B4FC`；3 行单选。
- 片头片尾：居中 360 玻璃卡圆角 18，标题 16 w600 + 当前位置 12 white54，
  两行（icon22、标题14、提示11、chevron18）；已有标记走**原生**二次确认
  （更新 / 清除 / 取消）——Flutter `showDialog` 在原生双窗之上不可见。

**Android 特殊性**：控件层与视频层是两个独立窗口，无法跨窗口真模糊，
用 tint + rim + 圆角近似；鸿蒙用 `backgroundBlurStyle` 真模糊。

### Phase 2：鸿蒙完整原生控件

- [x] 顶部/底部控制条（手机横屏 / TV 两套排布，图标走 MaterialIcons 字体）。
- [x] 倍速/锁定/自动隐藏（音量经命令回传 Flutter 处理）。
- [x] 音轨/字幕（外挂字幕走 Flutter `addSubtitle`）。
- [x] 字幕样式/延迟（「显示调节」面板：字幕 3 滑杆）。
- [x] 选集/版本。
- [x] 内核/解码/显示调节。
- [ ] 播放页设置（房间/调试面板等 Phase 5 字段）。
- [ ] 截图。
- [x] 片头片尾标记（居中玻璃卡 + 原生二次确认）。
- [ ] 手机手势（单独一轮）。
- [ ] 验收：手机触控全功能可用（需真机）。

### Phase 2.6：与 Flutter 观感逐项对齐（1.5.5+562）

> 起因：用户三张截图 + 要求「整体排查，交付效果与 Flutter 播放器一致、
> 双端一致」。逐项对照 Flutter 播放页修正。

**截图暴露的三个缺陷**

- [x] A1 角标：改正圆（`BadgeCircleDrawable`，边长按实测文本宽 + 4dp）
      + 整条父链 `clipChildren=false`（旧实现 19×14 椭圆且右半被切）。
- [x] A2 玻璃面板：`drawRefractedSample` 改为面板屏幕矩形 → 位图源矩形
      映射（旧实现整帧铺满 → 面板显示「缩小版全视频」）。
- [x] A3 竖屏画布：surface 事件带 width/height → Dart 设
      `android-surface-size`（旧实现从不设 → mpv 恒按初始尺寸合成被拉伸）。
- [x] A3 竖屏控件：新增 `ScaleDownBox`（测量级等价 `FittedBox(scaleDown)`）
      替换只收窄间距的 `applyGroupGap`；顶栏标题保底宽 56dp。
- [x] 缩放态触摸热区补偿到 ≥44dp（只扩热区不改视觉）。

**与 Flutter 的视觉/语义偏差**

- [x] B1 TV 时钟：安卓 `clockWrap` 从未挂到顶栏（死代码）→ 已挂载；
      鸿蒙改为仅 TV 显示（旧实现非房间模式恒显示）。
- [x] B2 时钟格式：双端支持 off/12h/24h（鸿蒙旧实现写死 24h）。
- [x] B3 房间「资源面板」按钮：新增 `toggleResourcePanel` 命令
      （旧实现发 `requestBack` → 点一下直接退出播放页）。
- [x] B4 底栏渐变 alpha 0xCC→0xD9（Flutter 0.85）。
- [x] B5 顶/底栏安全区：安卓读 `WindowInsets`/`DisplayCutout`，鸿蒙读
      `getWindowAvoidArea`，喂给控件层避让刘海与手势条。
- [x] B6 鸿蒙自动隐藏 4000ms→5000ms（Flutter 5s）。
- [x] B7 进度条未播段 white@0.16（0x29）统一双端。
- [x] B8 缓冲圈颜色 WHITE_70→accent；鸿蒙补上缓冲圈所需状态字段。
- [x] B9 移除安卓 HDR 徽标（Flutter 控制层无此元素）。
- [x] B10 解码面板：改 180dp 独立 popover（对齐 Flutter `DecodeModePanel`
      的位置/宽度/radio 行样式），删掉死代码 `decodePopoverOpen` 分支；
      档位标签「自动」→「智能」（对齐 Flutter 播放页）。
- [x] B11 面板几何叠加安全区（`safeTop+48` / `116+safeBottom`）。
- [x] B12 显示调节滑杆补 track6/thumb16 玻璃观（鸿蒙旧用系统默认滑杆）。
- [x] B13 鸿蒙长按进度条 → 片头片尾卡加 `tvMode && segmentEnabled` 条件
      （旧实现无条件绑定，手机长按会误弹）。
- [x] B14 鸿蒙锁定态底栏：对齐 Flutter `_buildLockOnlyControls`
      （补渐变底 + 锁钮在时间数显列内居中）。
- [x] B15 顶/底栏内边距统一走 `BAR_PAD_*` 常量。

**跨语言一致性**

- [x] Dart `NativePlayerTheme` 补 `white12`/`accent30`/`barGradientSolid`/
      `barBottomSolid`/`barPad*`/`titleMinWidth`（唯一真相源）。
- [x] 新增 `test/native_player_layout_test.dart`（布局语义 + 显隐谓词 +
      面板几何 + 双端源码静态断言）。
- [x] 扩展 `test/native_player_theme_test.dart`（新增常量三端比对）。

### Phase 2.7：真机回归修复（1.5.8+588）

> 起因：鸿蒙「正常播放还一直转圈」、安卓双击手势图标反了、跳过片头/片尾
> 时机与残留、角标三端不一致、安卓选集封面加载慢、解码面板单选圈错图标。

- [x] 鸿蒙 `pollState` 补 `width`/`height`/`estimated-vf-fps`/
      `frame-drop-count`；适配器 `hasVideoFrame` 作为「首帧已出」第二判据
      （`video-params` 是 NODE 属性、`getPropertyString` 常返空）。
- [x] 缓冲位：`positionMs > 0` 也算在出帧（鸿蒙 `demuxer-cache-time` 常读不到）。
- [x] 安卓双击手势图标方向对齐 Flutter `playPauseHintIcon`。
- [x] 跳过提示：`shouldKeepSkipPrompt` 每 tick 校验（离开片段立刻收起）+
      首帧就绪门禁（`MpvPlayerAdapter.firstFrameReady`）。
- [x] 角标三端统一分档：1~2 位 15dp / 3 位 19dp / 4 位起 24dp
      （`NativePlayerTheme.badgeSizeFor`）。
- [x] 安卓选集封面：4 线程优先级队列 + 磁盘 LRU（64MB）+ 目标宽二次采样 +
      关面板取消队列（`NativeLogoLoader` 重做）。
- [x] 解码面板单选圈：`ICON_RADIO_BUTTON_CHECKED/UNCHECKED = 0xE503/0xE504`
      （旧 0xE838/0xE836 实为 `cancel_sharp`）；图标→文字 8dp；每行含末行
      0.5dp 分隔线；鸿蒙改用图标字体（不再 `●/○`）。
- [x] 手动片头/片尾范围约束（全平台全播放器）：片头结束点 ≤ 10%、
      片尾开始点 ≥ 70%（`lib/utils/segment_mark_rules.dart` 权威校验 +
      安卓/鸿蒙手势与二次确认前置校验 + 设置页说明）。

### Phase 2.8：弹幕重写 + 竖屏标题 + 角标圆底 + 鸿蒙转圈根因（1.5.9+589）

> 起因：安卓 MPV 弹幕与鸿蒙此前遇到的是同一批问题（跳行/中途消失/速度
> 不对）；手机竖屏顶栏标题把尾簇挤出屏；安卓角标只有白字没有靛蓝圆底；
> 鸿蒙正常播放仍显示加载器。

- [x] 安卓 `DanmakuLayerView` 重写：`laneOf` 行号绑定生命周期（禁全量重
      分配）、`flying` 飞行缓存、`currentPositionMs × speed` 倍速外推、
      底部 `(lane+1)`、顶/底冲突表（禁轮转）、行容量扣边距、固定弹幕首尾
      10% 淡入淡出、`measureCache` 文本宽缓存、`onSizeChanged` 重排、
      无活跃弹幕不重绘、w500 + 黑 54% blur3 描影（禁粗描边）。
- [x] 弹幕屏蔽链进原生（三端共用）：`NativePlayerUiExtras` 新增
      `danmakuBlockTop/Bottom/Words`，`_buildDanmakuWindow` 按
      `DanmakuTimeline._filter` 同序过滤 + `timeMs` 升序。
- [x] 鸿蒙弹幕行容量变化也清 `laneOf`（转屏后不越界）。
- [x] 手机竖屏不显示顶栏标题（`PlayerScreen.showTopBarTitle`）；安卓/鸿蒙
      原生早已按 `portrait` 隐藏。
- [x] 安卓角标改系统 `GradientDrawable(OVAL)` + `NPTheme.BADGE_BG`：自绘
      Drawable 的 `draw()` 依赖 `bounds`，`setBackground` 与首次
      `onSizeChanged` 时序不保证 → bounds 恒空 → 圆底完全不画（真机「只有
      白色数字」）。Flutter 角标同时改固定 `width==height`（只给
      `constraints` 下限会被两位数撑成椭圆）。
- [x] 鸿蒙转圈根因：`build()` 里 `this.state().showLoading` 是宿主普通字段
      （不在 ArkUI 观察链上），该 if 节点也不在 epoch 重建块里 → 条件只求值
      一次，起播前的 `true` 永久保留。改为 `@State showLoading` 镜像 +
      build 直读。
- [x] Dart 转圈兜底：`hasVideoFrame` 增 `estimated-vf-fps > 0` 第三判据；
      新增 3s 看门狗（在播且位置已推进即强制收起，不依赖任何视频属性）。

### Phase 2.9：弹幕行分配重建 + 角标 + 四端二维码 + 原生房间资源面板（1.5.10+590）

> 起因：安卓弹幕「只显示最顶一行、一条条冒出来」；角标被裁 + 空/0 显示
> 空白圆点；保存二维码全平台报错；安卓房间模式一播放就全屏、资源面板展
> 不开。

- [x] 弹幕行分配：`assignLanes` 每帧按「当前在场且已分配」的条目重建三组
      冲突表（`fill(0)` + 按 `laneOf` 回填 `max(occupancy)`），再给新条目
      分配。旧实现把 `avail[]` 当跨帧持久状态，离场条目占用不释放 → 新条目
      找不到空行 → `lane=-1` 全部丢弃（只显示最顶一行）。安卓 + 鸿蒙同修。
- [x] 角标空/0：`badgeButton` 创建时 `visibility = GONE`（吸收
      `badgeLastText` 短路歧义——HashMap 缺键取 null 与值为 null 无法区分，
      导致 `visibility` 从未设成 GONE → 空白蓝圆点）；新增
      `badgeText(count)` 统一入口；`applyState` 加
      `toIntOrNull()?.takeIf { it > 0 }` 兜底。
- [x] 角标裁剪：`badgeLayoutParams` 的 `marginEnd` 从 `-dp(2)` 改 0，角标
      完整落在 32dp 命中框内，不再依赖父级 `clipChildren`（旧实现只关了根 /
      topBar / bottomBar，中间层 `buttonRow`、`trailingGroup` 仍会裁）。
- [x] 二维码保存/分享四端统一（`QrExportService`）：Android 走 MediaStore
      （API 29+，`RELATIVE_PATH=DCIM/Himi` + `IS_PENDING`）/ 直写（≤28）；
      iOS 走 `PHPhotoLibrary`；鸿蒙走 `photoAccessHelper.createAsset`；
      Windows 走 FilePicker / 剪贴板。删除两处
      `/storage/emulated/0/DCIM` 直写与「鸿蒙暂不支持」拦截。
- [x] 二维码截图可靠性：`RoomShareDialog` 自持 `qrKey` 并暴露
      `_captureBytes()`，调用方不再依赖跨层传入的 key 时序；加 2s 超时
      兜底（`RepaintBoundary.toImage` 极端情况可能永不返回）。
- [x] 原生房间资源面板（安卓 + 鸿蒙，完整移植）：`NativePlayerUiExtras`
      下发 `roomCode`/`isHost`/`onlineUserCount`/`audienceName`/
      `resourceGroups`/`broadcasts`/`resourcePanelOpen`；新增命令
      `toggleResourceGroup`/`toggleResourceSeason`/`removeResourceEpisode`/
      `openResourceSearch`；`ToggleResourcePanel` 从「只打日志」改为真正
      切换 `_showPanel`。
- [x] 面板展开时视频区收窄：安卓收窄 surface 窗宽（`onVideoInsetRight`）；
      鸿蒙 `XComponent` 宽度 `calc(100% - 320vp)`。否则视频被面板盖住。

### Phase 2.10：手势方向修正 + 房间面板推送（1.5.11+591）

> 起因：安卓 MPV 手势音量/亮度方向反了（上滑减、下滑加）；向上滑时进度条
> 会变；房间模式资源面板全空、播报 (0)、在线人数 0。

- [x] 手势方向：安卓 `onScroll` 的 `distanceY` **正值 = 手指上滑**，旧实现
      写成 `-distanceY`（误以为需与 Flutter 的「正值=下滑」对齐）→ 方向完全
      反了。改为直接相加（上滑增大）。对照 Flutter
      `_brightness - delta/600`（primaryDelta 上滑为负 → 减去后增大）。
- [x] 手势方向锁：旧实现每帧用 `|dx| > |dy|` 重判方向，斜向拖动会在横/纵
      之间来回切换 → 上滑误触发 seek。新增 `dragAxis` 一次性定轴
      （0 未定 / 1 横向 / 2 纵向），`ACTION_DOWN` 复位，`onFling` 与
      `ACTION_UP` 提交都加 `AXIS_HORIZONTAL` 守卫。安卓 + 鸿蒙同修。
- [x] 在线人数：RTM presence 未同步时返回 0 会覆盖初始值 1。新增纯函数
      `PlayerScreen.resolveOnlineCount`（`rtmCount > 0` 采用权威值，否则保留
      当前值且至少 1）。
- [x] 房间面板推送时机（真机「资源面板全空、播报 0」根因）：
      `_addBroadcastMessage` / `_refreshOnlineCount` / `_applyRoomResources`
      都补 `_syncNativePanelData()`。此前播报只更新 `_broadcastVersion`
      （Flutter 内部通知），原生永远收不到。
- [x] `ToggleRoomSync` 命令接线（此前解析后无 case 分支，静默丢弃）。
- [x] 安卓资源面板头部标题补 `ellipsize`，与 Flutter
      `Expanded(资源) | 搜索 | 人数 | 角色` 布局一致。

### Phase 2.11：房间资源面板逐项复刻 Flutter（1.5.12+592）

> 起因：真机房间模式面板全空（「资源」下面一片空白、播报 (0)），且与 Flutter
> `_buildResourcePanel` 差距大。

- [x] **根因：签名初值碰撞**。`roomPanelSig` / `roomBroadcastSig` 初值为 `""`，
  与「零分组/零播报」产生的签名 `""` 相等 → `buildRoomPanelList` 与播报重建
  **从未执行** → 连「暂无资源」「暂无消息」空态都不渲染，列表区纯空白。
  改用哨兵 `ROOM_SIG_UNBUILT`（`"\u0000unbuilt"`）。
- [x] 头部逐项对齐：搜索显隐改 `isHost && !paused`（旧只看 `isHost` 只调
  alpha）；人数胶囊改 `people` 图标字体 12 + 数字 11（旧用 `👥` emoji）；
  胶囊底 white12 圆角 8 padding h6 v2；角色徽章房主 accent / 观众红。
- [x] 分组计数 white54 12sp（旧 WHITE_70 11sp）。
- [x] 季标题：左 24 / 右 12 / 上下 6、white54 16 图标、`第N季` white70 12
  w500、`(N集)` white38 11；且**只在剧集组显示**（旧按 `seasons.size > 1`）。
- [x] 电影组直接列 `seasons.first.episodes`（旧套季循环）。
- [x] 集行：当前集加**左 3dp accent 竖条**（旧只有底色）；缩略图圆角 4 +
  无图时灰底 `movie` 图标；播放/暂停图标随状态；删除 `close` 18 white24。
- [x] 播报板：标题加 `campaign` 图标 12；新消息自动 `fullScroll` 到底；
  空态居中。
- [x] 列表 `padding vertical 4`（对齐 Flutter `ListView`）。
- [x] 鸿蒙 `RoomPanel` 同款复刻：补季行/集行/删除/播放图标/当前集左边框/
  电影组直接展开/人数胶囊图标/播报标题图标/空态居中。

### Phase 2.12：原生播放器与资源面板真双窗口分栏（1.5.13+593）

> 起因：真机房间模式「播放器全屏、资源面板盖在播放器上」，与 Flutter
> `Row(Expanded(video), SizedBox(320))` 的分屏差距大。

- [x] **根因：surface 窗宽度从未真正生效**。`applyVideoInsetRight` 只改
  `window.attributes.width`，而 `applyFullscreen()` 已
  `setLayout(MATCH_PARENT, MATCH_PARENT)`——后者覆盖前者，实际仍全屏。
  改为 **每次都调 `window.setLayout(targetW, MATCH_PARENT)`**（写 attributes
  并立即 apply），并去掉 `if (lp.width == targetW) return` 短路（`show()`
  后可能被重置，必须重申）。
- [x] 控件层同步分栏（`applyVideoSplit`）：左区（`屏宽 - inset`）承载
  手势层/弹幕/顶栏/底栏/面板遮罩/解码 popover/片头片尾卡；右区资源面板改
  「贴左区右缘」（`leftMargin = videoW`）而非 `Gravity.END` 贴屏幕右缘。
- [x] 转屏/尺寸变化后按新屏宽重算分栏（`onSizeChanged` 里重置并重应用）。
- [x] 鸿蒙 `XComponent` 宽度修正：`layoutWeight(1)` 与 `width('100%')` 同时
  设置时 **width 优先**、layoutWeight 失效 → 视频不收窄。改为二选一
  （展开 `width('auto') + layoutWeight(1)`，收起 `width('100%')`）。

### Phase 2.13：资源面板保留非空值 + 竖屏上下结构 + fit 重同步（1.5.14+594）

> 起因：真机「一播放资源面板就空」；「全屏控件失效」；「手动竖屏应该是
> 上下结构」。

- [x] **资源面板一播放就空**：观众端起播路径
  `_playFromUrl` → `_loadEpisodeStream` 会先重置 `_episodes` 再重建，中间
  存在「重置后、重建前」窗口——此时 `_resourceGroups` 为空，推送下去原生
  收到空列表；原生签名已记为「空」，之后要等签名再变一次才重建 → 面板
  长时间空白。Dart 侧新增 `_lastNonEmptyResourceGroups` 保留上次非空值，
  `_nativeResourceGroups()` 空时返回缓存；`clearNativeResourceCache()` 供
  换片/退出房间时明确清空。
- [x] **竖屏上下结构**：安卓 `applyVideoSplit` 增加 `portrait` 分支——视频区
  高 = `屏高 - 280dp`、面板贴下缘全宽；宿主 `applyVideoInsetRight` 按方向
  收窄高/宽（竖屏收窄高度）。新增 `NPTheme.ROOM_PANEL_HEIGHT = 280`
  （对齐 Flutter `SizedBox(height: 280)`）。
- [x] **鸿蒙竖屏**：`build()` 用 `if/else` 双分支（横屏 `Row`、竖屏
  `Column`），视频层+手势层抽成 `VideoStack` @Builder 共用；
  `RoomPanelSlot` 按 `portrait` 切 320vp / 280vp。
  不用 `Flex({direction})`：ArkTS 对三元表达式推断方向枚举报
  `arkts-no-any-unknown`（构建实测）。
- [x] **全屏控件（fit）失效**：`applyVideoFit` 只写 mpv 属性，但 letterbox
  依赖 surface **当前尺寸**；分栏 `setLayout` 异步生效 → 属性已改、尺寸
  还没到，画面按旧尺寸裁切。新增
  `MpvPlayerAdapter.refreshSurfaceAfterFit()`，`_cycleVideoFit` 调用它补
  一次 surface 重同步。

### Phase 2.14：修复房间面板数据链路（1.5.15+595）

> 起因：真机「资源面板还是空」「显示/隐藏资源面板控件点击没反应」「横屏
> 弹出面板被资源面板遮挡」「竖屏底栏控件消失」。

- [x] **数据链路断裂（前三轮一直没修好的真正原因）**：
  `onlineUserCount` / `audienceName` / `resourceGroups` / `broadcasts` /
  `resourcePanelOpen` 此前**只存在于 `NativePlayerUiExtras`**，从未进入
  `NativePlayerState`——构造时漏传、`toJson` 未序列化、`fromJson` 未解析。
  原生 `optJSONArray("resourceGroups")` 永远 null、
  `optBoolean("resourcePanelOpen", true)` 永远默认 true → 面板永远空白、
  开关点了也没变化。
  修法：五层全补（`NativePlayerState` 构造参数 + 字段 + `toJson` +
  `fromJson` + `copyWith` + `==`/`hashCode`，以及
  `MpvPlayerAdapter._buildNativePlayerState()` 传值）。
- [x] **横屏弹出面板被遮挡**：`panelWidthDp()` 按全屏宽算 0.42，分栏后
  父级只有 `videoW` → 面板过宽、右缘被裁。改为按
  `w - lastVideoSplitInsetPx`（视频区宽）计算。
- [x] **竖屏底栏消失**：旧实现 `height = WRAP_CONTENT` +
  `topMargin = videoH - BAR_PAD_TOP - (TRANSPORT_PLAY+8)`——底栏真实高度
  ≈100dp，topMargin 只减 44dp → 底部超出 `videoH` 被裁。改为
  `height = videoH` + `gravity = BOTTOM`，不依赖高度估算。

### Phase 2.15：底栏定位 / 当前集边框 / 搜索条件 / 弹出面板宽度（1.5.16+596）

> 起因：真机「进度条和底栏跑到屏幕顶部」「资源列表当前集前面多一条竖条」
> 「搜索控件应只在暂停时显示」「控件弹出面板没显示」。

- [x] **底栏跑到顶部**：595 把 `bottomBar.height` 设成 `MATCH_PARENT`
  （横屏分支）——底栏内部是 `LinearLayout.VERTICAL`，撑满高度后内容从
  **顶部**开始排，进度条行与控件行跑到屏幕最上方、与顶栏重叠。
  修法：底栏**不改 height**（`WRAP_CONTENT` + `Gravity.BOTTOM` 天然贴底），
  只改 `width` 与 `gravity`，横竖屏一致。
- [x] **当前集竖条**：旧实现用独立 `View` 占 `dp(3)` 布局宽——视觉上
  「多一条竖条」且把右侧内容整体右推。Flutter 用
  `Border(left: BorderSide(accent, 3))` 画在容器内边缘、不占宽。
  修法：安卓改 `foreground = leftAccentDivider()` 自绘（只涂左侧 3dp）；
  鸿蒙改行容器 `.border({ width: { left: 3 }, color: SEL_COLOR })`。
- [x] **搜索控件条件（595 写反了）**：595 写成 `isHost && !paused`
  （播放中显示），而 Flutter 是
  `_roomData != null && _isHost && _player.state != AdapterPlaybackState.playing`
  ——播放中**不**显示。原生侧 `paused == (state == paused || stopped)`，
  等价条件为 `isHost && paused`。真机截图回归：房主播放中仍显示放大镜。
- [x] **弹出面板没显示**：595 在 `applyVideoSplit` 里把
  `panelContainer.width` 改成 `videoW`（整个视频区宽），与
  `renderOverlays()` 的 `lp(panelWidthDp(), MATCH_PARENT)` 冲突 → 面板
  撑满视频区，看起来像「没显示」。修法：`applyVideoSplit` 不动面板宽度
  （由 `panelWidthDp()` 统一决定，它已按 `videoW` 计算），只限制遮罩范围。

### Phase 2.16：弹出面板分栏定位 / 竖屏底栏 / 搜索后重开 / 锁定态底栏（1.5.17+597）

> 起因：真机「弹出面板不显示在视频区内、只让视频区变黑」「竖屏后进度条
> 和底栏没有」「搜索后添加资源、播回来当前暂停的视频黑屏」「锁定态去
> 资源栏切资源后锁控件消失」。

- [x] **弹出面板只让视频区变黑（面板不见）**：`panelContainer` 用
  `Gravity.END + marginEnd`，父级是**根 FrameLayout（全屏宽）**；分栏后
  面板贴在「全屏右缘」——正好落在资源面板下方被完全盖住，而遮罩（黑
  45%）盖住视频区 → 只看到「视频区变黑」。
  修法：改 `Gravity.START + leftMargin = videoAreaWidth() - 面板宽 - 12dp`，
  贴**视频区**右缘；高度也限制在视频区内（`videoAreaHeight() - 上下避让`）。
  `applyVideoSplit` 同步 `leftMargin`（不动 width，避免与 `renderOverlays`
  冲突）。解码 popover（180dp）同理。
- [x] **片头片尾卡相对全屏居中**：`Gravity.CENTER` 是相对根容器，
  竖屏分栏后卡片落到资源面板区；且 width 被撑成 videoW。
  修法：抽 `positionVideoCenteredCard()`——`START|TOP` + 精确 leftMargin，
  垂直方向 `post{}` 读实测高度修正。
- [x] **竖屏进度条/底栏没有**：`bottomBar` 的 LayoutParams 挂在根
  FrameLayout（全屏高），`Gravity.BOTTOM` 贴**全屏底缘**——竖屏分栏后
  资源面板占底部 280dp，底栏整个落在面板下方被盖住。
  修法：竖屏**分栏时**改 `Gravity.TOP + topMargin = videoH - 底栏高`；
  高度未知，先按 `BOTTOM_BAR_ESTIMATED_HEIGHT = 100dp` 估值，再在
  `post{}` 里用实测 `bottomBar.height` 修正（零误差）。未分栏仍走
  `Gravity.BOTTOM`（videoH == 屏高，不必偏移）。鸿蒙用
  `.translate({ y: -ROOM_PANEL_HEIGHT })` 同理。
- [x] **搜索后黑屏**：`_openRoomResourceSearchFromNative()` 里
  `closeNativeUi()` 关掉宿主，回来后只调 `_syncNativePanelData()`，
  **没有任何路径重开原生 UI**（`_openNativeUiIfNeeded()` 只在 `prepare()`
  里调用）→ 原生窗口没了、Flutter 视频层又因 `nativeUiActive` 曾是 true
  而未挂载 → 纯黑。
  修法：`MpvPlayerAdapter.reopenNativeUi()`（清残留控制器 → 走已验证的
  `nativeUiActive=true → open → refreshSurface()` 路径），并在搜索返回后
  `await` 调用。重开前多等 250ms 让 Flutter 平台视图先卸载，避免两个
  SurfaceView 并存抢绑定（v1.5.4 安卓黑屏根因）。
- [x] **锁定态切资源后锁控件消失**：`applyState()` 锁定分支只设
  `leadingGroup.visibility = VISIBLE`，**没设 `bottomBar` 自身**——它由
  `setControlsVisible()` 控制；切资源会走 `closePanel()` →
  `renderOverlays()`，自动隐藏计时器（5s）也可能已把 `controlsVisible`
  置 false，之后无路径显回底栏。
  修法：锁定分支强制 `bottomBar.visibility = VISIBLE`；
  `setControlsVisible()` / `scheduleAutoHide()` / `tick()` 在锁定态
  直接跳过隐藏（锁定态本就该常显，对齐 Flutter `_buildLockOnlyControls`）。

### Phase 2.17：资源行播放图标就地刷新 + 鸿蒙 597 回归回滚（1.5.18+598）

> 起因：真机「资源列表里每个资源前面的播放/暂停图标和实际状态不匹配，
> 暂停了图标也一样该变成暂停」；以及「鸿蒙现在播放控件全消失了」。

- [x] **鸿蒙控件全消失（597 引入的回归）**：597 在**已有**
  `position({y:'100%'}) + markAnchor({x:'0%', y:'100%'})` 的节点上又加
  `.translate({ y: -280 })`。`position` 百分比基准是父容器高度、
  `markAnchor` 再按百分比偏移，本已依赖「Stack 高度已确定」；再叠一个
  绘制层平移 → **布局与绘制两套坐标系打架**，底栏被推到屏幕外，顶栏/
  底栏全部消失（真机「一进入就消失」）。
  触发条件 `roomPanelVisible() && portrait` 只在房间模式 + 竖屏为真，
  非房间模式恒为 0，所以前几轮没暴露。
  修法：**整体回滚鸿蒙 597 改动**（两处 `.translate` + `bottomInset`
  传参与声明），恢复到 596 真机验证过的状态（`git diff 4207239` 为空）。
  **教训**：`.translate` 是全项目首次使用，且与项目明令禁用的
  `position/markAnchor` 百分比定位叠加——不能在没有真机验证的情况下
  「顺手同步三端」。鸿蒙竖屏底栏若仍需修，必须走**流式布局**（`Column`
  + `Blank` 占位），不碰任何百分比定位与平移属性。
- [x] **资源行播放/暂停图标与实际状态不匹配**：列表签名只含 `isPlaying`
  （是否当前集），**不含 `paused`**；而图标判定是
  `ep.isPlaying && !lastState.paused`。暂停/恢复时签名不变 →
  `buildRoomPanelList()` 不重跑 → 图标停留在建列表那一刻的值（播放中
  建的就永远是暂停圈）。
  修法：对齐 Flutter `ValueListenableBuilder` **逐行监听**——
  `roomPlayIcons` 登记 `图标视图 → 是否当前集`，
  `refreshRoomPlayIcons(state)` 就地改文字/颜色，`renderRoomPanel()` 每次
  调用（500ms 轮询推来的 `paused` 立刻生效）。**不把 `paused` 加进签名**：
  那会让每次暂停都整表重建（滚动位置归零、封面重新解码闪烁）。
  颜色语义与 Flutter 一致：只看 `isPlaying`（`isPlaying ? accent :
  white54`），与是否正在播无关。
  签名补 `isHost`——图标只有房主看得到，角色切换必须重建。

### Phase 2.18：鸿蒙 VideoStack 单 Stack 重构（1.5.19+599）

> 起因：真机「鸿蒙进播放页还是没控件」+「点屏幕完全没反应」+「每次进
> 都没有」（截图是**横屏**）。

- [x] **根因（594 引入的结构性 bug，与前两轮判断都不同）**：594 把视频区
  抽成 `@Builder VideoStack()` 时，**误把原本在根 Stack 上的手势层一起搬
  了进去** → 该 @Builder 有 **3 个平级子节点**
  （`XComponent` + 手势层 A + 手势层 B）。而它被放进 `Row()`：
  ```
  Row() { this.VideoStack(); this.RoomPanelSlot(); }
  ```
  @Builder 展开后 Row 里是 4 个节点、其中 3 个都设 `'100%'` →
  - `XComponent` 只占第一格 → **画面偏左/被裁**；
  - 手势层被挤出屏外 → 触摸点落不到它上面 → **点屏幕完全没反应**；
  - Row 尺寸异常 → 破坏根 Stack 后续控件层的定位基准 → **顶栏/底栏全消失**。
- [x] **为什么前两轮都没修好**：597 的 `.translate` 在**横屏**下恒为 `0`
  （`portrait=false`），回滚它必然无效；598 回滚后
  `git diff 4207239 -- plugins/himi_mpv_ohos/` 为 0 行、问题依旧，正是反证。
  根因是 594 的结构错误，一直没被触碰。
- [x] **修法**：`VideoStack()` 只保留**一个顶层节点**（`Stack`），视频与
  手势层在 Stack 内叠放、各占 `100%`；分栏用的
  `layoutWeight`/`width`/`height` 上移到这个 Stack 上。同时删除 590 遗留的
  重复手势层（`GestureGroup` 全文件从 2 处减到 1 处）。
  `XComponent` 的 `onAreaChange` **仍挂在它自己身上**（挂外层 Stack 会
  拿到外层尺寸 → 586 的画质/拉伸问题会复发），`vp2px` 换算一行未动。

### Phase 2.19：鸿蒙房间模式控件收窄 + 资源行图标刷新 + 起播进度条（1.5.20+600）

> 起因：真机「房间模式控件是全屏的，应该和安卓一样」「资源列表前面的
> 播放/暂停控件状态不变化」「每次起播还在加载进度条时进度条会跑到最
> 末端，正常播放了就回到了开头」。

- [x] **房间模式控件层是全屏**：599 已把 `VideoStack` 收窄，但控件层
  （顶栏/底栏）挂在根 Stack 上、宽高都是 `'100%'`（全屏）→ 横跨整屏、
  压在资源面板上。安卓有 `applyVideoSplit()` 专门收窄控件层，鸿蒙没有
  对应逻辑。
  修法：新增 `@State controlsW` / `@State controlsH`，控件层包一层 Column
  按它们收窄（0 时回落 `'100%'`）。语义对齐安卓：
  - **横屏**只收宽度：`controlsW = 屏宽 - ROOM_PANEL_WIDTH`（视频区底
    就是屏幕底）；
  - **竖屏**只收高度：`controlsH = 屏高 - ROOM_PANEL_HEIGHT`（视频区宽
    就是屏幕宽）；
  - **未分栏**两者归零。
  **关键**：`onAreaChange` 只在**屏幕尺寸变化**时触发，房间面板开关时
  屏幕尺寸不变 → 抽成 `updateControlsSplit()`，在 `onAreaChange` /
  `onStateChanged` / `tick` 三处都调用（否则收窄永远不生效）。
- [x] **控件层改流式布局（彻底移除百分比定位）**：底栏壳原本用
  `.position({y:'100%'}) + markAnchor({y:'100%'})` 贴根 Stack 底缘——
  分栏后那是「全屏底」而非「视频区底」（竖屏被资源面板盖住），且百分比
  定位与任何附加属性叠加都会跑位（597 的 `.translate` 就是这么把控件推
  到屏幕外的）。
  修法：控件层改 `Column + Blank` 流式布局——顶栏贴顶、`Blank()` 吃掉
  中间剩余、底栏自然落在容器（= 视频区）底缘。`LockOnlyBar` 同样处理
  （锁定分支 `Blank` 在前推到底）。**全文件不再有 `.position` /
  `.markAnchor` 实际调用**。
- [x] **资源行播放/暂停图标不随状态变化**（与安卓 598 同源 bug）：
  `RoomEpisodeRow` 读 `state().paused` 是宿主**普通字段**（不在 ArkUI
  观察链上），而 `RoomPanel` 又不在任何 `ForEach` 重建块里 → 暂停/恢复
  时面板节点不重建 → 图标停在建列表那一刻的值。
  修法：新增 `@State roomPlayEpoch`，`syncFromHost()` 里按
  `${paused}|${currentEpisodeIndex}` 签名比对、变化才自增（**不用 tick
  每 250ms 推进**——那会把列表滚动位置每 250ms 归零）；`RoomPanelSlot`
  外包 `ForEach([this.roomPlayEpoch])` 按 epoch 重建；图标判定改读
  `@State this.paused`。
- [x] **起播加载时进度条跑到最末端、正常播放后回到开头**：
  `positionNowMs()` 在 `durationMs` 未解析出来时（起播前几秒仍为 0）走
  **无上限外推**，而 `GlassSlider` 的 `max` 此时是兜底值 `1`
  （`durationMs > 0 ? durationMs : 1`）→ `value` 被外推到几千 /
  `max=1` → `toRatio` 钳到 1 → **进度条顶到最右**；等时长就绪、`max`
  变成真实毫秒数，`value` 回到正常位置 → 又跳回开头。
  修法（双保险）：
  - `positionNowMs()` 加前置守卫：`durationMs <= 0` 时直接返回上报位置；
  - `ProgressRow` 的 `max` 兜底改为
    `Math.max(dragging ? dragMs : posMs, 1)`，保证 `value <= max` 恒成立。

### Phase 2.20：鸿蒙横屏控件贴左 + 房间模式锁控件（1.5.21+601）

> 起因：真机「鸿蒙横屏房间模式控件位置不对」（截图：控件整体居中、右缘
> 被资源面板切掉）、「横屏竖屏都没了锁控件」（且确认只在房间模式消失）。

- [x] **横屏控件层整体居中、被面板切掉**：根 `Stack` 的
  `alignContent: Alignment.Top`——`Top` 的**水平**对齐是 `Center`。600
  给控件层容器设的宽度是**具体数值**（`屏宽 - 320vp`，不足 100%），在
  Stack 里就按 Top 的水平居中规则摆放 → 控件整体右移居中、右缘被资源
  面板切掉。
  修法：容器显式 `.align(Alignment.TopStart)` 贴左上。**不改根 Stack 的
  `alignContent`**（会影响所有子节点，风险大）。
- [x] **房间模式锁控件消失（横竖屏都没有）**：`ControlRow` 的底栏锁钮
  条件写死 `!tvMode && !isRoom`——房间模式下整个跳过锁钮，用户无法锁定
  屏幕。而 Flutter 是 `showPhoneLock = phoneControls &&
  showLockButton(tvMode)`（**与房间模式无关**），安卓是
  `lockButton.visibility = if (!tv) VISIBLE else GONE`（也不看 `isRoom`）。
  修法：去掉 `&& !this.state().isRoom`，只看 `tvMode`，对齐两端。

### Phase 2.21：鸿蒙横竖屏切换黑屏 + 控件贴左（1.5.22+602）

> 起因：真机「鸿蒙横屏房间模式的控件 UI 还是老样子」（截图：控件仍居中、
> 右缘被资源面板切掉）、「横竖屏切换为什么会短暂黑屏」。

- [x] **601 的修法无效（`.align()` 用错了）**：601 给控件层容器加了
  `.align(Alignment.TopStart)`。但 `.align()` 的 ArkUI 语义是
  「**组件内容**在自身绘制区内的对齐」，**不能**定位组件在父 `Stack`
  中的位置——真机截图证实控件仍居中。
  正确修法：根 `Stack` 的 `alignContent` 从 `Alignment.Top` 改为
  `Alignment.TopStart`（`Top` 的**水平**对齐是 `Center`）。已核实根
  Stack 其余子节点全部是 `100% × 100%`（分栏容器 / 加载指示器 /
  `DanmakuLayer` / 手势提示 / 倍速提示 / 音量柱条 / `NativePlayerPanel`），
  只有控件层容器宽度是具体数值（`屏宽 - 320vp`）——改 `alignContent`
  只影响控件层，风险可控。
- [x] **横竖屏切换短暂黑屏**：594 的分栏结构是
  `if (portrait) { Column{ VideoStack } } else { Row{ VideoStack } }`——
  `VideoStack()` 在两个分支里**各调用一次**。ArkUI 的 `if/else` 条件翻转
  会**整体销毁旧分支、创建新分支**，里面的 `XComponent` 随之
  `onSurfaceDestroyed`（解绑 → 黑一帧）→ `onSurfaceCreated`（重绑 → 画面
  回来）。
  修法：**视频层提到 if/else 分支之外**，根 Stack 里只存在一份实例；方向
  切换只移动资源面板，视频节点完全不动。
  配套：`VideoStack` 的尺寸从 `layoutWeight`（依赖 Row/Column 弹性布局）
  改为显式 `videoW`/`videoH`（0 = 铺满 100%），由
  `updateControlsSplit()` 一并计算——横屏 `videoW = 屏宽 - 320vp`，
  竖屏 `videoH = 屏高 - 280vp`。资源面板改用 `Blank` 弹性推到边缘
  （竖屏贴底、横屏贴右）。

### Phase 2.22：弹出面板收窄到视频区 + suspend/resume 替代 close/reopen（1.5.23+603）

> 起因：真机「鸿蒙横屏房间模式，所有弹出面板不在视频区域」（截图：显示
> 调节面板整个压在右侧资源面板上）；「点击返回弹出确认框，点取消后播
> 任何视频都白屏」。

- [x] **弹出面板不在视频区**：`NativePlayerPanel` 挂在根 Stack 上，根容器
  是 `100% × 100%`（**全屏**）+ 内部 `Alignment.End` → 贴**全屏右缘**；
  房间模式横屏时资源面板占右侧 320vp，面板正好压在它上面。
  安卓有 `panelLeftMarginPx`（`videoAreaWidth() - 面板宽 - 12dp`）贴视频区
  右缘，鸿蒙完全没有——**599~602 四轮都在改控件层（顶栏/底栏），从未处理
  过弹出面板**。
  修法：`NativePlayerPanel` 新增 `@Prop videoW`，根容器
  `.width(videoW > 0 ? videoW : '100%')`——收窄后内部 `Alignment.End`
  自然落在视频区右缘（与安卓等价，无需额外 margin）。遮罩同步收窄
  （对齐安卓 `panelScrim` 的 `videoW × videoH`）。
  **本轮只改横屏**（竖屏面板避让留待下轮）。
- [x] **取消离房后白屏**：`_exitFromNativeUi` 先 `closeNativeUi()`（销毁
  宿主）再弹确认框；取消分支不 pop → 原生窗口已关、`nativeUiActive` 为
  false → Flutter 视频层重建，但 mpv surface 仍绑在已销毁的原生窗口上
  → 白屏（且无任何恢复路径）。
  修法：三段式 —— **先 `suspendNativeUi()`（只隐藏、不销毁）** → 弹框
  → 取消则 `resumeNativeUi()`（session/surface 原封不动，零白屏）；
  确认才 `closeNativeUi()` + pop。
- [x] **搜索返回黑屏改用 suspend/resume**：597 用
  `closeNativeUi()` + `reopenNativeUi()` 修黑屏，但那是**销毁后重建**——
  要重新绑定 surface，有「两个 SurfaceView 抢绑定」风险（597 为此加了
  250ms 等待）。603 统一改为 `suspendNativeUi()` → 搜索页 →
  `resumeNativeUi()`，session 原封不动。
- [x] **平台侧实现（只隐藏不销毁）**：
  - 鸿蒙：`win.hideWindow()` / `win.showWindow()`（**不** `destroyWindow`），
    resume 后补一次 `feedSafeArea`（隐藏期间安全区可能变化）；
  - 安卓：`dialog.hide()` / `dialog.show()`（**不** `dismiss`），resume 后
    重新 `applyFullscreen` + 按 `lastVideoInsetPx` 重新收窄（`show()` 会把
    窗口尺寸重置回全屏）。

### Phase 2.23：鸿蒙房间面板交互补全 + 分享面板遮挡（1.5.24+604）

> 起因：真机「鸿蒙开空房间或房间未播放资源时资源面板顶部缺几个控件：
> 搜索、人数、用户」「播放时资源面板无法手动展开收起」「资源列表里只能
> 播放/暂停和切换视频（删除无效）」「搜索添加的新资源不能立马显示」
> 「删除不了列表最后一个资源」「安卓和鸿蒙的分享控件弹出面板被原生层
> 遮挡，没显示」。

- [x] **空房间头部缺搜索/人数/角色徽章**：`RoomPanel` 包在
  `ForEach([roomPlayEpoch])` 里，而 600 的签名只含
  `paused | currentEpisodeIndex`——空房间时这两项恒定 → epoch 不推进 →
  面板节点不重建 → 头部那些读宿主普通字段（不在 ArkUI 观察链）的条件
  永远取不到新值。
  修法：签名补全 `isHost` / `onlineUserCount` / `audienceName` /
  `resourcePanelOpen` / `broadcasts.length`，另加轻量的资源分组内容签名
  （组名/季数/各季集数）。
- [x] **播放时无法手动展开/收起资源面板**：鸿蒙**完全没有**资源面板开关
  按钮（安卓有 `panelToggleButton`，条件 `if (state.isRoom)`）→ 面板一旦
  打开就再也关不掉，视频区一直被压缩、其它底栏控件被挤掉。
  修法：`ControlRow` 右侧簇加 `panelToggle` 按钮（图标 `ICON_OPEN_IN_FULL`
  与安卓同源，条件 `isRoom`，发 `toggleResourcePanel` 命令）。
- [x] **列表里删除无效（点了变成切集）**：删除按钮 `Text` 是行容器 `Row`
  的**子节点**，而 `Row` 自己有 onClick（切集/暂停）。ArkUI 的 onClick
  会**冒泡到父节点** → 点删除先发 `removeResourceEpisode`、再触发一次切集。
  且 `ClickEvent` 上**没有** `stopPropagation`（只有 Hover/Mouse/Touch/
  Key 有），无法就地阻止。
  修法：把「缩略图 + 集信息」包进可点击容器，行容器 `Row` 不再挂 onClick
  ——删除按钮与播放图标成为它的**兄弟节点**，互不冒泡。与 Flutter
  （`InkWell` 包内容区 + `IconButton` 兄弟）和安卓（子 View 各自
  `setOnClickListener`）一致。
- [x] **搜索添加的资源不立即显示**：`_addResourceLocally` 只做
  `setState(_rebuildGroups())`，没有推原生；且原生重建签名不含资源分组
  内容 → 新资源加进来后签名不变、列表不重建。
  修法：`_addResourceLocally` 末尾补 `_syncNativePanelData()`；签名补
  资源分组内容（同第一条）。
- [x] **删不掉列表最后一个资源**：594 的「保留非空值」逻辑在
  `_resourceGroups` 为空时返回上次快照——删到最后一个时原生收到的仍是
  删除前的旧列表。（原生命令路径本就有 `_syncNativePanelData()`，问题是
  推送了**旧数据**。）
  修法：新增 `_resourceGroupsCleared` 标记，只由「用户主动删除」置位；
  `_nativeResourceGroups()` 据此放行空列表。594 的保护仍兜住起播瞬态。
  同时 `_removeEpisode` 末尾补 `_syncNativePanelData()`（删除后立即刷新）。
- [x] **分享面板/房间解散提示被原生层遮挡**：原生播放窗口（鸿蒙子窗口 /
  安卓 Dialog）的 z-order 在 Flutter 页面**之上**，`showDialog` 被完全
  盖住。603 已修「离房确认」与「资源搜索」，但**漏了分享**。
  修法：抽公共辅助 `_suspendNativeUiForDialog()` /
  `_resumeNativeUiAfterDialog()`；分享面板与「房间已解散」提示都改为
  「隐藏原生窗口 → 弹框 → 关闭后恢复」（session 未销毁 → 零黑屏）。

### Phase 2.24：鸿蒙面板显隐/头部控件改走 @State（1.5.25+605）

> 起因：真机「鸿蒙初始房间无播放时头部缺搜索、人数、角色徽章」（澄清：
> 播放后就出现，初始也要有）「资源面板收起/展开有问题，横屏竖屏都不对」
> （澄清：点收起后视频全屏了，但面板还在）「资源列表无法展开子分支」。

- [x] **收起后视频全屏了但面板还在**：`build()` 里的
  `if (this.roomPanelVisible())` 读的是 `this.state().resourcePanelOpen`
  ——宿主**普通字段**，不在 ArkUI 观察链上 → 这个 `if` 节点**不会随状态
  变化重新求值**，面板节点一直留在树里。而 `videoW`/`videoH` 是 `@State`
  （会刷新）→ 视频区确实恢复了全屏，两者不同步。
  修法：新增 `@State roomPanelShown`，`syncFromHost()` 里同步
  `s.isRoom && s.resourcePanelOpen`；`build()` 的 `if` 与
  `updateControlsSplit()` 都改读它。
- [x] **初始房间无播放时头部缺三个控件**：搜索/人数/角色徽章的条件与文案
  读 `this.state().isHost` / `onlineUserCount` / `audienceName`——宿主
  普通字段（不在观察链），只能靠面板节点重建才取到新值；而空房间时重建
  签名（`paused|currentEpisodeIndex`）恒定，节点根本不重建 → 永远停在
  首次渲染时的空值。
  修法：新增 `@State roomIsHost` / `roomOnlineCount` / `roomAudienceName`，
  `@Builder` 内直读 `@State` → 任何变化立即刷新（不依赖重建纪元）。
  资源行的房主判断（播放图标/删除按钮/内容区点击）一并改读 `roomIsHost`。
- [x] **资源列表无法展开子分支**：604 的 `groupsSig` 只算
  「组名:季数:各季集数」，**不含 `collapsed`**——折叠/展开只改折叠态，
  签名不变 → 列表不重建 → 箭头与内容都不变。
  修法：签名补组/季的 `collapsed`：
  `${g.name}:${g.collapsed}:${g.seasons.length}:${各季 ${s.collapsed}/${集数}}`。

> **本轮的根因共性**：ArkUI 的 `if` 条件与 `@Builder` 内部**读宿主普通
> 字段都不会自动刷新**，必须镜像到 `@State`。600 在资源行图标上踩过一次
>（`ep.isPlaying && !this.state().paused`），但当时只在那一处修了，没有
> 推广到面板显隐与头部控件——605 一次性补齐。

### Phase 2.25：鸿蒙头部挤压 + 面板开关位置 + 删除播放中资源不停播（1.5.26+606）

> 起因：真机「鸿蒙初始进房间（未播放）头部还是不显示搜索、人数、房主
> 徽章」「面板开关控件在视频区横竖屏都太靠右」「安卓和鸿蒙都有的问题：
> 点击删除正在播放的资源，该资源还在播」。

- [x] **头部三控件被标题挤压到不可见**：`Text('资源')` 用
  `layoutWeight(1)`——ArkUI 里它会吃掉**全部**剩余空间，把兄弟节点压到
  0 宽。安卓注释记录过同一 bug：「标题只占剩余空间（layoutWeight=1），
  但必须给搜索/人数/角色预留固定宽度，否则标题撑满后把三者挤到最右」。
  修法：给人数胶囊 `constraintSize({ minWidth: 40, minHeight: 20 })`、
  角色徽章 `constraintSize({ minWidth: 32, minHeight: 20 })` 保底（搜索
  图标本就有 28×28 显式尺寸）。截图里连**无条件渲染**的人数胶囊/角色徽章
  都不见了，正是被压成 0 宽的表现。
- [x] **面板开关按钮太靠右**：604 把它放进了内层
  `Row({ space: 20 * bottomScale })`——那是图标簇内部用的间距（20×缩放），
  与安卓的 trailing 槽子项布局不同，真机上按钮贴到最右边缘、与其它图标
  脱节。
  修法：移到外层 trailing 槽（`justifyContent: End` 会把它排在图标簇之后），
  并加 `.margin({ left: 20 * bottomScale })` 与簇留间距——对齐安卓
  `trailingGroup.addView(panelToggleButton, llp(dp(32), dp(32), CONTROL_GAP))`。
- [x] **删除正在播放的资源后仍在播（安卓 + 鸿蒙都有）**：
  `_removeEpisode` 设了 `_player.state = AdapterPlaybackState.stopped`
  （该 setter **确实**会调 `player.stop()`），但适配器的 500ms 轮询
  `_applyPolledState` 里有：
  ```dart
  if (_prepared && hasProgress) {
    _setState(state.paused ? paused : playing);   // ← 把 stopped 覆盖回 playing
  }
  ```
  `_prepared` 只在 `prepare()` 里置 true、**从不重置**，而
  `durationMs`/`positionMs` 仍在 → 下一轮轮询立刻把状态改回 `playing` →
  `player.play()` → 画面继续播（暂停态删除同样会被拉回 playing）。
  修法：新增 `MpvPlayerAdapter.unloadMedia()`——重置 `_prepared` /
  `_positionMs` / `_durationMs` / `_bufferedMs` 与属性缓存、置
  `_mediaStatus = unloaded`、显式 `stop()`，让轮询不再认为「有进度在播」。
  `_removeEpisode` 删除当前播放资源时调它。

### Phase 2.26：鸿蒙头部 Blank 占位 + 播放图标点击 + 空态提示（1.5.27+607）

> 起因：真机「鸿蒙初始进房间（未播放）头部还是不显示搜索、人数、房主
> 徽章」「面板开关按钮跑到资源面板里、几乎压线」「删除正在播放的资源
> 不是要暂停，是要把正在播的视频清空（参考 Flutter 房间的删除）」
> 「资源面板每列前面的播放/暂停控件点击没反应」。

- [x] **头部三控件仍不显示**：606 加的 `constraintSize({ minWidth })`
  **无效**——ArkUI 里 `layoutWeight(1)` 的优先级**高于** `constraintSize`，
  `Text('资源')` 仍吃掉全部剩余空间、把兄弟节点压成 0 宽。
  修法：`layoutWeight(1)` → `Blank()` 弹性占位（ArkUI 里唯一可靠「吃掉
  剩余空间且不压扁兄弟节点」的手段，等价 Flutter 的 `Expanded(资源)`）。
- [x] **面板开关按钮压线资源面板边界**：`controlsW` 已生效（底栏只到视频
  区），但 `panelToggle` 是 trailing 槽**最末元素**，右缘正好落在控件层
  右缘（= 视频区/面板分界）。
  修法：`.margin({ left: 20 * bottomScale, right: 8 })` 补右侧留白。
- [x] **播放/暂停图标点击无响应**：604 修「删除按钮冒泡到切集」时把行容器
  的 onClick 移到了内容区容器（缩略图 + 集信息），但**遗漏了播放图标**
  ——它既没有自己的 onClick、也不再能靠父容器冒泡 → 点击完全无响应。
  修法：补独立 `onClick`（对齐 Flutter `TvFocusable.onTap`：当前集→暂停/
  继续，其它集→切集）+ `.hitTestBehavior(HitTestMode.Block)` 防穿透。
- [x] **删除当前播放资源后要「清空视频」而非暂停**：Flutter 侧置
  `_isPlayerReady = false` → 视频区走占位分支（`▶ play_circle_outline
  (64, white24)` + `请从资源面板选择要播放的内容`(14, white38)）。
  原生侧此前**完全没有**这个占位 UI，删除后停在最后一帧（看起来像
  「没删掉」）。
  修法：`NativePlayerState` 新增 `playerReady`（8 层补全：构造参数/字段/
  `fromJson`/`toJson`/`copyWith`/`==`/`hashCode`/`_buildNativePlayerState`），
  与 `_prepared` 绑定（`unloadMedia()` 会重置它）；鸿蒙新增 `@State
  playerReady` + 占位层（尺寸/颜色/间距逐值对齐 Flutter，`hitTestBehavior
  (None)` 不抢手势）。

### Phase 2.27：鸿蒙面板定位改 Stack 对齐 + 缩放宽度补算 + 占位层黑底（1.5.28+608）

> 起因：真机「鸿蒙初始进房间（未播放）和开空资源房间：头部还是没显示
> 搜索、人数、房主徽章」「面板开关按钮横屏不在视频区、竖屏超出手机界面」
> 「删除正在播放的资源会出现隐约的之前视频画面」。

- [x] **头部三控件"消失" + 面板开关按钮飞出屏幕（同一根因）**：
  602~607 一直用 `margin({ left: videoW })` 把面板推到右/下边缘——而
  `videoW` 是用 `areaWidth` 反推的，`areaWidth` 在**子窗口**场景可能大于
  实际内容宽 → `margin.left + 320 > 实际宽` → **面板右缘被裁到屏外**。
  头部右侧三个控件（搜索/人数/徽章）正好落在被裁区域，看起来"消失了"；
  面板开关按钮同理被挤出。
  **截图佐证**：竖屏（面板全宽、无 margin 计算）头部三控件正常；横屏
  （有 margin 计算）全无。
  修法：`RoomPanelSlot` 改用 `Stack` 的 `alignContent` 让框架按**父容器
  实测宽**摆放——横屏 `TopEnd`（贴右上）、竖屏 `BottomStart`（贴左下），
  不参与任何数值计算，从根上消除溢出。容器 `hitTestBehavior(Transparent)`
  让空白区放行给下层手势层。
- [x] **缩放比偏大导致按钮超出**：`trailingNaturalWidth()` 从 604 起**漏算
  房间模式的 `panelToggle`**（32vp + 20 间距）→ `natural` 少 52vp →
  `bottomScale` 算得偏大 → 簇实际宽度超出 trailing 槽 → 按钮被挤出可视区
  （竖屏尤其明显）。
  修法：`if (this.state().isRoom) blocks++;`。
- [x] **删除后出现隐约的旧视频画面**：mpv `stop()` 后 surface 上**仍残留
  最后一帧**，占位层若透明就会让旧画面透出来（真机截图能看到人像隐约
  浮现）。Flutter 侧视频区是独立 Widget 栈、天然不透明，原生必须自己盖
  一层。修法：占位层加 `.backgroundColor(Color.Black)`。

> **本轮的教训**：①和②前几轮一直在调数值（`minWidth` / `margin.right` /
> `constraintSize`），但真正的问题是**用 `areaWidth` 反推布局位置**——
> 这个值在子窗口场景不可靠。改用框架自己的对齐能力（`Stack.alignContent`）
> 才是正确方向。

### Phase 2.28：erika 预编译包下载地址失效（上游改名）（1.5.29+609）

> 起因：Windows CI 从 607 起连续失败（重跑两次仍红），报
> `MSB8066: Custom build for erika_capi_runtime ... exited with code 1`，
> 且 CMake 输出被 MSBuild 吞掉、看不到具体错误。

- [x] **根因：上游仓库改名导致下载 404**：
  `AimesSoft/Erika` 已改名为 **`AimesSoft/liberika`**，旧下载地址返回
  **404**。脚本用 `file(DOWNLOAD ... EXPECTED_HASH)`，拿到的是 9 字节
  `Not Found` 文本 → SHA 校验必然失败 → 自定义构建退出码 1。
- [x] **为什么之前误判为「偶发失败」**：我用 `curl -sIL` 检查地址，看到
  200 就以为正常——但 `-I` 只取响应头、`-L` 跟随重定向后的 200 是重定向链
  的假象。真正用 `curl -sL -o` **实际下载**才暴露：文件只有 9 字节、
  内容是 `Not Found`。
- [x] **修复 3 处下载地址**（`AimesSoft/Erika` → `AimesSoft/liberika`）：
  | 文件 | 平台 |
  |---|---|
  | `third_party/erika_flutter/windows/build_erika_runtime.cmake` | Windows（CI 当前失败） |
  | `third_party/erika_flutter/ohos/src/main/cpp/CMakeLists.txt` | 鸿蒙（本地有预编译缓存掩盖，CI 全新环境会失败） |
  | `third_party/erika_flutter/android/erika-native.gradle` | Android（同上） |
  每处都加了「上游改名、同步时不要回退」的注释。
- [x] **验证**：实际下载 `liberika` 的 windows-x64（143MB）与
  openharmony-arm64（17.6MB），SHA-256 与
  `native_artifacts.properties` 声明值**完全一致**——说明只换了域名、
  包内容未变，无需更新校验值。

### Phase 2.29：鸿蒙 Flex 流式分栏 + 安卓占位层/选集面板/弹幕重排（1.5.30+610）

> 起因：真机「鸿蒙横屏房间模式头部还是不显示搜索、人数、房主徽章」
> 「安卓 + 鸿蒙删除正在播放的资源，安卓占位提示下方还会透出旧画面，鸿蒙
> 整个资源面板都没了」「安卓非房间模式选集面板跑到左边」「安卓原生 MPV
> 的弹幕只有顶部一行、前后跳动抽搐」。

- [x] **鸿蒙横屏面板跑到屏外（头部三控件随之不可见）**：602~608 一直是
  「视频层常驻 + 面板用 `Stack.alignContent` 或 `margin` 叠加定位」，而
  那个 `Stack` 容器是**全屏尺寸**（`width('100%')`）→ `TopEnd` 让面板贴
  **全屏右缘**、正好落在资源面板下面；`margin.left = videoW` 又依赖不可靠
  的 `areaWidth`（子窗口场景偏大 → 面板右缘被裁到屏外）。
  修法：改回**流式布局**——`Flex` 把视频与面板作为兄弟节点排布，宽度由
  框架按父容器实测值分配（`layoutWeight(1)` 吃剩余），不参与任何数值反推。
  **为什么用 Flex 而不是 if/else 换 Row/Column**：换容器类型会让 ArkUI
  整体销毁子树 → `XComponent` 销毁重建 → 转屏黑一帧（594 真机回归）；
  `Flex` 的 `direction` 是**属性**，转屏只改属性、子树不销毁。
- [x] **安卓删除后旧画面还在**：安卓原生侧**完全没有**占位层（607 只给
  鸿蒙加了）。mpv `stop()` 后 surface 残留最后一帧一直可见。
  修法：`AndroidNativePlayerState` 补 `playerReady`；`NativePlayerScreenView`
  新增 `placeholderView`（图标 64 + 文案 14 + **不透明黑底**），加在
  `bufferingView` 之前保证 z-order 低于转圈。
- [x] **安卓非房间选集面板跑到左边**：`panelLeftMarginPx` 旧实现
  `if (fullBleed) return 0` —— `leftMargin = 0` 即贴**左**。而 Flutter 的
  `selectorPanelBox(fullBleed: true)` 是 `right: 0.0`（贴**右**、只是没有
  12dp 间距）。
  修法：`val rightPad = if (fullBleed) 0 else dp(PANEL_RIGHT)`，再算
  `videoAreaWidth() - panelW - rightPad`。
- [x] **安卓弹幕只有一行 + 抽搐**：`onSizeChanged` 只要尺寸变化就
  `laneOf.clear()` —— 而弹幕层在分栏/控件层收窄/视频区缩放时会**频繁**
  触发（尺寸微调但行容量不变），每次都清空所有行号绑定 → 下一帧全部重新
  分配 → 视觉「抽搐」；且首帧布局未完成时 `h` 偏小 → `autoRows` 算成 1 →
  只剩顶行。
  修法：按**行容量**（`autoRows`）判断——容量不变就不清；`h <= 0` 时直接
  返回（不基于无效高度重排）。

### Phase 2.30：鸿蒙头部 flexShrink + 占位层收进视频区 + 弹幕单层插值（1.5.31+611）

> 起因：真机「鸿蒙房间模式头部仍然不显示搜索、人数、房主徽章」（已修 4 轮
> 仍不生效）「鸿蒙删除正在播放的资源后资源面板变成整块黑色」「安卓 MPV
> 弹幕还是抖动」。

- [x] **头部三控件不显示（第 5 轮，终于找到正确方向）**：前 4 轮都在
  ArkUI 里试「让兄弟节点不被压扁」的写法——606 `constraintSize`
  （无效：`layoutWeight` 优先级更高）、607 `Blank()`（无效）、608/610
  也没解决。
  **真正的根因**：**ArkUI 的 `layoutWeight` 与安卓 `LinearLayout` 权重
  语义不同**——安卓 `LayoutParams(0, WRAP_CONTENT, 1f)` 是「先测量兄弟
  节点的自身宽度，剩余空间才给权重节点」；ArkUI `layoutWeight(1)` 会
  直接抢占剩余空间、把兄弟压成 0 宽。
  **修法（对齐安卓）**：改用 `Flex`，标题 `flexShrink(1)`（可收缩但不
  抢占），右侧三个控件 `flexShrink(0)`（固定尺寸、不参与收缩）——
  等价安卓给它们固定 `LayoutParams`。
- [x] **删除后资源面板整块黑色**：607 把空态占位层放在根 `Stack` 上、
  且是 `width('100%') + backgroundColor(Color.Black)` → **不透明黑底盖住
  了整个屏幕**，包括 `Flex` 里的资源面板（截图「面板整块黑色、标题列表
  全无」）。
  修法：占位层放进 `Flex` 的**视频子节点**内（用 `Stack` 包住
  `VideoStack` + 占位），只覆盖视频区。
- [x] **安卓弹幕抖动**：调用方传的是 `pos`（`positionAt()` 的**插值
  结果**），而 `DanmakuLayerView.setClock` 内部又会用墙钟再插值一次 →
  **两层插值叠加**。每次快照刷新（500ms）时 `positionAt` 的基准变化会让
  `pos` 跳变，弹幕位置随之跳动。
  修法：传**未插值的原始位置源** `state.positionMs`，由弹幕层单层插值
  ——对齐 Flutter（MDK 路径）`DanmakuOverlay` 的
  `_nowPosition = _lastPosition + (_elapsed - _alignElapsed)` 语义。

### Phase 2.31：原生 UI 初始快照补推 + 头部 flexGrow + Kotlin 类型修复（1.5.32+612）

> 起因：真机「鸿蒙房间模式初始未播放时头部不显示搜索/人数/房主徽章，
> 选资源播放后才显示」（已修 5 轮）；「三个控件挤在左边、没靠右」；
> 以及 CI 失败（Kotlin 类型不匹配）。

- [x] **初始未播放时头部三控件不显示（第 6 轮，找到真根因）**：前 5 轮
  全在改**布局代码**（`constraintSize` / `Blank` / `flexShrink`），方向
  错了。**根因是数据没送达**：
  `_syncNativePanelData()` 开头有守卫
  `if (mpv is! MpvPlayerAdapter || _disposed) return;`
  ——初始进房间时 `_player` **还不是 MpvPlayerAdapter**（播放器尚未创建）
  → 首次推送被**静默拦截** → `_nativeUiExtras` 从未赋值、保持默认
  `isHost: false` → 原生 UI 打开时读到的就是 false → 头部三控件不渲染。
  播放后（起播/切集路径）再次调用时 `_player` 已是适配器 → 推送成功 →
  头部才显示。
  **关键线索**：同一份布局代码「未播放没有、播放后有」→ 说明不是布局
  问题，是数据问题。
  修法：`_onNativeUiActiveChanged()` 里在 `_nativeUiActive` 为 true 时补推
  一次完整快照——那时 `_player` 必定已创建、守卫不会拦截，不依赖
  `initState` 的调用时机。
- [x] **三个控件挤在标题左边、没靠右**：611 只给了 `flexShrink(1)`——它
  只是「空间不足时可收缩」，**不会撑开**。标题按内容宽度（"资源" 2 字
  ≈28vp），剩余空间没人占 → 右侧控件紧跟标题（靠左）。
  安卓能靠右是因为 `LayoutParams(0, WRAP_CONTENT, 1f)` 的**权重 1 让
  标题吃掉剩余空间**。
  修法：补 `flexGrow(1)`（吃掉剩余空间）+ 保留 `flexShrink(1)`——与安卓
  权重 1 等价。
- [x] **CI Kotlin 类型错误**：`setClock(state.positionMs, ...)` 的
  `positionMs` 是 `Int`，而 `setClock` 签名要 `Long` → 编译失败
  `Argument type mismatch: actual type is 'Int', but 'Long' was expected`。
  修法：`state.positionMs.toLong()`。

### Phase 2.32：房间 UI 渲染层跟随播放器内核（1.5.33+613）

> 起因：真机「鸿蒙初始未播放/空房间时房间头部三控件不显示」已修 6 轮；
> 用户澄清需求：「播放器是原生就打开原生房，不是原生就开 Flutter 房，
> 切换播放器也同理」，且明确「不用提前创建 mpv 会话」。

- [x] **根因（第 7 轮，终于定位到渲染层错配）**：原生 UI 只在
  `prepare()` 里打开，而 `prepare()` 只在加载剧集时调用——**空房间没有
  剧集 → 原生窗口从未打开 → 用户看到的是 Flutter 播放页**。而 Flutter
  头部条件 `_roomData != null && _isHost && 非playing` 里的 `_roomData`
  在 **async 的 `_setupRoomSync()`** 里才赋值 → 初始为 null → 三控件不
  显示。播放后（`prepare()` 打开原生窗口、`isHost` 已推送）才显示。
  **关键线索**：同一份布局代码「未播放没有、播放后有」→ 不是布局问题，
  是**渲染层错配 + 数据时序**。
- [x] **修法（按用户要求，不提前建会话）**：
  1. `MpvPlayerAdapter.prefersNativeRoomUi` —— 纯计算 getter，只读
     `_resolveMpvVideoOutput()`（设置+平台）与 `NativePlayerGating`，
     **不创建会话**；
  2. `_openNativeUiIfNeeded()` 允许在 `prepare()` 之前打开（
     `_nativeUiEnabled` 未算时按 `prefersNativeRoomUi` 补算）；
  3. `PlayerScreen._roomUiShouldBeNative` 用它决定 Flutter 层是否退场
     （房间模式走新判定，非房间模式仍走 `_nativeUiActive`）；
  4. `initState` 里房间模式按判定 `reopenNativeUi()`，且 `_roomData`
     改为**同步** `RoomCode.decode()`（纯同步解码）；
  5. `_switchPlayerKernel` 的 `finally` 里重新判定——原生内核开原生房、
     非原生内核关原生房（旧实现切到 MDK 后仍是原生房、切回 mpv 后仍是
     Flutter 房）。
- [x] **空房间的预期表现**：原生窗口打开后无 mpv 会话 → 视频区显示
  「▶ 请从资源面板选择要播放的内容」占位（黑底），头部三控件正常。

### Phase 3：Android 完整原生控件 + TV

- [x] 同 Phase 2 全部控件（`NativePlayerScreenView` 照 Flutter 观感重画）。
- [ ] **`TvKeyRouter` 焦点/按键路由**（~~已勾选~~ 系**假勾选**：全仓无该
      文件，实际只有 `makeFocusable` 焦点环，无 seek/音量/跨组跳焦/退出确认
      等按键语义）。本轮已识别，待补。
- [ ] 手机手势（单独一轮）。
- [x] overscan/焦点描边。
- [ ] 验收：手机 + TV 遥控器全部语义与 Flutter 一致（需真机）。

### Phase 4：弹幕

- [ ] 鸿蒙 Canvas 弹幕 + 设置面板。
- [ ] Android Compose Canvas 弹幕 + 设置面板。
- [ ] 时间轴分片、轨道、滚动/顶部/底部、透明度、字号、速度、屏蔽词。
- [ ] 验收：双端弹幕性能与时间轴正确。

> 说明：弹幕**开关与样式参数**已在 Phase 2.5 接通设置（`adjustDisplay`
> 的 danmakuSpeed/FontSize/Opacity 三个滑杆），但原生侧暂不绘制，
> 绘制层属 Phase 4。

### Phase 5：房间同步、截图、调试、片头片尾

- [ ] 房主/观众控制。
- [ ] 成员列表、聊天、同步状态。
- [ ] 截图回调与保存。
- [ ] 调试面板完整字段。
- [ ] 片头片尾标记。
- [ ] 验收：双端完整复刻现有 Flutter 播放页。

### Phase 6：切换与生命周期

- [ ] Texture ↔ Surface 切换。
- [ ] 内核切换。
- [ ] 前后台、旋转、全屏。
- [ ] 退出清理、窗口销毁、播放器释放。
- [ ] 返回键只由当前活跃层处理。
- [ ] 验收：连续切换 10 次无残留窗口/无黑屏/无泄漏。

### Phase 7：测试、构建与交付

- [x] Dart 单元测试（Phase 0 协议/门控/控制器 45 项 + 回归 107 项）。
- [x] 鸿蒙 ArkTS 编译（`hvigor CompileArkTS` 零错误）。
- [ ] 鸿蒙真机测试（SDR/HDR 出画、surface/vo 诊断）——需实机。
- [ ] Android CI signed APK——需 CI 触发（本机无 Android SDK）。
- [x] Android 本地编译校验（`android.jar` API 36 + Flutter 桩，全量零错误）
  与状态层 11 项 JVM 单测。
- [ ] TV 遥控器实测——需实机。
- [x] 全量测试与 `flutter analyze`（Flutter-OH 3.35.7：2468 项全通过、
  无任何 analyze 问题）。
- [x] 版本递增（1.5.3+532）、构建产物、签名校验
  （`himi-sync-ohos-1.5.3-532-local-signed.hap`，`verify-app` 通过）。

> 工具链要求：`flutter test` / `flutter analyze` 必须用 Flutter-OH SDK。
> 标准 Flutter 3.47 下 `test/services/ohos_hybrid_platform_view_test.dart`
> 因缺 `PlatformViewsService.initExpensiveOhosView` 无法编译，且 M3 的
> `InkSparkle` 会在测试环境尝试编译 `shaders/ink_sparkle.frag` 失败，
> 波及约 32 个 widget 测试文件——均为工具链差异，与本计划无关。

---

## 9. 测试矩阵

| 场景 | 鸿蒙 | Android 手机 | Android TV |
|---|---|---|---|
| SDR 播放 | ✅ | ✅ | ✅ |
| HDR10 | ✅ | ✅ | ✅ |
| HLG | ✅ | ✅ | ✅ |
| 播放/暂停 | ✅ | ✅ | ✅ |
| seek | ✅ | ✅ | ✅ |
| 音轨/字幕 | ✅ | ✅ | ✅ |
| 选集/版本 | ✅ | ✅ | ✅ |
| 弹幕 | ✅ | ✅ | ✅ |
| 房间同步 | ✅ | ✅ | ✅ |
| 截图 | ✅ | ✅ | ✅ |
| 调试面板 | ✅ | ✅ | ✅ |
| Texture 回归 | ✅ | ✅ | — |
| 旋转/后台 | ✅ | ✅ | — |
| 返回/退出 | ✅ | ✅ | ✅ |
| 遥控器焦点 | — | — | ✅ |

---

## 10. 构建与发布

### 10.1 鸿蒙

```bash
export OHOS_CLT=/home/mojito/harmonyos-clt/command-line-tools
export JAVA_HOME=...
export HOS_SDK_HOME=$OHOS_CLT/sdk
export OHOS_BASE_SDK_HOME=$HOS_SDK_HOME
export DEVECO_SDK_HOME=$HOS_SDK_HOME
export PATH=$JAVA_HOME/bin:/tmp/opencode/flutter_flutter/bin:$OHOS_CLT/tool/node/bin:$OHOS_CLT/bin:$OHOS_CLT/hvigor/bin:$PATH
bash scripts/build_ohos_local.sh
```

- 产物：`dist/ohos/local/himi-sync-ohos-<version>-<build>-local-signed.hap`
- 校验：`hap-sign-tool.jar verify-app`
- 更新两个 `main_pages.json` 后再构建。

**环境依赖（本机实测）**

- Flutter-OH SDK：`git clone --depth 1 -b oh-3.35.7-release
  https://gitcode.com/CPF-Flutter/flutter_flutter.git /tmp/opencode/flutter_flutter`
  → 版本 `3.35.7+ohos-1.0.5`，引擎 `f3113bb0309`，与 `ohos/oh-package-lock.json5`
  及 `ohos/local.properties` 的 `flutter.sdk` 路径一致。
- 首次需要 `flutter precache --ohos` 下载 `bin/cache/artifacts/engine/ohos-arm64-release`。
- 本仓库的 MPV hybrid 平台视图补丁（`tool/ohos_mpv_hybrid/*.patch`）必须应用：
  `framework_platform_views.patch` 直接 `git apply` 到 checkout；
  `engine_arkts.patch` 需解包 `flutter_embedding_release.har` 后用
  `patch -p9` 应用并重新打包（原包保留为 `.har.orig`）。
- `JAVA_HOME` 必须指向 JDK 17，否则 hvigor 打包阶段报 `spawn java ENOENT`
  （本机：`~/.local/share/mamba/pkgs/.../openjdk-17.0.18.../lib/jvm`）。

### 10.2 Android

- 走 GitHub Actions（`android-hdr-ci.yml` / release workflow）。
- 使用现有 Himi release keystore，保证可覆盖安装。
- 三个 ABI 全出。
- 需要同步检查 `scripts/patch_android_signing.sh`。

### 10.3 版本

- 每批交付递增 `pubspec.yaml` 的 `+N`。
- `major/minor/patch` 每段 0–99。
- 构建号单调递增。

---

## 11. 风险与回退

| # | 风险 | 影响 | 应对 |
|---|---|---|---|
| 1 | `createSubWindow` 在部分设备/时机不可用 | 鸿蒙无法全屏原生 | 回退到同窗口 ArkUI `Stack` 覆盖层（`Index` 叠在 FlutterPage 上） |
| 2 | entry 无法导入 HAR 组件 | 编译失败 | 在 `ohos/entry/oh-package.json5` 显式加 `himi_mpv_ohos` 依赖 |
| 3 | 子窗口页面路由缺失 | 白屏/加载失败 | 同时更新 entry 与 template 的 `main_pages.json`；无需重编 index |
| 4 | Android Compose 与 Flutter Gradle 冲突 | 构建失败 | 原生 UI 放 app 模块；插件只提供 Surface/JNI |
| 5 | Surface handle 中途变化 | 黑屏/无声 | 中途变化时重建播放器并恢复位置；正常路径先开宿主再建播放器 |
| 6 | 原生 UI 状态不同步 | 进度/控件错乱 | 250–500ms 快照 + 本地插值 + 事件立即推送 |
| 7 | mpv 本身不出帧 | 独立窗口也白屏 | 保留 `surfaceAttached` / `vo-configured` / `current-vo` / surface 尺寸诊断 |
| 8 | HDR 设备不支持 | 发白/黑屏 | 按显示能力 tone map；调试面板标明实际路径 |
| 9 | TV 遥控器语义遗漏 | 验收失败 | 以现有 Flutter TV 逻辑为唯一基准，逐项写测试 |
| 10 | 子窗口/弹窗残留 | 内存泄漏/悬浮窗 | 所有退出路径统一 `close`；幂等销毁 |

---

## 12. 新会话开工检查清单

1. 阅读本文件与 `docs/mpv_kernels.md`。
2. 检查工作区状态，确认上一批 Surface/诊断改动是否已提交。
3. 确认 `pubspec.yaml` 版本与 build 号。
4. 确认鸿蒙 SDK / Flutter-OH / Java 环境变量。
5. 确认 Android release keystore 与 CI 权限。
6. 从 Phase 0 开始，按阶段提交。
7. 每个阶段结束更新本文件中的勾选状态与实测结果。

---

## 13. 关键代码位置索引

| 位置 | 说明 |
|---|---|
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvOhosPlugin.ets` | 鸿蒙 mpv 会话、surface 绑定、通道 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvSurface.ets` | XComponent / surface 回调 |
| `plugins/himi_mpv_ohos/ohos/src/main/ets/components/plugin/HimiMpvPlatformView.ets` | 现有 PlatformView（Surface 模式将不再使用） |
| `plugins/himi_mpv_ohos/lib/himi_mpv_surface_view.dart` | 现有 Flutter 平台视图 |
| `plugins/himi_mpv_ohos/lib/himi_mpv_ohos.dart` | Dart 侧鸿蒙接口 |
| `plugins/himi_mpv_android/android/src/main/kotlin/com/himi/mpv/android/` | Android Surface/JNI |
| `plugins/himi_mpv_android/lib/himi_mpv_android.dart` | Android media_kit + Surface 会话 |
| `lib/services/player/mpv_session_platform.dart` | 平台会话工厂 |
| `lib/services/player/mpv_player_adapter.dart` | 统一 MPV 适配器、HDR 与诊断 |
| `lib/screens/player/player_screen.dart` | 播放页、Surface/Texture 分支 |
| `ohos/entry/src/main/ets/entryability/EntryAbility.ets` | 鸿蒙入口 |
| `ohos/entry/src/main/ets/pages/Index.ets` | 主页面 |
| `ohos/entry/src/main/resources/base/profile/main_pages.json` | 页面路由 |
| `ohos/template/resources/base/profile/main_pages.json` | 打包用页面路由 |
| `scripts/build_ohos_local.sh` | 鸿蒙本地构建与签名 |
| `scripts/ohos_pack.sh` | HAP 重打包 |
| `android/app/src/main/kotlin/com/himi/syncwatch/MainActivity.kt` | Android 通道注册 |
| `android/app/build.gradle` | Compose 与签名 |

---

## 14. 待新会话确认的少量开放项

1. 是否保留现有 PlatformView Surface 路径作为调试/回退开关（建议保留，默认关闭）。
2. 鸿蒙原生 UI 面板是否允许与 Flutter 视觉不完全一致（此前已确认允许半透明深色近似）。
3. Android 原生 UI 是否确认放 app 模块（建议是，避免插件 Gradle 冲突）。
4. Phase 1 是否必须同时包含调试面板（建议至少包含 Surface/vo/HDR 关键行）。

以上开放项不阻塞 Phase 0；开工时确认即可。
