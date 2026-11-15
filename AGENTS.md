# AGENTS.md

## 开发规范

1. 全程中文交流
2. 要求项目功能模块化设计，低耦合度，分布式开发
3. 每次完成一个功能或者修复完一个bug，务必编写相关测试并验证，交付用户之前，确保所有测试完整全部通过
4. 回答用户问题时，使用ask-question标签提问，不用plain text提问
5. 不要把安全隐私类文件传github,比如的github Api不要泄露，因为项目是公开库
6. 版本号各段（major/minor/patch）取值范围 0-99（如 1.2.0；不再出现 1.1.255 这类三位数补丁），构建号 `+N` 保持单调递增以保证 Android versionCode 可覆盖安装
7. 发布基础设施：`deps-mirror` release（存改名副本 `mdk-sdk-windows-x64.7z`）是 Windows 构建依赖，**严禁删除**；清理旧版本时只删 `v*` 标签/Release，勿动 `deps-mirror`
8. **发布说明写简短**：只列出**新增了哪些功能**；修复项一笔带过（统一写「修复一些已知问题」），不写根因分析和实现细节。**不按平台分章节**——相同功能/修复合并成一条，平台差异用括号注明（如「（安卓 TV）」）。`docs/release_notes_by_platform.md` 面向最终用户，不是技术报告

## 构建环境陷阱

### 鸿蒙 SDK 会串改依赖解析（必读）

`flutter_ohos` 的 `pub get` / `analyze` / `build` 会把
`.dart_tool/package_config.json` 里的 `flutter` 指向 `flutter_ohos`。
之后用 **stock Flutter** 跑 `flutter test` / `flutter analyze` 会报一堆：

```
The getter 'hasSelectedState' isn't defined for the type 'SemanticsFlags'
A value of type 'Tristate' can't be assigned to a variable of type 'bool'
```

**这不是代码坏了**，只是两套 SDK 的 `dart:ui` 不兼容。同理，鸿蒙 SDK
编译过的 `build/test_cache` 也会让 stock 测试报诡异编译错误。

**处理**：
- 手工用过鸿蒙 SDK 后，务必用 stock Flutter 重跑 `flutter pub get`
- `scripts/build_ohos_local.sh` 已内置 `trap`：构建结束（成功或失败）自动
  还原 `package_config.json` 并清 `build/test_cache`

### 安卓 libmpv 的 Vulkan 开关在 mpv-android 上游

libplacebo 的 Vulkan 后端（DV 元数据处理需要 compute shader）由
mpv-android 的 `buildscripts/scripts/libplacebo.sh` 控制：

    meson setup $build ... -Dvulkan=disabled

`build_android.sh` 在构建前 sed 替换为 `-Dvulkan=enabled`，并在构建后
用 `grep_binary libplacebo.so pl_gpu_vk` 验证。**改这个前先看上游**，
不要凭印象改 mpv.sh 或 ffmpeg.sh——Vulkan 开关只在 libplacebo.sh。

运行时由 `HimiMpvPlugin.isVulkanAvailable()`（Kotlin `System.loadLibrary`
验证）决定 `gpu-api=vulkan` 还是 `opengl`。

**CI 构建陷阱**：`release.yml` 的 `kernels` 任务复用最近一次成功的
`mpv-kernels.yml` 产物。改了 `scripts/mpv/**` 后必须等 kernels 构建完
再跑 release，否则 APK 里是旧 libmpv。

### 安卓启用 Vulkan 的三个必踩坑

697 真机回归：启用 libplacebo Vulkan 后 app **启动即白屏**。链路是：

1. media_kit 插件静态初始化块 `System.loadLibrary("mpv")`
   （在 Flutter 插件注册时执行，即启动阶段）
2. `System.loadLibrary` 用 **RTLD_NOW** —— 要求所有符号立即可解析
3. libmpv.so 里有未定义 Vulkan 符号 → `UnsatisfiedLinkError`
4. Flutter 生成的 `GeneratedPluginRegistrant` 只 `catch (Exception)`，
   而 `NoClassDefFoundError` 是 **Error** → 冒泡 → 首帧不出 → 白屏

必踩的三个坑：

| 坑 | 现象 | 解法 |
|---|---|---|
| meson 交叉编译只走 pkg-config，NDK 无 `vulkan.pc` | `vulkan found: NO` | 手写 `vulkan.pc` |
| NDK 只有 API 24+ 目录才有 `libvulkan.so` stub（编译用 API 23） | 链接器 `unable to find library -lvulkan` | 倒序搜 36→24 拷到 prefix/lib |
| `VK_KHR_display` 是桌面扩展，连 API 35 stub 都没有 | RTLD_NOW 失败 → 白屏 | `-Wl,--defsym=<sym>=0` 定义为绝对 0 |

验证手段：用 Python 解析 APK 里 `libmpv.so` 的 `SHT_DYNSYM` 段，
列出 `shndx==0` 的符号。**必须为 0 个 Vulkan 符号未定义。**

**第四个坑（黑屏有声的真凶）**：mpv 的 Android 上下文名按 API 区分——

    视频输出 API      上下文名
    OpenGL            android
    Vulkan            androidvk

`gpu-api=vulkan` + `gpu-context=android` 等于拿 GL 上下文配 Vulkan API，
必然报 `Failed initializing any suitable GPU context!` → vo 起不来
→ **有音频无画面**。正确写法用优先级列表（逗号分隔，依次尝试）：

    gpu-api      = vulkan,opengl
    gpu-context  = androidvk,android

这样 Vulkan 可用就走 Vulkan（DV 的 libplacebo compute），失败自动回落
OpenGL，不会黑屏。

**注意 mpv 的遍历顺序**（`video/out/gpu/context.c` 的 `ra_ctx_create`）：
它按 **`gpu-context` 列表**逐个 `create_in_contexts`，再用 `gpu-api`
的类型列表过滤。所以顺序由 `gpu-context` 决定，两个列表必须成对写。

**坑 4.5：`gpu-api` / `gpu-context` 读回来是「配置列表」，不是实际值。**
两者都是 `OPT_SETTINGSLIST` 类型，`getProperty` 返回完整候选串
（`vulkan,opengl` / `androidvk,android`）。想看**实际生效**的后端必须读

    current-gpu-context      // → vo->context_name，如 `androidvk`

697 真机回归：面板拿 `gpu-context` 判 DV 能力，又叠加「`androidvk`
不含 `vulkan` 子串」的坑，于是把跑在 Vulkan 上的 P5 内容标成
「后端不支持 DV，画面会偏色」。判定逻辑现统一在
`lib/services/debug/render_backend.dart`（四端同构），关键词用 **`vk`**
覆盖 `androidvk` / `ohosvk`，并且**实际值优先**。

**第五个坑：Vulkan 能初始化但渲染不出帧**。优先级列表只覆盖「上下文
创建失败」。若 Vulkan 上下文创建成功、呈现却失败，mpv 不会回退 → 仍然
是有声无画。适配器因此加了第二级看门狗
（`MpvPlayerAdapter._maybeFallbackToSoftwareDecode`）：

    软解(hwdec=no) 下 3s 仍无画面
      + vo-configured == "no"
      + 安卓
    → 显式 gpu-api=opengl / gpu-context=android 并重载一次
    → 同时 HimiMpvAndroidSession.disableVulkanRendering()
      （本次运行内后续会话直接 opengl，不再每次黑 3 秒）

另外两条硬化措施：
- Manifest 加 `<uses-native-library android:name="libvulkan.so"
  android:required="false"/>`（Android 12+ 可见性策略）
- `hwdec` 保持 `auto` / `auto-copy`，**不要**显式写 `mediacodec`：
  显式值要求硬解直写 Surface，部分设备直写失败且不回退 → 黑屏有声。
  `hwdec=auto` 时 mpv 虽把 vulkan 硬解纳入候选，但只有在 Vulkan 上下文
  初始化成功后才用，且 `hwdec-software-fallback=yes` 会兜底。
- MainActivity 用 `catch (Throwable)` 包住 `super.configureFlutterEngine`
  ——再出问题也不会白屏，至少能打出可诊断日志

**第六个坑（Vulkan 起不来的真因）：libplacebo 有 Vulkan 后端 ≠ Vulkan 能用。**

`pl_gpu_create_vk()` 里第一件事是建 GLSL→SPIR-V 编译器
（`src/vulkan/gpu.c` → `pl_spirv_create()`）。libplacebo 只在

    #ifdef PL_HAVE_SHADERC   → src/glsl/spirv_shaderc.c
    #ifdef PL_HAVE_GLSLANG   → src/glsl/spirv_glslang.c

两个宏之一存在时才把编译器放进 `compilers[]`；都没有时：

    pl_fatal("Failed initializing any SPIR-V compiler! ...");
    return NULL;            // → pl_gpu_create_vk() 失败
                            // → mpv: Failed initializing any suitable GPU context!
                            // → 静默回落 OpenGL（有声有画，只是 DV 退化成静态峰值）

上游 mpv-android 的 `libplacebo.sh` 是 `-Dvulkan=disabled`，所以它从不需要
SPIR-V 编译器；**我们只把 vulkan 改成 enabled、没补 shaderc，就等于开了个
永远起不来的 Vulkan**。正确做法（照抄 mpv-ohos 的构建）：

    -Dvulkan=enabled -Dshaderc=enabled   # libplacebo
    # 另需独立构建 shaderc（CMake+Ninja，静态），并把
    # shaderc_combined.pc 改名成 shaderc.pc（默认那个指向 -lshaderc_shared）

**怎么判断编没编进去**（比看 meson 日志可靠）：

    grep -a 'Initialized SPIR-V compiler' libmpv.so

这条 slog 在 `compilers[]` 为空时是死代码，字符串会被编译器消除。所以
**有 = 至少一个编译器在；没有 = Vulkan 必然起不来**。`build_android.sh`
已把这条做成构建期断言（还有 `shaderc_compile_into_spv`）。

> 反例参考：`NextPlayerCloud/NeoPlayer` 自带的 libmpv 两个字符串都有、
> 并且链了 glslang（`_ZN7glslang` 上千个符号），所以它的 `androidvk` 能用。

**Vulkan 下 hwdec 必须 copy-back**：MediaCodec 直通（HW+）输出的是
ANativeWindow Surface，Vulkan 没有帧导入互操作 → 解码成功但出不了画面。
`_sessionHwdec()` 因此收敛到 `mediacodec,mediacodec-copy,no`。

### mpv 属性字段名必须查源码，不能凭印象

697 真机回归：面板把杜比 P5 显示成「非 DV 内容」。根因是凭空写了
`video-params` 里不存在的 `dovi-profile` 字段。事实是：

| 想读 | 错误写法 | 正确路径 |
|---|---|---|
| DV Profile | `video-params/dovi-profile` | `current-tracks/video/dolby-vision-profile` |
| DV Level | `video-params/dovi-level` | `current-tracks/video/dolby-vision-level` |
| 信号峰值 | 直接当 nits | `video-params/sig-peak` 是 `max_luma/100` 的**倍数**，×100 才是 nits |

**更隐蔽的坑**：测试会「通过」——因为断言的是自己的错误假设
（`jsonEncode({'dovi-profile': 5})` 当然能解析出 5）。防法是把 mpv
真实字段表固化进 `test/services/mpv_field_names_697_test.dart`。

**鸿蒙限制**：`MpvLib` 只暴露 `getProperty`(number) / `getPropertyBool`
/ `getPropertyString`，**不支持 NODE**——整块 `video-params` 读出来是
空串。必须走**标量子属性**路径（`video-params/primaries` 这种）。

### QML 的 `font.pixelSize` 只接受整数

写 `font.pixelSize: 10.5`（想对齐 Flutter 的 10.5px）不会「四舍五入」，
而是报：

    Invalid property assignment: int expected

后果不是字号不准，而是**整个 Overlay.qml 加载失败** → Windows Qt 播放窗
启动即回退到 Flutter 内置窗口。CI 的「QML 冒烟自检」能抓到，但装机前
就该避免：需要小数时用整数近似。

**更隐蔽的变体（699 真机）**：同样的错误写在 `Repeater` 的 delegate 里
**不会崩整个 Overlay**，只会让**该 delegate 创建失败**：

    面板显示「弹幕 总 3353 · 在屏 20」，画面里一条弹幕都没有

根因是 `fontSize = 25 × danmakuFontSize(0.5) = 12.5`。排查线索：同文件
里其他字号（`Theme.captionSize`=12 等）全是整数，**只有弹幕那处是算出来
的小数**。所以凡是「算出来的字号」，一律

    readonly property int fontSize: Math.round(base * scale)

声明类型也要写 `int`（写 `real` 会让 QML 认为可能收到小数）。

### QML 属性名不能遮蔽全局单例（`playerState`）

`playerState` 是 `qmlRegisterSingletonInstance` 注册的**全局单例**。
在子组件里再声明同名属性会**遮蔽**它：

```qml
// DanmakuLayer.qml —— 错
property var playerState: null
// Overlay.qml
DanmakuLayer { playerState: playerState }   // ← 自赋值！
```

QML 报 `Binding loop detected for property "playerState"`，然后读到 null。
699 真机的后果是**弹幕时钟恒 0**（`currentPos()` 拿不到
`danmakuPositionMs`）→ 时间窗全被判「超前过多」丢弃 → 一条都不画，
而面板仍然显示「在屏 20」（那个数由 Dart 侧算，与 QML 无关）。

**正确做法**：换个名字传引用，例如 `stateRef: playerState`。
CI 的 QML 冒烟自检会把这条 `WARN` 打出来——**别忽略冒烟日志里的
Binding loop**，它不是噪音。

### 弹幕数据源要跟着播放位置推进（两条推送链路不同）

安卓/鸿蒙与 Windows Qt 走**完全不同**的推送链路：

| 端 | 链路 | 节拍 |
|---|---|---|
| 安卓 / 鸿蒙 | `_pushNativeUiState()`（同进程原生宿主） | **200ms 轮询**（`_pollTimer`） |
| Windows Qt | `_syncNativePanelData()` → `qt.pushNativeState()` | 仅**事件**触发 |

所以给安卓/鸿蒙加「每帧重算」的东西（如弹幕时间窗 `_buildDanmakuWindow`），
在 Qt 侧**不会自动生效**——必须显式挂到 `_positionTimer`（500ms）里。
699 真机症状：面板「总 3353 · 在屏 0 · 时钟 145030ms」（时钟对、窗口死）。

> 排查口诀：**时钟对 + 在屏 0** ⇒ 数据窗口没跟着位置重算，不是渲染问题。

### 弹幕匹配与弹幕弹窗（694 M1–M5，借鉴 NeoPlayer 只抄设计）

匹配链路（四端同构，Dart 单实现）：

```
匹配记忆（持久，manual 永久/auto 30 天）→ 6h 内存缓存
  → match(剧名.SxxExx，619 系列名重试) + search 并行
  → 8 桶排序（集号命中+同年/错源排除/年份降权）+ 同桶相似度 tiebreak
  → 逐候选试（上限 12）
```

多服务器：**并发**搜索 + 严格优先级仲裁（`runDanmakuServers`——低优先级
先到也等高优先级定局；高优先级命中立即返回）+ 每源 15s 超时。
记忆仓库（`DanmakuMatchMemory`）写操作串行化，防并发命中丢条目。

**弹幕弹窗**：全平台「点击弹幕开关按钮 → 弹窗」（不搞长按）。弹窗内含
动效开关（视觉主角）+ 绑定状态 + 搜索/换绑 + 解除绑定；入口按钮图标随
开关状态变色。四壳同构：Flutter `DanmakuControlSheet` / Windows Qt
`DanmakuPanel.qml` / Android TV `PANEL_DANMAKU` / 鸿蒙 ArkTS
`DanmakuPanel.ets`（挂 `NativePlayerPanel` 分发），搜索绑定全在
`DanmakuSearchController`（壳只发命令 + 渲染状态回流
`danmakuBinding`/`danmakuSearchResults`）。TV 无输入法：空关键词 = Dart
用预填标题直接搜索。绑定 = 写 manual 记忆 + `_loadDanmaku(force)`，
走「记忆优先」路径立即生效；匹配失败文案指向弹窗入口。

> 鸿蒙壳教训：**播放器 UI 是 ArkTS 原生**（`himi_mpv_ohos` HAR 的
> `HimiNativePlayerView` 子窗口），不是 Flutter——弹幕弹窗这类播放器内
> UI 改动必须四壳齐改，鸿蒙壳别漏。ArkTS 不踩 QML 的 pixelSize/属性
> 遮蔽坑，但 @State 必须 build 显式读取（589 教训，本壳经 @Prop
> revision + 宿主快照驱动）。

### media_kit 不是引擎（694 引擎收敛，别再混）

引擎收敛表（`PlayerEngineFactory.supportedEngines`，681 起）：

| 平台 | 引擎 | 播放器内切换 |
|---|---|---|
| Android 手机 | 仅 MPV | ✗ |
| Android TV | MDK / Erika / MPV | ✓ 底栏 |
| HarmonyOS | 仅 MPV | ✗ |
| Windows | 仅 MPV（Qt 独立播放窗） | ✗ |
| iOS / iPadOS | 仅 Erika | ✗ |

**`media_kit` / `media_kit_video` 包 ≠ media_kit 引擎**。media_kit 引擎层
（`NipaMediaKitAdapter` / `MediaKitPlayerAdapter` / `PlayerEngine.mediaKit`）
已随 694 死码清理整体移除——它不属于表中任何平台。但这两个包**活得很好**：
它们是 **himi_mpv（MPV 引擎）的 libmpv 驱动 + 纹理通道底层库**，
`himi_mpv_android` / `himi_mpv_windows` 直接使用其 `Player` /
`VideoController`（"libmpv 由 media_kit 驱动"）。同理
`media_kit_libs_android_video` / `media_kit_libs_windows_video` 是
**libmpv 原生库供给包**（安卓 `System.loadLibrary("mpv")` 的 jar、
Windows `libmpv-2.dll`），CI 经 `MEDIA_KIT_ANDROID_LIBMPV_DIR` /
`MEDIA_KIT_LIBMPV_DIR` 换自建完整版。**删依赖前先问：谁在消费 libmpv？**

连带事实：MPV 引擎 **texture 档路径恒为 `vo=gpu`**（`resolveMpvVo`）——
media_kit 的 Android `VideoController` 走 TextureRegistry Surface + wid +
vo=gpu，传别的值 `VideoOutput.Resize` 永不触发 → 纹理 id 恒 null。
iOS 走 Erika 不消费 libmpv，**不带** `media_kit_libs_ios_video`，
`MediaKit.ensureInitialized()` 只在安卓/Windows 调。

### 鸿蒙本地构建所需工具链

`scripts/build_ohos_local.sh` 会自动探测，但需知道这些位置：

| 依赖 | 位置 | 缺失时的报错 |
|---|---|---|
| `npm` | `~/harmonyos-clt/tool/node/bin` | `ProcessException: Failed to find "npm"`（栈全是 flutter_tools 内部帧） |
| `java` | `~/.local/jdk-17.0.21+9-jre/bin` 或 DevEco JDK | `Error Code: 00308018 / spawn java ENOENT` |
| `hvigorw` | `~/harmonyos-clt/bin` 或 `~/harmonyos-clt/hvigor/bin` | `ProcessException: Failed to find "hvigorw"`（`assembleHap` 直接 exec 它） |
| SDK 根 | `~/harmonyos-clt/sdk` | `ohos_pack.sh` 直接退出 |

`OHOS_BASE_SDK_HOME` 与 `DEVECO_SDK_HOME` 需**同时**设置。
