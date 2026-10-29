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

/**
 * Phase 2 二级面板类型（计划书 §5.2 面板清单）。
 * 每个面板一个模态，打开时遮住视频、点外/返回关闭。
 */
export class NativePlayerPanelType {
  static readonly speed: string = 'speed';
  static readonly audio: string = 'audio';
  static readonly subtitle: string = 'subtitle';
  static readonly episode: string = 'episode';
  static readonly version: string = 'version';
  static readonly settings: string = 'settings';
  static readonly lock: string = 'lock';
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

/** 面板轨道项（与 Dart `NativeTrack.toJson` 字段一致）。 */
export class NativeTrackUi {
  id: number = 0;
  type: string = 'audio'; // audio / sub / video
  title: string = '';
  lang: string = '';
  selected: boolean = false;
}

/** 面板选集项（与 Dart `NativeEpisode.toJson` 一致）。 */
export class NativeEpisodeUi {
  index: number = 0;
  title: string = '';
}

/** 面板版本项（与 Dart `NativeVersion.toJson` 一致）。 */
export class NativeVersionUi {
  index: number = 0;
  title: string = '';
}

function parseTracks(v: ESObject): NativeTrackUi[] {
  const out: NativeTrackUi[] = [];
  if (Array.isArray(v)) {
    const arr = v as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item = new NativeTrackUi();
      const src = arr[i] as Record<string, Object>;
      item.id = jsonNum(src['id'], 0);
      item.type = jsonStr(src['type'], 'audio');
      item.title = jsonStr(src['title'], '');
      item.lang = jsonStr(src['lang'], '');
      item.selected = jsonBool(src['selected'], false);
      out.push(item);
    }
  }
  return out;
}

function parseEpisodes(v: ESObject): NativeEpisodeUi[] {
  const out: NativeEpisodeUi[] = [];
  if (Array.isArray(v)) {
    const arr = v as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item = new NativeEpisodeUi();
      const src = arr[i] as Record<string, Object>;
      item.index = jsonNum(src['index'], 0);
      item.title = jsonStr(src['title'], '');
      out.push(item);
    }
  }
  return out;
}

function parseVersions(v: ESObject): NativeVersionUi[] {
  const out: NativeVersionUi[] = [];
  if (Array.isArray(v)) {
    const arr = v as Object[];
    for (let i = 0; i < arr.length; i++) {
      const item = new NativeVersionUi();
      const src = arr[i] as Record<string, Object>;
      item.index = jsonNum(src['index'], 0);
      item.title = jsonStr(src['title'], '');
      out.push(item);
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

  // ── Phase 2 面板数据 ──
  /** 全部轨道（audio/sub/video），面板按 type 过滤展示。 */
  tracks: NativeTrackUi[] = [];
  episodes: NativeEpisodeUi[] = [];
  versions: NativeVersionUi[] = [];
  selectedAudioId: number = 0;
  selectedSubtitleId: number = 0;
  subtitleDelayMs: number = 0;
  currentEpisodeIndex: number = 0;
  currentVersionIndex: number = 0;
  /** 音量（0-1），音量面板/滑杆用。 */
  volumeDisplay: number = 1.0;

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
    // ── Phase 2 面板数据 ──
    if (obj.tracks !== undefined) {
      this.tracks = parseTracks(obj.tracks);
    }
    if (obj.episodes !== undefined) {
      this.episodes = parseEpisodes(obj.episodes);
    }
    if (obj.versions !== undefined) {
      this.versions = parseVersions(obj.versions);
    }
    this.selectedAudioId = jsonNum(obj.selectedAudioId, this.selectedAudioId);
    this.selectedSubtitleId = jsonNum(obj.selectedSubtitleId, this.selectedSubtitleId);
    this.subtitleDelayMs = jsonNum(obj.subtitleDelayMs, this.subtitleDelayMs);
    this.currentEpisodeIndex = jsonNum(obj.currentEpisodeIndex, this.currentEpisodeIndex);
    this.currentVersionIndex = jsonNum(obj.currentVersionIndex, this.currentVersionIndex);
    this.volumeDisplay = jsonNum(obj.volume, this.volumeDisplay);
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

  /** 当前打开的二级面板（null = 无）。见 [NativePlayerPanelType]。 */
  activePanel: string | null = null;

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

  /** 打开二级面板（同类型重开为 no-op；打开时保持控件可见）。 */
  openPanel(type: string): void {
    if (this.activePanel === type) return;
    this.activePanel = type;
    this.setControlsVisible(true);
  }

  /** 关闭当前面板（无面板时 no-op）。 */
  closePanel(): void {
    if (this.activePanel === null) return;
    this.activePanel = null;
    this.notify();
  }

  /** 切换面板（点同一按钮再点关闭）。 */
  togglePanel(type: string): void {
    if (this.activePanel === type) {
      this.closePanel();
    } else {
      this.openPanel(type);
    }
  }

  /**
   * 返回键语义（计划书 §5.6）：先关面板 → 再隐藏控件 → 再请求退出。
   * 恒返回 true（本页面消费 back，避免子窗口被系统直接销毁）。
   */
  handleBack(): boolean {
    if (this.activePanel !== null) {
      this.closePanel();
      return true;
    }
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

  // ── Phase 2 面板命令（乐观更新 + 回传 Dart）────────────────

  /** 倍速：乐观改本地 speed，回传 setSpeed。 */
  optimisticSetSpeed(speed: number): void {
    this.state.speed = speed;
    this.lastStateAtMs = Date.now();
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('speed', speed);
    this.sendCommand('setSpeed', fields);
    this.notify();
  }

  /** 音量：乐观改本地 volume，回传 setVolume。 */
  optimisticSetVolume(volume: number): void {
    const clamped = Math.min(Math.max(volume, 0), 1);
    this.state.volume = clamped;
    this.state.volumeDisplay = clamped;
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('volume', clamped);
    this.sendCommand('setVolume', fields);
    this.notify();
  }

  /** 选音轨：乐观标 selected，回传 selectAudio（id = mpv track id）。 */
  optimisticSelectAudio(trackId: number): void {
    this.state.selectedAudioId = trackId;
    for (let i = 0; i < this.state.tracks.length; i++) {
      const t = this.state.tracks[i];
      if (t.type === 'audio') {
        t.selected = t.id === trackId;
      }
    }
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('id', trackId);
    this.sendCommand('selectAudio', fields);
    this.notify();
  }

  /** 选字幕轨：id=0 表示关闭，回传 selectSubtitle。 */
  optimisticSelectSubtitle(trackId: number): void {
    this.state.selectedSubtitleId = trackId;
    for (let i = 0; i < this.state.tracks.length; i++) {
      const t = this.state.tracks[i];
      if (t.type === 'sub') {
        t.selected = t.id === trackId;
      }
    }
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('id', trackId);
    this.sendCommand('selectSubtitle', fields);
    this.notify();
  }

  /** 选集：回传 selectEpisode。 */
  optimisticSelectEpisode(index: number): void {
    this.state.currentEpisodeIndex = index;
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('index', index);
    this.sendCommand('selectEpisode', fields);
    this.notify();
  }

  /** 选版本/线路：回传 selectVersion。 */
  optimisticSelectVersion(index: number): void {
    this.state.currentVersionIndex = index;
    const fields: Map<string, Object> = new Map<string, Object>();
    fields.set('index', index);
    this.sendCommand('selectVersion', fields);
    this.notify();
  }

  private notify(): void {
    const listener = this.listener;
    if (listener !== null) {
      listener.onNativeStateChanged();
    }
  }
}
