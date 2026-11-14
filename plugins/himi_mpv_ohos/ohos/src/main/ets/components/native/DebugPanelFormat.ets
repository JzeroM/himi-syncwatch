/**
 * 697：播放调试面板的纯判定逻辑（ArkTS，可单测）。
 *
 * ## 为什么抽出来
 *
 * 面板的价值在于「这个组合算正常还是异常」。判错比没有面板更糟：
 * 把 P5 偏色标成绿、把软解标成正常，会把人引向错误的排查方向。
 *
 * 判定逻辑与 UI 分离后，可以在不改 UI 的前提下单测（见
 * `test/player_core/ohos_debug_panel_697_test.dart` 的结构断言 +
 * 三端一致性检查）。
 *
 * ## 三端一致性
 *
 * 同一套语义在 Flutter（`debug_metrics_collector.dart`）、Android
 * （`DebugPanelFormat.kt`）、Windows Qt（`DebugPanel.qml`）各有一份。
 * 改阈值/关键词时必须四端同步，否则会出现「鸿蒙说支持、Qt 说不支持」。
 */

/** 状态色语义（与 Flutter / Android / Qt 完全一致）。 */
export class DebugSeverity {
  static readonly NORMAL: string = 'normal';
  static readonly GOOD: string = 'good';
  static readonly WARN: string = 'warn';
  static readonly ERROR: string = 'error';
}

/**
 * 上下文名 → 后端族（`vulkan` / `d3d11` / `opengl` / `unknown`）。
 *
 * 【697 真机回归（安卓）】不能写 `ctx.indexOf('vulkan') >= 0`：安卓
 * Vulkan 的上下文名是 **`androidvk`**，不含 `vulkan` 子串。旧判定会把
 * 跑在 Vulkan 上的 P5 误报成「后端不支持 DV，画面会偏色」。
 *
 * 入参可能是逗号分隔的**优先级列表**（`androidvk,android`）——只看第一项：
 * 列表语义就是「第一个能起来的就是它」。若传的是实际值
 * （mpv `current-gpu-context`），本来就只有一项。
 */
export function renderBackendOf(context: string | null): string {
  const raw: string = (context ?? '').toLowerCase();
  let first: string = '';
  const parts: string[] = raw.split(',');
  for (let i = 0; i < parts.length; i++) {
    const t: string = parts[i].trim();
    if (t.length > 0) {
      first = t;
      break;
    }
  }
  if (first.length === 0) return 'unknown';
  // `androidvk` / `ohosvk` / `vulkan` / `x11vk`……都带 `vk`
  if (first.indexOf('vk') >= 0 || first.indexOf('vulkan') >= 0) return 'vulkan';
  if (first.indexOf('d3d11') >= 0) return 'd3d11';
  if (first.indexOf('android') >= 0 ||
    first.indexOf('egl') >= 0 ||
    first.indexOf('glx') >= 0 ||
    first.indexOf('wayland') >= 0 ||
    first.indexOf('opengl') >= 0 ||
    first.indexOf('gl') >= 0) {
    return 'opengl';
  }
  return 'unknown';
}

/**
 * 后端是否支持 DV 元数据（libplacebo 需要 compute shader）。
 *
 * - D3D11（Windows）/ Vulkan（安卓 androidvk、鸿蒙 ohosvk）→ 支持
 * - OpenGL / OpenGL ES → 不支持（mpv 会关掉 hdr-compute-peak）
 *
 * 未知 context 保守判为不支持：误判成「支持」会让人以为 P5 没问题。
 */
export function backendSupportsDv(gpuContext: string | null): boolean {
  const backend: string = renderBackendOf(gpuContext);
  return backend === 'vulkan' || backend === 'd3d11';
}

/**
 * 面板判后端用的上下文：**实际值优先**，缺失才退回配置列表。
 *
 * 实际值来自 mpv `current-gpu-context`（`vo->context_name`）；配置列表只
 * 说明我们「允许」哪些后端，不能证明实际选中了哪个。
 */
export function effectiveRenderContext(
  actual: string | null,
  configured: string | null,
): string {
  const a: string = (actual ?? '').trim();
  if (a.length > 0) return a;
  return (configured ?? '').trim();
}

/**
 * 丢帧分级（阈值与 Flutter / Android / Qt 一致）。
 *
 * 少量丢帧（起播/seek 瞬间）是正常现象，不该报红。
 */
export function dropSeverity(render: number, decode: number): string {
  if (render > 100 || decode > 100) return DebugSeverity.ERROR;
  if (render > 10 || decode > 10) return DebugSeverity.WARN;
  return DebugSeverity.GOOD;
}

/**
 * DV 的 tone-mapping 是否正确。
 *
 * 697 修复点：DV 是动态元数据，必须 `bt.2390`（感知映射）；
 * 用 `clip` 会硬裁切 → 高光细节丢失、暗部发灰。
 * 非 DV 内容用 `clip` 是正常的（不该报错）。
 */
export function dvToneMappingOk(isDv: boolean, toneMapping: string): boolean {
  return !isDv || toneMapping === 'bt.2390';
}

/** 输出是否真的在 HDR（`target-trc` 为 pq/hlg）。 */
export function isHdrOutput(targetTrc: string): boolean {
  return targetTrc === 'pq' || targetTrc === 'hlg';
}

/** 毫秒 → `mm:ss` / `hh:mm:ss`。 */
export function fmtMs(ms: number): string {
  if (!ms || ms <= 0) return '00:00';
  const total: number = Math.floor(ms / 1000);
  const h: number = Math.floor(total / 3600);
  const m: number = Math.floor((total % 3600) / 60);
  const s: number = total % 60;
  const two = (v: number): string => v < 10 ? `0${v}` : `${v}`;
  return h > 0 ? `${two(h)}:${two(m)}:${two(s)}` : `${two(m)}:${two(s)}`;
}

/**
 * DV Profile 的可读文本（`P8 L6` / `P5（单层 IPT）` / `非 DV 内容`）。
 *
 * 逐段拼接而不是 `a + if(x) 'y' else '' + if(z) 'w' else ''`——
 * 后者的 else 会吞掉后半段（Dart / Kotlin / QML / ArkTS 都有这个陷阱）。
 */
export function dvProfileText(doviProfile: number, doviLevel: number): string {
  if (doviProfile <= 0) return '非 DV 内容';
  const ipt: string = doviProfile === 5 ? '（单层 IPT）' : '';
  const level: string = doviLevel > 0 ? ` L${doviLevel}` : '';
  return `P${doviProfile}${ipt}${level}`;
}

/** 空串 → '-'（面板不留空白格，一眼能看出「没取到」）。 */
export function orDash(value: string, fallback?: string): string {
  if (value && value.length > 0) return value;
  if (fallback && fallback.length > 0) return fallback;
  return '-';
}
