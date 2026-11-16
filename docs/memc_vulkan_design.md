# MEMC 补帧技术方案（mpv 内部 · libplacebo Compute）

> 状态：方案定稿（未实施）
> 目标端：**安卓手机 / 安卓 TV / 鸿蒙 / Windows**（均为 MPV 引擎）
> 开发载体：安卓（唯一有 CI 快回路）；鸿蒙/Windows 只做接入与驱动差异纠偏
> 编写依据：NeoPlayer v1.7.4 的 APK 逆向分析（自定义 `libmpv.so` 的 GPU motion 引擎）+ 我们现有管线
> 决策：**只做 MEMC，不提供帧混合（interpolation）档位**

---

## 0. 一句话结论

真 MEMC（运动补偿插帧）在 **mpv 的 libplacebo 渲染链内部**实现：
抓 2 帧 → 金字塔粗估光流 → 细化 → 前后向一致性/遮挡 → warp → 按 alpha 合成 → 上屏。
算力分配照抄参考实现：**运动分析压到 ≤480p，合成按源分辨率**。
**HDR / DV 内容一律 bypass**，因此不动我们已完成的 HDR/DV 链路。
引擎只依赖 libplacebo 抽象，**一份补丁同时编进 Vulkan（安卓/鸿蒙）与 D3D11（Windows）**。

---

## 1. 需求与边界

### 1.1 目标
- 24/30fps 的 SDR 内容，输出到屏幕刷新率（60/90/120）的 MEMC 插帧。
- 开关只有「开/关」；内部有质量档与目标帧率，但不对用户暴露过多组合。
- 任何条件不满足时**自动旁路**，面板显示原因。
- 面板可观测（合成帧数、耗时、旁路原因）。

### 1.2 明确不做
- **不做帧混合/`interpolation` 档位**。用户已决定：补帧只有 MEMC 一档，
  不满足条件就明确显示「未补帧」及原因，而非退化成混合（混合会带来双重影，误导观感）。
- 不做 HDR/DV 补帧（旁路）。将来若要做，需要重新评估 DV 元数据与 DataSpace 的传递，
  不在本方案范围内。
- 不接神经网络插帧（RIFE 类）：移动端 4K 撑不住，模型体积也不划算。
- 不改现有 HDR 直出、DV DOVI 重塑、`gpu-context` 优先级列表。

### 1.3 「不提供帧混合」带来的 UX 约束

| 场景 | 行为 |
|---|---|
| 开关打开且条件满足 | 输出补帧画面 |
| 开关打开但 HDR / 高帧率源 / 变速 / 过热… | **旁路**：原样输出，面板标「补帧未生效：原因」 |
| 开关关闭 | 原样输出（与今天逐字节等价） |

设置项文案需要明确写「HDR 内容不支持补帧」，避免用户以为坏了。

### 1.4 参考实现的能力面（从 APK 提取，用于对齐 UX）

| 维度 | 参考实现取值/行为 |
|---|---|
| 目标帧率 | 2x / 2.5x / 3x / 4x / 屏幕刷新率 |
| 质量档 | better performance / better quality |
| 伪影抑制 | off / weakest / weak / medium / strong |
| 动画优化 | 线条轮廓保护 + 平滑一拍二/一拍三 |
| 旁路规则 | `bypass_hdr` / `bypass_pip` / `bypass_speed` / `bypass_high_fps` / `bypass_overheating` |
| 遥测 | 合成帧/秒、呈现帧/秒、分析分辨率、实时 fps |

参考实现的 pass 链（从其日志与内嵌 GLSL 还原）：

```
capture → coarse → refinement → evidence → reconstruction → warp → synthesis
日志：GPU motion interpolation enabled: target=%d fps,
      analysis<=480 pixels, synthesis=source resolution.
```

---

## 2. 为什么放在 mpv 内部

1. **不动视图链路**：我们已验证的 HDR/DV Surface 逻辑零改动；旁路就是走原渲染路径，
   不需要切换 Surface、不会黑屏/重建 vo。
2. **零额外拷贝**：源帧本来就是 libplacebo 的 `pl_tex`，直接在同一个 `pl_gpu` 上算，
   省掉一次全帧拷贝与一条缓冲队列。
3. **音画同步最准**：alpha 直接用 mpv 的 audio clock 与 frame pts 计算，长播不漂移。
4. **HDR 天然兼容**：同一个 swapchain 与 DataSpace；将来要做 linear 光域补帧也是同一条路
   （参考实现就有 `linear_hdr` 参数）。
5. **单一图形 API**：全 Vulkan，shaderc / SPIR-V 已在 697 打通并在真机验证。

代价（已知并接受）：新增第 3 个内核补丁，改 shader 要重编 libmpv（CI 约 30 分钟一轮），
开发反馈慢；因此 §8 的 A0 spike 必须先做。

---

## 3. 总体架构

### 3.1 在 mpv 里的位置

```
vo_gpu_next.c
  ├─ draw_frame()                       ← 唯一的视频呈现入口
  │    ├─ 新源帧到达：pl_render_image() 到 capture_ring[slot]
  │    └─ 每个 vsync：
  │         ├─ memc 关闭 / 条件不满足 → 原有路径（直接 render + swap）
  │         └─ memc 开启且有两帧      → 执行 memc pass 链 → 输出合成帧 → swap
  └─ 新增文件 video/out/gpu/memc.c/.h  ← 引擎本体（可编译期开关）
```

### 3.2 新增模块

| 文件 | 职责 |
|---|---|
| `video/out/gpu/memc.c/.h` | 引擎：资源管理、pass 调度、时间轴选择、遥测 |
| `video/out/gpu/memc_shaders.c` | 内嵌 GLSL compute（走 libplacebo 的 shader 预处理） |
| `video/out/gpu/memc_opts.h` | 选项定义（`--memc-*`） |
| `video/out/vo_gpu_next.c`（改） | 捕获与呈现挂钩、条件旁路 |
| `meson.build`（改） | `memc` 特性开关（默认 on，可 `-Dmemc=disabled` 完全摘除） |

### 3.3 运行时开关（mpv 选项，同时作为 property 暴露）

```
--memc=<auto|yes|no>                       默认 no
--memc-target-fps=<screen|2x|2.5x|3x|4x>   默认 screen
--memc-quality=<performance|quality>       默认 performance
--memc-artifact=<off|weakest|weak|medium|strong>  默认 weak
--memc-anime=<yes|no>                      默认 no
--memc-analysis-height=<360|480|720>       默认 480
--memc-stats=<yes|no>                      默认 no（面板遥测用）
```

---

## 4. 算法设计

### 4.1 pass 划分与分辨率

| pass | 分辨率 | 输出 | 说明 |
|---|---|---|---|
| capture | 源分辨率 | `capture[2]`（RGBA16F，或 R16F 仅亮度） | 只保留最近两帧 |
| preprocess | 分析分辨率（长边 ≤480） | 2 × luma + 3 级金字塔 | 高斯降采样 |
| coarse | 分析分辨率 / 4 | `flow_coarse`（RG16F） | 块匹配，16×16 块，搜索半径 R |
| refinement | 分析分辨率 / 2、/1 | `flow`（RG16F） | 由粗到细，候选集细化 |
| evidence | 分析分辨率 | `conf` + `occ`（RG16F / R8） | 前后向一致性 + 光度误差 |
| reconstruction | 分析分辨率 | `flow_smooth` | 3×3 中值 + 可选全局运动补偿 |
| warp | 源分辨率 | `warp0`, `warp1`（RGBA16F） | 双向 warp |
| synthesis | 源分辨率 | 输出帧 | alpha 混合 + 遮挡处理 + 场景保护 |

> 划分直接对齐参考实现日志里的
> `coarse-pass / refinement-pass / evidence-pass / reconstruction-pass / warp-pass / synthesis`，
> 以及 `analysis<=480 pixels, synthesis=source resolution`。

### 4.2 关键 shader 伪代码

**coarse（块匹配，SAD）**

```glsl
// 每线程输出一个 block 的粗光流
ivec2 blk = ivec2(gl_GlobalInvocationID.xy);
vec2 best = vec2(0.0); float bestCost = 1e20;
for (int dy = -R; dy <= R; ++dy)
  for (int dx = -R; dx <= R; ++dx) {
    float c = sadBlock(luma0, luma1, blk*BLK, vec2(dx,dy), BLK);
    if (c < bestCost) { bestCost = c; best = vec2(dx,dy); }
  }
imageStore(uOutCoarse, blk, vec4(best, 0.0, 1.0));
```

**refinement（候选集细化）**

```glsl
vec2 cand[6] = vec2[](
  vec2(0.0),                    // 零运动
  coarse * 2.0,                 // 上层光流上采样
  median4(mL, mR, mU, mD),      // 邻域中值（去孤立错误）
  best + vec2(-1,0), best + vec2(1,0),
  best + vec2(0,-1));           // 局部 ±1 精修
// 逐个评估 SAD 取最小；再对 4 邻域做一次 ±1 搜索
```

**evidence（置信度 + 遮挡）**

```glsl
vec2 fwd = texture(uFlow, uv).xy;
vec2 bwd = texture(uFlowBack, uv + fwd * invAnalysis).xy;
float fbErr = length(fwd + bwd);              // 前后向不一致 → 遮挡/不可信
float photoErr = sadPatch(luma0, luma1, uv, fwd);
float conf = exp(-fbErr * k1) * exp(-photoErr * k2);
bool occluded = fbErr > FB_THRESHOLD;
```

**reconstruction（中值滤波）**

```glsl
vec2 f = texture(uFlow, uv).xy;
vec2 m = median9(uv, uFlow);                  // 3x3 中值
imageStore(uOutFlow, gid, vec4(mix(f, m, 0.6), conf, occ));
```

**warp + synthesis（合成）**

```glsl
// 参考实现签名（二进制里提取到的原文）：
// vec4 synthesize_pixel(sampler2D source0, sampler2D source1,
//                      sampler2D warp0, sampler2D warp1, sampler2D scene_map,
//                      ivec2 pixel, vec2 output_extent, vec2 motion_extent,
//                      float alpha, bool linear_hdr);

vec3 c0 = texture(source0, uv - alpha * fwd).rgb;
vec3 c1 = texture(source1, uv + (1.0 - alpha) * bwd).rgb;

float w0 = conf0 * (occ0 ? 0.0 : 1.0);
float w1 = conf1 * (occ1 ? 0.0 : 1.0);
vec3 outRgb;
if (w0 + w1 < 1e-4) {
  // 不可信像素的兜底：逐像素两帧插值（不是「帧混合模式」，只是本像素的容错）
  outRgb = mix(c0, c1, alpha);
} else {
  outRgb = (c0 * w0 * alpha + c1 * w1 * (1.0 - alpha)) / (w0 * alpha + w1 * (1.0 - alpha));
}
// 场景切换：scene_map 命中 → 直接输出 c0（禁止跨场景插帧）
```

> 注意：`mix(c0, c1, alpha)` 只出现在**单个像素低置信度**的容错分支里，
> 不是可选的「帧混合」模式；整体观感仍是 MEMC。

### 4.3 时间轴与 alpha

- `alpha = (now - pts0) / (pts1 - pts0)`，`now` 由 VO 的 vsync 时钟给出。
- 目标帧率 `screen` 时按 vsync 逐次推进；`2x/3x/4x` 时按 `round(srcFps * n)` 生成时刻表。
- 音画同步：alpha 必须基于 **mpv 的 audio clock**（`mpctx->playback_pts`），不能基于系统时钟，
  否则会累积漂移。参考实现的 `notifySourceFrameAvailable(pts)` + `onVsyncTick(t)` 就是这个模型。

### 4.4 场景切换检测

- 分析分辨率下统计 `avg / avgMetric`（参考实现有 `ensureReductionResources`，就是干这个）。
- 亮度均值突变 + 全局 SAD 偏高 → 标记 `scene=1` → 该区间不插帧。

---

## 5. 算力与显存预算（四档）

### 5.1 各端目标档位

| 平台 | 目标分辨率 | 目标输出 | 分析分辨率 | 显存峰值 | 单帧耗时预算 | 说明 |
|---|---|---|---|---|---|---|
| 安卓手机 | 1080p | 120fps | 长边 480 | 70~100MB | **≤ 7ms**（120Hz 8.3ms） | 最紧的一档，决定算法下限 |
| 安卓 TV / 盒子 | 1080p~4K | 60fps | 1080p：480；4K：**360** | 100~140MB | ≤ 14ms（60Hz 16.7ms） | 2GB 内存盒子默认关闭 |
| 鸿蒙手机/TV | 同安卓 | 60~120fps | 同安卓 | 同安卓 | 同安卓 | 同一颗 SoC 量级，按安卓档位跑 |
| Windows 桌面 | 1440p~4K | 60~144fps | 长边 720 | 不受限 | ≤ 6ms | 桌面 GPU 富余，可开 quality 档 |

> 分析分辨率是**唯一的性能杠杆**：4K 内容仍按 360~480 分析（参考实现也是
> `analysis<=480 pixels`），合成分辨率始终跟随源分辨率。

### 5.2 1080p 资源明细（基准档）

| 项 | 规格 | 备注 |
|---|---|---|
| 合成分辨率 | 源分辨率 | warp + blend，纯采样 |
| capture | 2 × RGBA16F 1080p ≈ 33MB | 可用 R16F 亮度降到 8MB（颜色仍从源纹理采） |
| 金字塔 | 3 级，≈ 1.33 × 分析亮度 ≈ 2MB | |
| 光流 | 分析分辨率 RG16F ×3 ≈ 5MB | fwd / bwd / smooth |
| warp | 2 × RGBA16F 1080p ≈ 33MB | 可合并为一次采样 |
| **峰值** | **≈ 70~100MB 显存** | TV 盒子（2GB）需降档或不启用 |

### 5.3 耗时分解（1080p，24→120fps 基准）

| pass | 目标 |
|---|---|
| coarse+refine | ≤ 3ms/对 |
| evidence+recon | ≤ 1ms |
| warp+synthesis | ≤ 3ms/合成帧 |
| **合计** | **≤ 7ms/帧** |

超预算的自动降档顺序：`analysis-height 480→360` → `搜索半径减半` → `跳过 ±1 精修` →
`memc-quality=performance` → 仍超则 `bypass_perf`。

---

## 6. 旁路（bypass）规则

按优先级依次判断，命中即旁路并记录原因（面板显示）：

| 条件 | 原因码 |
|---|---|
| `hdrContent \|\| dvContent` | `bypass_hdr` |
| 画中画 / 后台 | `bypass_pip` |
| 播放速度 ≠ 1.0 | `bypass_speed` |
| 源 fps ≥ 55 或 ≥ 目标帧率 | `bypass_high_fps` |
| 分辨率长边 > 2560 | `bypass_resolution` |
| 热状态 ≥ `THERMAL_STATUS_SEVERE` | `bypass_overheating` |
| 连续 3 秒合成耗时超预算 | `bypass_perf` |
| 引擎初始化失败 | `unsupported` |

> `bypass_hdr` 是硬规则：DV/HDR 的观感完全不受影响，我们已完成的
> `androidvk` + DOVI 重塑链路零风险。

---

## 7. 与现有代码的接线

### 7.1 Dart 侧
- `AppSettings` 新增：`memcEnabled`、`memcTargetFps`、`memcQuality`、`memcArtifact`、`memcAnime`。
- `MpvPlayerAdapter`：起播 / 设置变更时写 mpv property（`memc`、`memc-target-fps`…）。
- `DebugMetricsCollector`：新增「补帧」分组（状态/目标帧率/分析分辨率/合成帧率/耗时/旁路原因）。
- 引擎矩阵：仅 **MPV 引擎**暴露该开关（MDK/Erika 不接）。

### 7.2 原生侧

三端共用同一份 mpv 补丁与同一套 `--memc-*` 选项，差异只在构建方式与面板出口：

| 平台 | 属性通道 | 调试面板出口 | 首要验证点 |
|---|---|---|---|
| 安卓 | `HimiMpvAndroidSession.setProperty` | Kotlin `DebugPanelView` | 过热 / 掉帧 / 音画同步 |
| 鸿蒙 | `HimiMpvOhosSession.setProperty` | ArkTS `DebugPanel.ets` | 本地构建反馈慢；Vulkan 驱动差异 |
| Windows | `MpvSession`（Qt 侧 mpv 独立进程） | Qt `MpvWindow::debugText()` | **D3D11 compute 路径**（libplacebo 用得少） |

- 视图链路三端都不需要改（MEMC 在 mpv 内部）。
- Windows 的遥测要在 `debugText()` 里新增一行，格式与另外两端保持一致。

### 7.3 构建
- 补丁文件统一命名 **`scripts/mpv/patches/memc.patch`**（不叫 `-vulkan`：引擎只依赖
  libplacebo 抽象，同一个补丁可编进 Vulkan / D3D11 两种后端）。
- 安卓 / 鸿蒙：`build_android.sh` / `build_ohos.sh` 在 mpv checkout 后 `git apply`。
- Windows：沿用 `build_windows.sh` 已有的 `PATCH_COMMAND` 机制
  （现有 `patch_mpv_angle.sh` 就是通过它注入的），再加一个 `patch_mpv_memc.sh`。
- 构建期断言：`grep_binary libmpv.so 'memc: engine ready'`，防止「编了但没生效」
  （教训参照 697：Vulkan 后端在、SPIR-V 编译器不在，就静默失效）。
- `mpv-kernels.yml` 会因 `scripts/mpv/**` 变更自动触发（Android 三 ABI + Windows 任务）。

---

## 8. 分阶段实施与验收（双轨）

引擎本体与平台无关，**统一在安卓上开发验证**（唯一有 CI 快回路的端）；
平台接入按「安卓 → 鸿蒙 → Windows」推进。

### 8.1 轨道 A｜引擎核心（平台无关，在安卓上开发）

| 阶段 | 内容 | 工期 | 验收标准 |
|---|---|---|---|
| **A0 技术验证（spike）** | 在 `vo_gpu_next` 里确认能做到「按 vsync 逐次呈现」、拿到双帧与 audio clock；打日志证明钩子位置正确 | 2~3 天 | 24fps 内容能稳定按显示刷新率提交（日志可证），无音画不同步 |
| **A1 最小可用** | capture + coarse + warp + synthesis（先不做 evidence/遮挡），只支持 2x、SDR、≤1080p | 4~6 天 | 横向 pan 明显更顺；无卡顿；关闭开关后与现在完全一致 |
| **A2 质量** | refinement + evidence（前后向一致性/遮挡）+ 中值滤波 + scene map | 4~6 天 | 快速运动不撕裂；场景切换不出现拖影；伪影档可调 |
| **A3 动画优化** | 边缘保护 + 一拍二/一拍三节奏平滑 | 3~5 天 | 番剧观感接近参考实现 |

### 8.2 轨道 B｜平台接入（三端并列，各有独立验收）

| 子项 | 内容 | 前置 | 工期 | 专属验收 |
|---|---|---|---|---|
| **B1 安卓** | bypass 规则、过热/性能降级、遥测、设置页、面板行 | A1 完成即可并行 | 3~4 天 | 三类内容（24fps 动漫 / 30fps 实拍 / 60fps 体育）行为正确；`androidvk` 下合成帧率达标 |
| **B2 鸿蒙** | 本地构建（`build_ohos_local.sh`）+ `git apply` 补丁 + ArkTS 面板遥测 | A2 完成 | 3~4 天 | `ohosvk` 下合成帧率达标；HDR 走 `bypass_hdr`；无白屏/花屏 |
| **B3 Windows** | `PATCH_COMMAND` 注入 + Qt `debugText()` 遥测 + **D3D11 compute 验证** | B2 完成 | 3~5 天 | 8-bit / 10-bit / HDR bypass 三组各达标；`d3d11` 下无掉帧 |

### 8.3 排期与并行关系

```
周 1-2   A0 ──► A1 ──┬──► A2 ──┬──► A3
                     └──► B1（安卓工程化，与 A2 并行）
周 3-4                         ├──► B2（鸿蒙）
周 5                           └──► B3（Windows）
```

总计（A0~A3 + B1~B3）约 **4~5 周**：轨道 A 约 2.5~3 周，B1 与之并行，
B2 约 1 周、B3 约 1 周串在其后。

### 8.4 硬门槛与顺序约束

- **A0 是硬门槛**：若钩子拿不到双帧或 vsync 时序不可控，方案重估（不在本方案范围内）。
- **引擎先稳、再接线**：B2/B3 不做算法改动，只做构建、属性与面板；发现需要改算法，
  一律回到轨道 A，改完再同步。
- 安卓 CI 是唯一快回路，**shader 调参只在安卓做**；鸿蒙/Windows 只做驱动差异纠偏。

---

## 9. 测试策略

### 9.1 可自动化的部分（进 `flutter test`）
- 旁路判定纯函数：`hdr → bypass_hdr`、`speed != 1 → bypass_speed`、`fps >= target → bypass_high_fps` 等。
- 目标帧率时刻表：2x/2.5x/3x/4x/screen 的采样时刻（含 24→60 非整数倍）。
- 设置项往返：`AppSettings` ↔ mpv property 名。
- 结构断言：`build_android.sh` 含 `memc-vulkan.patch` 与构建期 `grep_binary` 断言；
  Dart 侧所有 `memc-*` property 名与 mpv 选项表一致（防字段名写错，参考 697 的教训）。
- 面板行存在性 + 四端一致性（与 `dv_backend_actual_697_test` 同构）。

### 9.2 只能真机验证（分端）

| 平台 | 验证项 |
|---|---|
| 安卓 | 观感（拖影/撕裂/伪影）；音画同步（长播 30 分钟）；温度与掉帧（4K 源、120Hz 屏） |
| 鸿蒙 | 同安卓，另加：`ohosvk` 下不花屏/不白屏；本地构建产物与安卓行为一致 |
| Windows | 8-bit SDR / 10-bit / HDR bypass 三组；`d3d11` 下 1440p~4K 掉帧情况；Qt 面板遥测字段齐全 |

### 9.3 回归保护
- 关闭开关时，所有现有测试必须全绿；HDR/DV 用例在 `memc=on` 下也必须全绿（走 bypass）。
- 新增断言：`memc=on` 且 `hdrContent=true` 时，实际呈现路径标记为 `bypass`。

---

## 10. 风险与回退

| 风险 | 影响 | 缓解 |
|---|---|---|
| 改 mpv 渲染循环引入崩溃/白屏 | 高 | 编译期开关 `-Dmemc=disabled` 可完全摘除；运行时默认 `no` |
| 音画不同步 | 高 | alpha 绑定 audio clock；A0 先验证；漂移即自动旁路 |
| 过热/掉帧 | 中 | 性能降档 + 过热旁路 + 面板可见 |
| 遮挡区伪影 | 中 | evidence 通道 + 低置信度像素级容错 |
| 显存吃紧（TV 2GB） | 中 | 分辨率门限 + R16F 亮度 |
| 与 DV/HDR 冲突 | 低（已 bypass） | 硬规则旁路 + 回归用例 |

**回退路径**：`memc=no` → 走原有 `pl_render_image` 直出，与今天逐字节等价。

---

## 11. 跨平台设计（鸿蒙 / Windows）

### 11.1 为什么同一份代码能三端跑

引擎**只使用 libplacebo 公共接口**，不写任何后端专用调用：

| 只允许用 | 对应后端实现 |
|---|---|
| `pl_dispatch_*`（compute 调度） | Vulkan / D3D11 / GLES 各自实现 |
| `pl_tex`（纹理创建、采样、渲染目标） | 同上 |
| `pl_shader`（GLSL 片段 / 计算） | 由 shaderc 或 glslang 运行期编译 |
| `pl_gpu`（能力查询） | 统一限流 |

**禁止**出现 `vkCmdDispatch` / `ID3D11DeviceContext::Dispatch` / `glDispatchCompute`
等后端直调——一旦出现，三端共用就破了。

### 11.2 三端前置条件核对

| 条件 | 安卓 | 鸿蒙 | Windows |
|---|---|---|---|
| mpv 自编译 | ✅ kernels CI | ✅ 本地脚本 | ✅ shinchiro 交叉构建 |
| 能打 mpv 补丁 | ✅ | ✅ `patch.sh` | ✅ `PATCH_COMMAND`（已有先例） |
| libplacebo compute | ✅ Vulkan | ✅ Vulkan | ✅ **D3D11** |
| SPIR-V 编译器 | ✅ shaderc（697 已补） | ✅ `-Dshaderc=enabled` | ✅ 由 libplacebo 构建带入 |
| 现役 GPU 后端 | `androidvk` | `ohosvk` | `d3d11` |
| HDR 直出 | ✅ | ✅ | ✅ |

### 11.3 各端特有风险与对策

| 平台 | 风险 | 对策 |
|---|---|---|
| 安卓 | 过热降频、120Hz 预算紧（8.3ms） | 性能档 + 过热旁路 + 500ms 均值超预算自动降档 |
| 鸿蒙 | 无 CI，改 shader 一轮反馈慢；Vulkan 驱动差异 | 先在安卓把 shader 调稳，鸿蒙只做接线与真机纠偏 |
| Windows | **D3D11 compute** 在 libplacebo 里用得少；10-bit/HDR 纹理格式组合需验证 | B3 先跑 SDR 8-bit，再逐级验 10-bit / HDR bypass |
| Windows | mpv 在独立进程，遥测取数走 `debugText()` | 新增一行固定格式，与另外两端字段对齐 |

### 11.4 三端一致性要求（进测试）

- `--memc-*` 选项名、默认值、取值范围三端完全相同（同一份补丁，天然一致，需断言）。
- 旁路原因码三端相同（`bypass_hdr` / `bypass_pip` / …），面板文案可本地化但码值不变。
- 面板「补帧」分组的字段顺序一致，便于跨端截图对比排障。

### 11.5 不做跨端的事

- 不为某端写专用引擎实现（宁可少一个优化，也不让补丁分叉）。
- 不让 MEMC 影响 `gpu-api` / `gpu-context` 的选择逻辑（它与 697 的 Vulkan 结论解耦）。

---

## 12. 待确认事项（实施前需拍板）

1. 目标帧率默认值：`屏幕刷新率` 还是 `2x`？（建议屏幕刷新率）
2. TV 低内存设备是否默认关闭（建议：`ActivityManager.isLowRamDevice` 自动关）
3. 面板遥测刷新频率（建议沿用 2s，合成耗时用 500ms 窗口均值）
4. A3 动画优化是否必要（视 A2 观感决定）

---

## 附录 A：参考实现的二进制证据（供复核）

```
libmpv.so (19.2MB，标准 12MB)
  "GPU motion interpolation enabled: target=%d fps, analysis<=480 pixels, synthesis=source resolution."
  "Motion GPU means: capture=.. coarse-pass=.. refinement-pass=.. evidence-pass=..
   reconstruction-pass=.. warp-pass=.. synthesis=.."
  "Passing frames unsupported by motion interpolation through without synthesis."
  vec4 synthesize_pixel(sampler2D source0, sampler2D source1, sampler2D warp0,
                        sampler2D warp1, sampler2D scene_map, ivec2 pixel,
                        vec2 output_extent, vec2 motion_extent, float alpha, bool linear_hdr)
  "Initialized SPIR-V compiler" / "shaderc_compile_into_spv"   ← 与我们现在的构建一致

classes4.dex
  frc_enabled / frc_quality_level / frc_target_fps_mode
  frc_artifact_mask / frc_anime_optimization / frc_auto_options
  player_frc_status_bypass_{hdr,pip,speed,high_fps,overheating}
  player_vulkan_motion_stat_{synthesized,presented,resolution,fps_value}
```

> 另：参考实现还有一个独立的 `libmpvex_frc.so`（GLES compute 外部引擎）。
> 本方案不走那条路，仅作为算法细节的对照来源（块匹配 SAD / 前后向一致性 / 中值滤波 / warp 混合）。

## 附录 B：可复用的现成能力

- Android libmpv 自编译流水线（`scripts/mpv/build_android.sh`）与补丁机制
- shaderc / SPIR-V（697 已打通，Vulkan 已真机验证）
- 四端调试面板与遥测采集框架
- `AppSettings` / 引擎矩阵 / 原生属性下发通道

---

（完）
