# 原生播放器命令路由矩阵（Phase 2 / 计划书 §4.3）

> 盘点日期：2026-10-30。对照 `NativePlayerCommand`（30 类）×
> `MpvPlayerAdapter._handleNativeUiCommand` × `PlayerScreen` 现有 handler。
>
> 背景：Phase 1 只接了 4 类命令（返回/播放/seek/倍速），其余 26 类在
> adapter 的 `default:` 分支只打日志「待接入 PlayerScreen」。Phase 2 的
> 协议层工作 = 补全「原生 → Dart → PlayerScreen」的通用命令桥 + 逐条接线。

## 一、现状：命令流向

```
原生 View（ArkUI / Kotlin）
  → EventChannel（himi_mpv/native_ui/commands · himi_native_player/commands）
  → NativePlayerController.handleNativeCommand（fromMap 解析）
  → MpvPlayerAdapter._handleNativeUiCommand（switch 分发）
       ├─ 已处理（6 类）
       └─ default → LogService「待接入 PlayerScreen」← 26 类卡在这
```

**缺口**：`_handleNativeUiCommand` 只有 `onNativeUiExit` 一个 PlayerScreen
回调，没有通用命令出口。PlayerScreen 有大量现成 handler（选集/版本/音轨/
字幕/倍速…）但命令到不了。

## 二、逐类状态

### A. adapter 已处理（6 类）✅
| 命令 | 处理 |
|---|---|
| `togglePlay` | 切换 `_state` |
| `seekTo` | `seek(positionMs)` |
| `seekRelative` | `seek(_positionMs + delta)` |
| `setVolume` | `volume = clamp` |
| `setSpeed` | `playbackRate = clamp` |
| `requestBack` / `requestExit` | `onNativeUiExit` → PlayerScreen 退出 |

### B. PlayerScreen 有现成 handler，只差接线（9 类）🔧
| 命令 | PlayerScreen handler | 行号 |
|---|---|---|
| `selectAudio` | `_selectEmbyAudio(id)` | 6437 |
| `selectSubtitle` | `_selectEmbySubtitle(pos)` / null=关 | 4214 |
| `addSubtitle` | `_loadLocalSubtitle()`（外挂需带 url） | 10124 |
| `selectEpisode` | `_switchToEpisode(index)` | 6330 |
| `selectVersion` | `_switchMediaSource(source)` | 6392 |
| `setSpeed` | `_applySpeed(speed)`（与 adapter 重复，取一） | 8438 |
| `toggleDanmaku` | `_toggleDanmaku()` | 8152 |
| `setSubtitleStyle` | `_subtitleStyleStore` + apply timer | 1129-1135 |
| `setSubtitleDelay` | `_subtitleDelayMs` + reload timer | 1119-1126 |

### C. 需新写 handler（Phase 2 内，4 类）🆕
| 命令 | 说明 |
|---|---|
| `setDecodeMode` | `DecodeModeService` 已有（428/436/2103），缺命令入口 |
| `adjustDisplay` | 显示调节（缩放/裁剪/偏移），Flutter 侧有 `Icons.zoom_out_map` |
| `setSegmentMark` | 片头片尾标记，`_showSegmentMarkPanel` 已有 UI 态（1027） |
| `takeScreenshot` | `_probeSnapshot` 已有截帧逻辑（3161），缺保存/回调 |

### D. 属后续 Phase，暂不接（7 类）⏭
| 命令 | 归属 |
|---|---|
| `updateDanmakuSettings` | Phase 4（弹幕设置面板） |
| `toggleRoomSync` / `sendRoomChat` | Phase 5（房间同步） |
| `toggleDebug` | Phase 5（调试面板完整字段） |
| `switchEngine` | Phase 6（内核切换） |
| `requestBack`/`requestExit`（已算 A） | — |
| `setSubtitleStyle`/`setSubtitleDelay`（已算 B） | — |

> D 组实际 4 类独立：`updateDanmakuSettings`、`toggleRoomSync`、
> `sendRoomChat`、`toggleDebug`、`switchEngine`（5 类）。原生 UI Phase 2
> 不出这些入口，命令先忽略（打日志），协议保持可解析不崩。

## 三、Phase 2 协议层改动

1. **通用命令桥**：`MpvPlayerAdapter` 加 `onNativeUiCommand`
   （`Future<void> Function(NativePlayerCommand)`），`_handleNativeUiCommand`
   的 `default` 改为转发给它；PlayerScreen 注入实现，按上表路由到现有
   handler。模式对齐 `onNativeUiExit`。
2. **B 组 9 类接线**（纯转发，handler 已在）。
3. **C 组 4 类**：PlayerScreen 补最小 handler。
4. **D 组**：`default` 保持打日志，但日志降级为「Phase 后续」不再误报「待接入」。
5. **原生侧 Listener 扩展**：双端原生 View 目前只发 4 类命令，面板做出来后
   按需补发（随 UI 里程碑走，不在本协议轮）。

## 四、测试计划

- `fromMap` 全 30 类往返（`toMap` → `fromMap` 一致）——已有部分，补全。
- 每类命令经 `NativePlayerController.handleNativeCommand` 能到 handler
  （mock handler 断言收到对应 command 类型）。
- B 组接线后：PlayerScreen 收到 `selectEpisode` 等确实调用了对应方法
  （widget 测试或 handler 注入断言）。
- D 组命令不崩、只打日志。
