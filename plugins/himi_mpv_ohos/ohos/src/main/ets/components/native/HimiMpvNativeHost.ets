/**
 * 原生播放器宿主（全屏子窗口模式）。
 *
 * 单例桥：持有权威状态快照、surface 绑定转发、命令回传与视图刷新回调。
 *
 * 状态所有权（计划书 §3.2）：Dart 是唯一权威状态源。本宿主每次收到
 * `pushNativeState` 的 JSON 快照后整体覆盖本地状态，并记录快照落地时刻，
 * 视图按 `position + (now - snapshotAt) * speed` 做本地插值（暂停保持不变）。
 * 原生命令先由视图乐观更新显示，再经 [NativeHostBridge.forwardCommand]
 * 回传 Dart；Dart 应用后推回权威快照。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'HimiMpvNativeHost';
const DOMAIN = 0x0001;

/** 视图刷新回调（宿主状态变化时通知 ArkUI 视图重绘）。 */
export interface NativePlayerViewListener {
  onNativeStateChanged(): void;
}

/** 宿主 → 插件的转发桥（surface 生命周期与命令回传）。 */
export interface NativeHostBridge {
  forwardSurfaceCreated(surfaceId: string): void;
  forwardSurfaceChanged(surfaceId: string, width: number, height: number): void;
  forwardSurfaceDestroyed(surfaceId: string): void;
  forwardCommand(command: Map<string, Object>): void;
}

function jsonStr(v: ESObject, def: string): string {
  return typeof v === 'string' ? v as string : def;
}

function jsonNum(v: ESObject, def: number): number {
  return typeof v === 'number' ? v as number : def;
}

function jsonBool(v: ESObject, def: boolean): boolean {
  return typeof v === 'boolean' ? v as boolean : def;
}

function jsonStrList(v: ESObject): string[] {
  const out: string[] = [];
  if (Array.isArray(v)) {
    const arr = v as string[];
    for (let i = 0; i < arr.length; i++) {
      out.push(arr[i]);
    }
  }
  return out;
}

/** Dart 推送的权威状态快照（Phase 1 最小字段集；Phase 2 起按需扩展）。 */
export class NativePlayerUiState {
  title: string = '';
  mediaTitle: string = '';
  positionMs: number = 0;
  durationMs: number = 0;
  bufferedMs: number = 0;
  paused: boolean = true;
  buffering: boolean = false;
  ended: boolean = false;
  volume: number = 1.0;
  speed: number = 1.0;

  // 输出与 HDR 诊断
  engine: string = 'mpv';
  videoOutputRequested: string = 'surface';
  videoOutputActual: string = 'surface';
  nativeSurface: boolean = true;
  textureId: number = 0;
  hdrOutput: boolean = false;
  displayHdr: boolean = false;
  targetTrc: string = 'auto';
  voConfigured: string = '';
  currentVo: string = '';
  hwdecCurrent: string = '';

  // Surface 诊断
  surfaceAttached: boolean = false;
  surfaceId: string = '';
  surfaceError: string = '';
  surfaceWidth: number = 0;
  surfaceHeight: number = 0;

  canControl: boolean = true;
  locked: boolean = false;
  debugLines: string[] = [];

  /** 用 JSON 快照整体覆盖（缺失字段保持旧值，容忍字段增减）。 */
  update(obj: ESObject): void {
    this.title = jsonStr(obj.title, this.title);
    this.mediaTitle = jsonStr(obj.mediaTitle, this.mediaTitle);
    this.positionMs = jsonNum(obj.positionMs, this.positionMs);
    this.durationMs = jsonNum(obj.durationMs, this.durationMs);
    this.bufferedMs = jsonNum(obj.bufferedMs, this.bufferedMs);
    this.paused = jsonBool(obj.paused, this.paused);
    this.buffering = jsonBool(obj.buffering, this.buffering);
    this.ended = jsonBool(obj.ended, this.ended);
    this.volume = jsonNum(obj.volume, this.volume);
    this.speed = jsonNum(obj.speed, this.speed);
    this.engine = jsonStr(obj.engine, this.engine);
    this.videoOutputRequested = jsonStr(obj.videoOutputRequested, this.videoOutputRequested);
    this.videoOutputActual = jsonStr(obj.videoOutputActual, this.videoOutputActual);
    this.nativeSurface = jsonBool(obj.nativeSurface, this.nativeSurface);
    this.textureId = jsonNum(obj.textureId, this.textureId);
    this.hdrOutput = jsonBool(obj.hdrOutput, this.hdrOutput);
    this.displayHdr = jsonBool(obj.displayHdr, this.displayHdr);
    this.targetTrc = jsonStr(obj.targetTrc, this.targetTrc);
    this.voConfigured = jsonStr(obj.voConfigured, this.voConfigured);
    this.currentVo = jsonStr(obj.currentVo, this.currentVo);
    this.hwdecCurrent = jsonStr(obj.hwdecCurrent, this.hwdecCurrent);
    this.surfaceAttached = jsonBool(obj.surfaceAttached, this.surfaceAttached);
    this.surfaceId = jsonStr(obj.surfaceId, this.surfaceId);
    this.surfaceError = jsonStr(obj.surfaceError, this.surfaceError);
    this.surfaceWidth = jsonNum(obj.surfaceWidth, this.surfaceWidth);
    this.surfaceHeight = jsonNum(obj.surfaceHeight, this.surfaceHeight);
    this.canControl = jsonBool(obj.canControl, this.canControl);
    this.locked = jsonBool(obj.locked, this.locked);
    this.debugLines = jsonStrList(obj.debugLines);
  }
}

/** 调试面板单行（Phase 1 最小诊断集）。 */
export function nativeDiagSummary(s: NativePlayerUiState): string {
  return `req:${s.videoOutputRequested} act:${s.videoOutputActual} ` +
    `ns:${s.nativeSurface} tx:${s.textureId} att:${s.surfaceAttached} ` +
    `vo:${s.voConfigured.length > 0 ? s.voConfigured : '-'} ` +
    `cur:${s.currentVo.length > 0 ? s.currentVo : '-'} ` +
    `hw:${s.hwdecCurrent.length > 0 ? s.hwdecCurrent : '-'} ` +
    `trc:${s.targetTrc} hdr:${s.hdrOutput} dsp:${s.displayHdr}` +
    (s.surfaceError.length > 0 ? ` err:${s.surfaceError}` : '');
}

export class HimiMpvNativeHost {
  private static instance: HimiMpvNativeHost | null = null;

  static getInstance(): HimiMpvNativeHost {
    if (HimiMpvNativeHost.instance === null) {
      HimiMpvNativeHost.instance = new HimiMpvNativeHost();
    }
    return HimiMpvNativeHost.instance;
  }

  readonly state: NativePlayerUiState = new NativePlayerUiState();

  /** 最近一次快照落地时刻（本地插值基准）。 */
  lastStateAtMs: number = Date.now();

  /** 控件层显隐（点屏切换 / 自动隐藏 / 返回键第一段）。 */
  controlsVisible: boolean = true;

  private bridge: NativeHostBridge | null = null;
  private listener: NativePlayerViewListener | null = null;

  setBridge(bridge: NativeHostBridge | null): void {
    this.bridge = bridge;
  }

  registerListener(listener: NativePlayerViewListener): void {
    this.listener = listener;
  }

  unregisterListener(listener: NativePlayerViewListener): void {
    if (this.listener === listener) {
      this.listener = null;
    }
  }

  /** Dart → 原生：整体覆盖权威状态并刷新视图。 */
  applyStateJson(json: string): void {
    try {
      const obj: ESObject = JSON.parse(json);
      this.state.update(obj);
      this.lastStateAtMs = Date.now();
      this.notify();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'applyStateJson 失败: %{public}s', String(e));
    }
  }

  /**
   * 本地进度插值（计划书 §3.2）：
   * 播放中 `position + (now - snapshotAt) * speed`；暂停/缓冲/结束保持不变；
   * 外推夹紧到 [0, durationMs]。
   */
  positionNowMs(): number {
    const s = this.state;
    if (s.paused || s.buffering || s.ended || s.speed <= 0) {
      return s.positionMs;
    }
    const elapsed = Date.now() - this.lastStateAtMs;
    const projected = s.positionMs + elapsed * s.speed;
    if (s.durationMs > 0 && projected > s.durationMs) {
      return s.durationMs;
    }
    return projected < 0 ? 0 : Math.round(projected);
  }

  setControlsVisible(visible: boolean): void {
    if (this.controlsVisible === visible) return;
    this.controlsVisible = visible;
    this.notify();
  }

  toggleControls(): void {
    this.setControlsVisible(!this.controlsVisible);
  }

  /**
   * 返回键语义（计划书 §5.6）：先关面板 → 再隐藏控件 → 再请求退出。
   * 恒返回 true（本页面消费 back，避免子窗口被系统直接销毁）。
   */
  handleBack(): boolean {
    if (this.controlsVisible) {
      this.setControlsVisible(false);
      return true;
    }
    this.sendCommand('requestBack', null);
    return true;
  }

  /** 原生命令回传 Dart（经插件的 himi_mpv/native_ui EventChannel）。 */
  sendCommand(type: string, fields: Map<string, Object> | null): void {
    const bridge = this.bridge;
    if (bridge === null) {
      hilog.warn(DOMAIN, TAG, 'sendCommand 被忽略（bridge 未就绪）: %{public}s', type);
      return;
    }
    const cmd: Map<string, Object> = new Map<string, Object>();
    cmd.set('type', type);
    if (fields !== null) {
      fields.forEach((value: Object, key: string): void => {
        cmd.set(key, value);
      });
    }
    bridge.forwardCommand(cmd);
  }

  // ── surface 转发（视图 XComponent → 插件 mpv 会话）──────────

  attachSurface(surfaceId: string): void {
    const bridge = this.bridge;
    if (bridge !== null) {
      bridge.forwardSurfaceCreated(surfaceId);
    }
  }

  surfaceChanged(surfaceId: string, width: number, height: number): void {
    const bridge = this.bridge;
    if (bridge !== null) {
      bridge.forwardSurfaceChanged(surfaceId, width, height);
    }
  }

  detachSurface(surfaceId: string): void {
    const bridge = this.bridge;
    if (bridge !== null) {
      bridge.forwardSurfaceDestroyed(surfaceId);
    }
  }

  /**
   * 原生命令先乐观更新本地状态再回传 Dart（计划书 §3.2）：
   * 播放/暂停立即翻转，seek 立即定位；Dart 应用后推回权威快照覆盖。
   */
  optimisticTogglePaused(): void {
    this.state.paused = !this.state.paused;
    this.lastStateAtMs = Date.now();
    this.sendCommand('togglePlay', null);
    this.notify();
  }

  optimisticSeek(positionMs: number): void {
    const clamped = this.state.durationMs > 0
      ? Math.min(Math.max(positionMs, 0), this.state.durationMs)
      : Math.max(positionMs, 0);
    this.state.positionMs = clamped;
    this.lastStateAtMs = Date.now();
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('positionMs', clamped);
    this.sendCommand('seekTo', fields);
    this.notify();
  }

  private notify(): void {
    const listener = this.listener;
    if (listener !== null) {
      listener.onNativeStateChanged();
    }
  }
}
