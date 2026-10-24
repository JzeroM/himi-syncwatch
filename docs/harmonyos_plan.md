# HIMI 鸿蒙版分阶段开发计划（定稿存档）

> 状态：**定稿存档 v1.1（2026-10-13）——通道保留，暂缓开发**。以下结论已全部核实，开工时可直接引用，无需重新调研。
> 前提：Linux / macOS 已暂停支持并从 CI、README、仓库平台目录中移除；Android / iOS / Windows 三平台不受影响。
> README 平台表「HarmonyOS | 规划中」行保留，作为通道标记。

---

## 0. 存档决策摘要（用户已确认）

| 决策点 | 结论 |
|--------|------|
| 播放器 | **Erika 唯一引擎**（不引入 MDK / AVPlayer / media_kit 兜底）；失败即报错 + 日志上报，Erika 内含 FFmpeg 软解自兜底 |
| 版本基线 | HarmonyOS 6.0（API 20）起步 / 编译 SDK 26.0.0 / Flutter-OH `3.41.9-ohos` / DevEco Studio 26.0.0；主线 Flutter 3.47.4 不动 |
| 分发 | 双轨通道：GitHub Releases（调试签名 + UDID + hdc）先发测试包；正式分发仅 AppGallery 上架（发布签名 + APP 备案 + 隐私政策） |
| 华为账号 | ✅ 个人开发者已认证（ID 2850086000462423996） |
| CI | GitHub Actions **可**编译鸿蒙（无托管 runner，需自装 SDK CLI；详见 §4 阶段 5） |
| 开发节奏 | **暂缓**：阶段 0 未开工，以下分阶段计划保留待启用 |

---

## 1. 可行性结论

**可行，路线：双 SDK 工具链 + 纯 Dart 层复用 + Erika 单引擎 + 关键原生能力项目内桥接。**

| 关键环节 | 结论 | 依据 |
|---------|------|------|
| Flutter 鸿蒙框架 | ✅ 可用（有版本差） | CPF-Flutter 维护 `flutter_flutter` OpenHarmony 适配版；2026-07-06 发布 **Flutter 3.41 适配 Beta**（`oh-3.41.9-dev` 分支，tag `3.41.10-ohos-0.0.1-canary1`）；3.35.7 起可源码构建引擎。本项目主线为 Flutter 3.47.4，**存在约 6 个次版本差**，3.47 适配按官方路线图 2026-12 |
| 纯 Dart 业务层 | ✅ 直接复用 | Emby API（dio）、Riverpod 2、GoRouter、模型/路由/服务层均不依赖平台通道 |
| 视频播放 | ✅ **Erika 唯一引擎** | 本仓库 vendored `third_party/erika_flutter` 0.2.1 **自带完整 `ohos/` 模块**（pubspec 已声明 `ohos: pluginClass: ErikaFlutterPlugin`）+ **预编译 `liberika_capi.so`**（`native_artifacts.properties` 含 `ERIKA_OPENHARMONY_ARM64_SHA256`）；与 Android/iOS/Windows 同源。上游 AimesSoft/Erika 另有 `erika_ohos` OHPM 包；同门应用 NipaPlay-Reload v1.11.8 已发布鸿蒙版 |
| 多人观影 RTM | ✅ SDK 存在 | 声网 RTM 2 有 HarmonyOS 文档线（`doc.shengwang.cn/doc/rtm2/harmonyos`）；RTC 鸿蒙以 ohpm 包形态发布（`@shengwang/rtc-full`）。RTM 鸿蒙包名/形态需在开工前最终确认 |
| 插件生态 | ⚠️ 部分需适配/项目内实现 | CPF-Flutter `flutter_packages` 已适配官方常用插件；RTM/动态图标等需项目内 ArkTS 桥 |
| 构建与上架 | ⚠️ 需新工具链 | DevEco Studio + HarmonyOS SDK + 华为 AGC 签名 + AppGallery 审核；GitHub Actions 无托管 runner 但**可自装 SDK CLI 构建**（华为官方《Setting Up a Pipeline》：`developer.huawei.com/.../ide-command-line-building-app`；社区先例：`harmonyos-dev/harmonyos-github-action-example`） |
| 签名与分发 | ⚠️ 强制签名 | 「只有签名过的 HAP 才允许安装到设备」（华为官方）；发布证书包**本地装不上**（NEXT 只认市场分发包或调试签名包）；详见 §8 |

---

## 2. 目标与非目标

**目标**
- 鸿蒙版与现有三平台共用同一套 `lib/` 业务代码。
- 首版达到：登录 / 浏览 / 搜索 / 播放（含线路切换、字幕基础能力）可日常使用。
- 后续版本补齐：多人观影房间、弹幕、HDR 路由、TV 模式。

**非目标（首版明确不做）**
- 不做 macOS/Linux 恢复（已暂停）。
- 不承诺与主线 Flutter 同版本（受 Flutter-OH 发布节奏制约）。
- HDR/PGS/DV 能力以 Erika 实测为准（引擎层已具备，见 §3.3/§3.4），POC 未过前不写入对外承诺。

**版本矩阵**

| 项 | 版本 | 说明 |
|----|------|------|
| Flutter-OH（鸿蒙工具链） | `3.41.9-ohos`（canary `3.41.10` 可观望） | 唯一稳定适配线；不等 3.47（2026-12） |
| 主线 Flutter（三平台） | 3.47.4 不动 | 双 SDK 互不干扰 |
| 鸿蒙 SDK 编译目标 | 26.0.0 | DevEco Studio 26.0.0 Release（2026-08-28，官方新应用推荐） |
| `compatibleSdkVersion` | API 20（HarmonyOS 6.0） | 华为官方对新应用的推荐下限；存量设备覆盖 ≈99.97%（API 5.x 老设备 <0.5%） |
| 设备主力 | HarmonyOS 6.1 / 7.0 | 存量占比参考：API 24 ≈82.4%、API 26 ≈10.8%、API 23 ≈4.6% |
| Erika vendored 约束 | `flutter >=3.24.0` / `dart >=3.5.0` | 与 Flutter-OH 3.41.9 兼容 |

---

## 3. 总体架构

```
                    ┌──────────────────────────────────────┐
                    │        纯 Dart 业务层（复用）          │
                    │  Emby API / Riverpod / GoRouter      │
                    │  弹幕 / 房间状态机 / 引擎路由规则        │
                    └───────────────┬──────────────────────┘
                                    │ Platform Interface（现有抽象）
          ┌─────────────────────────┼─────────────────────────┐
          │                         │                         │
   Android/iOS                  Windows                   HarmonyOS
   Flutter 3.47.4              Flutter 3.47.4            Flutter-OH 3.41.9
   ├ MDK(fvp)                  ├ MDK(fvp)               ├ 播放器：Erika（唯一引擎）
   ├ Erika                     └ media_kit(libmpv)      │        （vendored ohos 模块）
   └ agora_rtm 官方插件                                  ├ RTM：himi_ohos_rtm 项目内插件
   himi_windows_rtm（Windows 项目内）                       └ 常用插件：CPF-Flutter 适配版
```

### 3.1 关键决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 工具链 | 双 SDK：主线 Flutter 管三平台，Flutter-OH 管 `ohos/` | Flutter-OH 与主线版本不齐，同仓双工具链互不污染；CI 中鸿蒙构建独立 job |
| 仓库形态 | 同仓库新增 `ohos/` 平台目录 + `plugins/himi_ohos_rtm/` | 与现有 `himi_windows_rtm` 对称；`lib/` 单份源码 |
| **播放器** | **Erika 唯一引擎，无 MDK/AVPlayer 兜底** | vendored 已带 ohos 模块与预编译 so，零集成成本；与三平台同源，弹幕/PGS/DV/字幕能力对齐；单一引擎维护面小；`resolveEngineForContent` ohos 列恒指 Erika |
| RTM | 项目内 `himi_ohos_rtm`（ArkTS 桥） | 与 Windows 项目内插件同构，复用 `RtmBackend` 抽象，官方 flutter 插件不支持 ohos |
| 版本基线 | 主线保持 3.47.4 不动；鸿蒙锁 Flutter-OH 3.41.9 | 避免主线为鸿蒙降级；`lib/` 写法向下兼容（不用 3.47 新 API、依赖两边可解析、pubspec.lock 单独处理） |

### 3.2 Erika vs MDK 选型对比（存档：已选 Erika，MDK 弃用）

| 维度 | Erika（已选） | MDK-OHOS（弃用，仅外部参考） |
|------|--------------|------|
| 与本项目关系 | ✅ 同源：三平台已用 Erika，鸿蒙同一套 `erika_flutter` API，`Engine` 抽象零改动 | fvp 无 ohos 后端；官方 ohpm 包 `@mediadevkit/libmdk-napi` 是 ArkTS/NAPI 形态，接 Dart 需项目内桥 |
| 集成成本 | ✅ vendored 已内置 ohos 模块 + 预编译 so | ⚠️ ohpm 包 + 自写胶水 |
| 渲染链路 | ✅ 外部纹理 → OHNativeWindow → wgpu Vulkan；AVCodec 硬解零拷贝；OHAudio；AVSession 全封装 | OH 硬解 0-copy + OHAudio，但 Flutter 宿主对接需自接 |
| 弹幕 | ✅ 原生 DFM+ 碰撞轨道 + GPU 字形图集 | ❌ 无 |
| 编解码/字幕 | ASS/libass + PGS + AVCodec H.264/HEVC + FFmpeg 软解兜底 | ✅ 更广（AV1/VP9/杜比视界/HDR10 直通、libass） |
| 成熟度 | ⚠️ ohos 路径较新，bug 需自修（Rust 可修，MPL-2.0） | ✅ 商业级久经考验 |
| 模拟器 | ⚠️ prebuilt 仅 arm64（真机） | ✅ 支持 x86_64 |
| 授权 | ✅ 开源可复现构建 | ⚠️ 闭源二进制，条款需核对 |

### 3.3 杜比支持结论（Erika）

| 项 | 状态 |
|---|---|
| **DV Profile 5**（IPTPQc2 纯 DV） | ✅ 移动端后端（MediaCodec / **ohos AVCodec 同属 generic AvCodec 后端**）硬解拿不到 RPU side data 时**自动回退 FFmpeg 软解**（`dolby_vision_decode_fallback()`，有单元测试）；RPU→shader 渲染色彩正确 |
| **DV Profile 8**（8.1 HDR10 / 8.4 HLG 兼容基底） | ✅ 保持硬解；RPU 缺失时基底色彩依然正确 |
| **DV Profile 7**（双层 FEL/MEL） | ⚠️ 不合成增强层，仅基底映射 + 诊断上报（**与 mpv 行为一致**） |
| 渲染管线 | 跟随 libplacebo/mpv：逐帧 RPU reshape（多项式/MMR）→ PQ 线性化 → L1 亮度自适应 tone map（BT.2390 默认）→ IPT 感知色域 LUT；shader 三份 WGSL/Metal/HLSL，**ohos wgpu Vulkan 正用 WGSL** |
| Atmos 音频 | ⚠️ Erika 音频为 f32 PCM 输出（ohos 走 OHAudio），无数字直通 → E-AC-3 JOC 解码为多声道 PCM 播放（功能正常，非授权 Atmos 渲染；手机扬声器/蓝牙场景无实际损失） |
| 授权注意 | DV 渲染实现参照 mpv/libplacebo 开源先例（非 Dolby 授权代码） |
| **POC 验证项** | 真机 DV P5/P8 样片色彩对比 Android（含 HDR Vivid 屏幕协同） |

### 3.4 字幕调节能力结论（鸿蒙可用，零新增开发）

| 调节项 | Erika 引擎 API | HIMI 现有接入 |
|--------|---------------|--------------|
| 大小 | `setSubtitleScale()` + `setSubtitleStyle(fontSize 8~400、scaleX/Y%)` | ✅ 已接：`erika_player_adapter.dart:478-543`（`subtitle.scale`/`subtitle.font.size`，100ms 合并下发） |
| 位置 | `setSubtitleStyle(alignment)`（ASS 九宫格 1~9，默认 2=底部居中）+ `marginLeft/Right/Vertical` | ✅ 已接：`subtitle.margin.y` → `marginVertical`（`erika_player_adapter.dart:486`）；左右边距 API 在（默认 48/48/54） |
| 延迟 | Erika 无引擎级字幕 delay（其 offset 为弹幕：`setDanmakuGlobalOffset`） | ✅ **HIMI 在 Dart 层解决，引擎无关**：`SubtitleShifter` 改写 SRT/ASS 时间戳 + 重载字幕轨（`player_screen.dart:7441` `_maybeApplySubtitleDelay`），鸿蒙原样生效 |

注：PGS 位图字幕为栅格，样式/缩放不适用（全平台同理）；弹幕另有原生 `setDanmakuTrackOffset`/`setDanmakuGlobalOffset`。

---

## 4. 分阶段计划（保留待启用，未开工）

### 阶段 0：环境与 POC（预计 3~5 天）

**目标**：证明「本仓库代码能在鸿蒙上跑起来」。

- [ ] 安装 DevEco Studio 26.0.0 + HarmonyOS SDK（编译 26.0.0，compatibleSdk API 20）。~~注册华为开发者账号~~ ✅ 已完成（个人已认证，ID 2850086000462423996）。
- [ ] 部署 Flutter-OH `3.41.9-ohos`，`flutter create --platforms ohos` 生成 `ohos/` 目录。
- [ ] 将本仓库 `lib/` 接入：`flutter pub get` 通过（统计依赖中不可用插件清单）。
- [ ] **erika_flutter ohos 模块实测**：`liberika_capi.so` CMake 下载校验、Vulkan 外部纹理起播、AVCodec 硬解 H.264/HEVC、OHAudio。
- [ ] **DV P5/P8 样片真机色彩对比 Android**（§3.3 POC 项）。
- [ ] hvigor `modelVersion` ↔ DevEco 兼容核对（模板配套，hvigor-config 不得高于 DevEco 配套版本）；Flutter-OH API 基线核对。
- [ ] POC 验收：真机上出现 HIMI 启动页，进入服务器配置页。
- [ ] 输出物：《依赖插件鸿蒙可用性核对表》（逐个标记：CPF 适配版可用 / 需项目内实现 / 可移除）。

**验收标准**：POC HAP（调试签名）安装到真机，应用可启动不闪退；核对表覆盖 pubspec 全部运行时依赖。

### 阶段 1：登录、浏览与基础播放（预计 2~3 周）

**目标**：核心 Emby 客户端体验闭环。

- [ ] 播放器适配层：**唯一引擎 Erika**——在 `PlayerEngine` 抽象下接 `erika_flutter` ohos 模块；`resolveEngineForContent` 平台矩阵补 ohos 列（恒指 Erika）；无引擎对比、无 AVPlayer 兜底，打不开文件时报错 + 日志上报。
- [ ] 逐个接入必需插件：`flutter_secure_storage`、`path_provider`、`permission_handler`、`file_picker`、`image_picker`、`share_plus`、`url_launcher`（CPF 适配版），不可用者项目内 ArkTS 插件。
- [ ] 字幕：**大小/位置/延迟三项鸿蒙已可用（§3.4）**，验证外挂 srt/ass + Emby 内封轨；PGS 位图由 Erika 验证。
- [ ] 起播性能与 seek 精度回归测试（对齐 Android 基线用例）。

**验收标准**：登录 → 浏览 → 详情 → 播放 → 选集/换线路全流程可用；1475 个存量测试在主线保持全绿（鸿蒙改动通过平台分支隔离，不破坏现有平台）。

### 阶段 2：体验补齐与插件完善（预计 1~2 周）

- [ ] 弹幕（弹弹 Play 协议为纯 Dart + dio，预期直接可用；Erika 弹幕轨道/偏移 API 原生支持，重点验证时间轴渲染性能）。
- [ ] 液态玻璃 UI / 多图标集（纯 Dart + shader，验证 Impeller-on-OHOS 兼容性）。
- [ ] 亮度 / 唤醒锁 / 传感器（`screen_brightness`、`wakelock_plus`、`sensors_plus` 按核对表处理）。
- [ ] 应用图标（鸿蒙 Shortcuts/OpenLayer 替代 `flutter_dynamic_icon_plus`）。

**验收标准**：功能矩阵表与 Android 版逐项对照，明确「支持 / 降级 / 不支持」三态并在 README 鸿蒙行披露。

### 阶段 3：多人观影 RTM（预计 1~2 周）

- [ ] 确认声网 RTM 2 鸿蒙 SDK 包名、下载与鉴权方式（对照 `doc.shengwang.cn/doc/rtm2/harmonyos`）。
- [ ] 新建 `plugins/himi_ohos_rtm`：ArkTS 插件封装，MethodChannel 协议对齐 `himi_windows_rtm`（消息流 / Presence 流 / 错误码）。
- [ ] `rtm_backend_factory.dart` 新增 ohos 分支；复用现有房间状态机、二维码加入、同步控制全部 `lib/` 逻辑。
- [ ] 双端互通测试：Android 房主 ↔ 鸿蒙加入者（反之亦然）。

**验收标准**：`RtmBackend` 全部接口在 ohos 有实现；冒烟用例（对齐 `HIMI_RTM_SMOKE` 思路）通过；跨平台互通至少完成 10 次连续进出房间无泄漏。

### 阶段 4：高级功能与降级决策（预计 1~2 周，可与阶段 3 并行）

- [ ] HDR 路由：Erika 自渲染管线不依赖系统 HDR 协商；验证鸿蒙 HDR Vivid 屏幕协同与 DV 色彩（承接阶段 0 POC），不通则 ohos 隐藏 HDR 开关。
- [ ] TV 模式：鸿蒙智慧屏形态待评估，首版可标记不支持。
- [ ] 后台播放 / 音频焦点（AVSession + 鸿蒙 audio session）。
- [ ] 倍速、音轨切换、画面比例等播放器子项逐一对齐。

### 阶段 5：CI、签名与上架（预计 1 周 + 审核等待）

- [ ] CI：release.yml 新增 `build-ohos` job——**GitHub Actions 可行**：自装 Flutter-OH + HarmonyOS Command Line Tools（含 ohpm/hvigorw/hdc/hap-sign-tool，无需 DevEco GUI），`hvigorw assembleHap` 构建。坑点：SDK 下载地区限制（镜像 `harmonyos-dev/hos-sdk`、`user.country=CN`）、360 分钟上限（`timeout-minutes`）、actions/cache 缓存 SDK/oh_modules、签名材料入 GitHub Secrets。保留 `workflow_dispatch` 手动 fallback。
- [ ] 签名：AGC 创建应用、申请证书与 Profile（发布证书 + 发布 Profile 供上架；调试证书 + UDID Profile 供 GitHub Releases 测试包）。⚠️ 发布证书签的 HAP 本地装不上，测试分发必须用调试签名。
- [ ] 分发双轨：GitHub Releases 挂调试签名 HAP（附 hdc 安装说明：开发者模式 + `hdc install`）；AppGallery 上架为正式渠道。
- [ ] 应用市场材料：图标、截图、隐私政策（RTM 涉及网络通信与麦克风/摄像头权限，需隐私声明）+ APP 备案（接入商代备，选「鸿蒙」平台）。
- [ ] 上架 AppGallery 审核（预留合规整改时间；审核 1~3 工作日）。
- [ ] README 平台表鸿蒙行由「规划中」改为正式支持 + 下载链接。

**验收标准**：AppGallery 审核通过（或拿到明确驳回项清单）；GitHub Releases 测试包可被登记 UDID 的设备安装。

---

## 5. 风险清单

| # | 风险 | 影响 | 缓解 |
|---|------|------|------|
| R1 | Flutter-OH 停在 3.41.x，主线 3.47.4 的新 API/依赖在 ohos 编不过 | 阻塞 | `lib/` 避免使用 3.47 新增 API；依赖锁版本；跟踪 CPF-Flutter 3.47 适配进度（路线图 2026-12）；写法向下兼容（pubspec.lock 单独处理） |
| R2 | **Erika 单引擎无备用**：ohos 路径较新，机型 bug 无替换项 | 播放体验 | Erika 为 Rust 源码可自修（MPL-2.0）；FFmpeg 软解内兜底；阶段 1 即建真机兼容测试清单（旗舰 + 中端各 1）；vendored 版本锁定可打补丁 |
| R3 | 声网 RTM 鸿蒙 SDK 形态与预期不符 | 阶段 3 返工 | 阶段 0 即拉取 RTM 鸿蒙文档与示例做 2 天技术验证 |
| R4 | 插件缺口需大量项目内 ArkTS 桥 | 工期 | 核对表前置（阶段 0 交付）；缺口按「项目内 / 替代 / 砍功能」三分决策 |
| R5 | ~~media_kit/Erika 不可用~~ **已收窄**：media_kit 不引入鸿蒙（仅 Windows HDR）；Erika 可用（DV/PGS/字幕齐备），剩余风险仅「Erika ohos 实测兼容性」 | 功能验证 | 阶段 0 POC 项覆盖（DV 色彩对比、硬解、软解回退） |
| R6 | GitHub Actions 无官方鸿蒙 runner | CI | **已降级**：CLI 构建可行（官方文档 + 社区 action 先例），仅需应对坑点（镜像/超时/缓存/Secrets）；保留手动 workflow_dispatch |
| R7 | AppGallery 审核（权限、版权内容、SDK 合规） | 上架 | 提前写隐私政策；APP 备案前置；RTM/RTC SDK 需附声网合规说明；预留 2 轮审核时间 |
| R8 | 真机碎片化（API 20+ / 智慧屏差异） | 测试 | 阶段 1 起建立真机测试清单（至少 2 台：旗舰 + 中端） |

---

## 6. 工作量估算汇总

| 阶段 | 内容 | 估算 |
|------|------|------|
| 0 | 环境 + POC + 依赖核对表 + Erika/DV 验证 | 3~5 天 |
| 1 | 登录/浏览/基础播放（Erika 唯一引擎） | 2~3 周 |
| 2 | 弹幕/UI/杂项插件 | 1~2 周 |
| 3 | RTM 多人观影 | 1~2 周 |
| 4 | HDR/TV/后台等高级项 | 1~2 周（可并行） |
| 5 | CI/签名/上架 | 1 周 + 审核等待 |
| **合计** | | **约 7~10 周**（阶段 3/4 并行时取下限） |

---

## 7. 每阶段通用交付规范

1. 每阶段开工前更新本文档勾选状态；交付时附测试结果（主线 1475 测试须保持全绿）。
2. 鸿蒙代码遵循现有模块化边界：平台差异只允许出现在 `PlayerEngine` / `RtmBackend` / 插件层，禁止污染业务层。
3. 阶段验收由用户确认后进入下一阶段；发现重大风险随时回本文档修订。

---

## 8. 签名与分发结论（存档）

**强制签名**：「只有签名过的 HAP 才允许安装到设备」（华为官方《配置应用签名》）。HAP 安装时校验证书链（.cer）+ Profile（.p7b，含包名/权限/设备清单）。

| 渠道 | 签名类型 | 安装/分发方式 | 限制 |
|------|---------|--------------|------|
| **GitHub Releases（测试通道，保留）** | **调试证书**（每账号最多 3 张，实名有效期 1 年）+ 调试 Profile（绑定设备 UDID） | `hdc install` / DevEco / HiSuite，设备需开发者模式 | 每台新设备需登记 UDID 重新签 Profile；普通用户无电脑 hdc 难安装；DevEco 自动签名可直接绑定连接的设备 |
| AppGallery（正式渠道） | **发布证书** + 发布 Profile，打 App Pack（.app）上传 AGC；市场分发时拆分重签名 | 应用市场 | 需 APP 备案 + 隐私政策 + 审核（1~3 工作日）；备案由接入商代备，平台选「鸿蒙」 |
| ⚠️ 已知坑 | 发布证书签的 HAP **本地装不上**（NEXT 只认市场分发包或调试签名包） | — | 测试分发不要用发布签名 |
| 官方折中 | AGC「指定设备发布」（原内部测试）：上传包 + Deeplink 下载页 / HDC 安装 | 测试性质 | 非公开分发 |

---

## 9. 待用户确认（开工前）

1. 首版功能范围（基础版 / 基础+RTM / 全量对齐）——决定阶段 3、4 是否进入首版。
2. 阶段 0 开工时机（本存档批准后随时可启用；暂缓期间 README 保持「规划中」）。
