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

- [ ] 新增 `NativePlayerState` / `NativePlayerCommand` / `NativePlayerController`。
- [ ] `MpvSession` 工厂增加 `nativeUi`。
- [ ] 门控逻辑与日志。
- [ ] 单元测试：序列化、门控、命令路由。
- [ ] 验收：Texture 模式无变化；Surface 模式不打开原生 UI（阶段 0 仅门控）。

### Phase 1：双端最小原生壳（一起做）

**鸿蒙**

- [ ] 插件实现 `AbilityAware`。
- [ ] 创建/销毁全屏子窗口。
- [ ] 新增 `NativePlayer` 页面与 `main_pages.json`。
- [ ] XComponent + surface 绑定。
- [ ] 最小控件：播放/暂停、进度、时间、返回、诊断行。
- [ ] `himi_mpv/native_ui` 状态与命令。

**Android**

- [ ] 全屏 Dialog + SurfaceView + Compose 最小壳。
- [ ] `himi_native_player` 通道。
- [ ] Surface handle 顺序与重建。
- [ ] 最小控件：播放/暂停、进度、时间、返回、诊断行。

**验收**

- [ ] 鸿蒙 SDR/HDR 均有画面，`surfaceAttached=true`、`vo-configured=yes`。
- [ ] Android SDR/HDR 均有画面，无黑屏。
- [ ] 播放/暂停/seek/返回可用。
- [ ] Texture 模式回归正常。
- [ ] 输出 signed HAP + signed APK。

### Phase 2：鸿蒙完整原生控件

- [ ] 顶部/底部控制条。
- [ ] 音量/倍速/锁定/自动隐藏。
- [ ] 音轨/字幕/外挂字幕/字幕样式/延迟。
- [ ] 选集/版本。
- [ ] 内核/解码/显示调节。
- [ ] 播放页设置。
- [ ] 截图。
- [ ] 片头片尾标记。
- [ ] 手势。
- [ ] 验收：手机触控全功能可用。

### Phase 3：Android 完整原生控件 + TV

- [ ] 同 Phase 2 全部控件。
- [ ] `TvKeyRouter` 与焦点导航。
- [ ] 手机手势。
- [ ] overscan/焦点描边。
- [ ] 验收：手机 + TV 遥控器全部语义与 Flutter 一致。

### Phase 4：弹幕

- [ ] 鸿蒙 Canvas 弹幕 + 设置面板。
- [ ] Android Compose Canvas 弹幕 + 设置面板。
- [ ] 时间轴分片、轨道、滚动/顶部/底部、透明度、字号、速度、屏蔽词。
- [ ] 验收：双端弹幕性能与时间轴正确。

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

- [ ] Dart 单元测试。
- [ ] 鸿蒙 ArkTS 编译与真机测试。
- [ ] Android CI signed APK。
- [ ] TV 遥控器实测。
- [ ] 全量测试与 `flutter analyze`。
- [ ] 版本递增、构建产物、签名校验。

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
