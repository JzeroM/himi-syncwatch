/**
 * 全屏原生播放器视图（Phase 1 最小控件）。
 *
 * 结构（自下而上）：
 *   XComponent（mpv 的 OHNativeWindow 出画）
 *   → 全屏点按层（点屏显隐控件）
 *   → 顶部条（返回 / 标题 / 时钟）
 *   → 底部条（播放暂停 / 进度 / 时间 / 倍速 / 诊断行）
 *
 * 状态来自 [HimiMpvNativeHost] 的权威快照（Dart 推送），视图只做显示与
 * 本地进度插值；命令经 host 乐观更新后回传 Dart（见 host 的 optimistic*）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HimiMpvNativeHost,
  NativePlayerUiState,
  NativePlayerViewListener,
  NativePlayerPanelType,
  nativeDiagSummary,
} from './HimiMpvNativeHost';
import { NativePlayerPanel } from './NativePlayerPanel';
import { NativePlayerIcons } from './NativePlayerIcons';
import { DanmakuLayer } from './DanmakuLayer';
import { MpvXComponentController, MpvSurfaceCallbacks } from '../plugin/HimiMpvSurface';

const TAG = 'HimiNativePlayerView';
const DOMAIN = 0x0001;

/** 选中主色（照抄 Flutter Color(0xFF6366F1)）。 */
const SEL_COLOR = '#6366F1';
/** TV 焦点环颜色（照抄 Flutter TvFocusable 的 #C1C2FE）。 */
const FOCUS_RING_COLOR: string = '#C1C2FE';

// ── 顶栏芯片样式（Flutter player_top_bar._decodeChipDecoration）──────
/** 玻璃芯片渐变：白 22% → 10%。 */
const CHIP_GRAD: LinearGradientOptions = { angle: 180, colors: [['#38FFFFFF', 0.0], ['#1AFFFFFF', 1.0]] };
/** 无底变体（倍速/裸图标）：透明渐变。 */
const CHIP_GRAD_CLEAR: LinearGradientOptions = { angle: 180, colors: [['#00000000', 0.0], ['#00000000', 1.0]] };
/** 玻璃胶囊内边距（h9 v6）。 */
const PAD_CHIP: Padding = { left: 9, right: 9, top: 6, bottom: 6 };
/** 倍速纯图标+文字内边距（4）。 */
const PAD_PLAIN: Padding = { left: 4, right: 4, top: 4, bottom: 4 };
/** 无描边。 */
const BORDER_NONE: BorderOptions = { width: 0, color: Color.Transparent, radius: 10 };
/** 玻璃芯片常规描边（白 24%）。 */
const BORDER_CHIP: BorderOptions = { width: 1, color: '#3DFFFFFF', radius: 10 };
/** 芯片打开态描边（强调色 1.5）。 */
const BORDER_ACTIVE: BorderOptions = { width: 1.5, color: SEL_COLOR, radius: 10 };
/** TV 焦点环描边（3px）。 */
const BORDER_FOCUS: BorderOptions = { width: 3, color: FOCUS_RING_COLOR, radius: 10 };

/** 控件自动隐藏延时（播放中）。与 Flutter `controlsAutoHideAfter` 一致（5s）。 */
const AUTO_HIDE_MS = 5000;

/** 进度刷新周期（与本地插值配合，独立于 Dart 快照频率）。 */
const TICK_MS = 250;

function formatTime(ms: number): string {
  if (ms < 0 || !Number.isFinite(ms)) {
    return '00:00';
  }
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = m < 10 ? `0${m}` : `${m}`;
  const ss = s < 10 ? `0${s}` : `${s}`;
  if (h > 0) {
    return `${h}:${mm}:${ss}`;
  }
  return `${mm}:${ss}`;
}

/** XComponent surface 回调 → 宿主 → 插件 mpv 会话。 */
class ViewSurfaceCallbacks implements MpvSurfaceCallbacks {
  onSurfaceCreated(surfaceId: string): void {
    hilog.info(DOMAIN, TAG, 'surface created: %{public}s', surfaceId);
    HimiMpvNativeHost.getInstance().attachSurface(surfaceId);
  }

  onSurfaceChanged(surfaceId: string, width: number, height: number): void {
    HimiMpvNativeHost.getInstance().surfaceChanged(surfaceId, width, height);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    hilog.info(DOMAIN, TAG, 'surface destroyed: %{public}s', surfaceId);
    HimiMpvNativeHost.getInstance().detachSurface(surfaceId);
  }
}

/** 宿主状态变化 → 视图重绘。 */
class ViewListener implements NativePlayerViewListener {
  private readonly view: HimiNativePlayerView;

  constructor(view: HimiNativePlayerView) {
    this.view = view;
  }

  onNativeStateChanged(): void {
    this.view.onStateChanged();
  }
}

/**
 * 按下反馈（所有可点击控件的统一按下态）。
 *
 * Flutter 侧 TvFocusable/IconButton 自带 ripple/高亮，ArkUI 的裸 Text
 * 默认**无任何按下视觉反馈**——真机表现为「点了没反应」。用组件内
 * @Styles + stateStyles(pressed) 补一层透明度/缩放反馈。
 */
@Styles
function pressedFeedback() {
  .opacity(0.5);
  .scale({ x: 0.92, y: 0.92 });
}

@Component
export struct HimiNativePlayerView {
  @State revision: number = 0;
  @State showControls: boolean = true;
  @State progressMs: number = 0;
  @State dragMs: number = 0;
  @State dragging: boolean = false;
  @State currentTime: string = '';
  @State activePanel: string = '';
  /**
   * 锁定态（**必须 @State**）。
   *
   * `state().locked` 是宿主的普通字段，不在 ArkUI 观察链上——乐观更新只靠
   * `revision++` 间接触发重建，实测不可靠（真机回归：点锁后图标不实时变，
   * 要等控件隐藏再现才更新）。显式复制到 @State 才能保证同步。
   */
  @State locked: boolean = false;
  /** 竖屏判定（height > width）：竖屏隐藏顶栏标题。 */
  @State portrait: boolean = false;
  /** TV 焦点态：记录当前聚焦控件的 key，条件描边实现焦点环。 */
  @State focusedKey: string = '';

  /** 顶栏宽度 / 尾组内容宽（onAreaChange 喂入，转屏自适应收窄间距）。 */
  @State topRowW: number = 0;
  @State topTailW: number = 0;
  /** 顶栏尾组间距（8→4→2→0 逐级收窄，全部控件保持可见）。 */
  @State topGap: number = 8;
  /** 控件行宽度 / 传输组宽 / 右侧簇内容宽（同上）。 */
  @State ctrlRowW: number = 0;
  @State transportW: number = 0;
  @State bottomTailW: number = 0;
  /**
   * 底栏右侧簇等比缩放比（1 = 不缩）。
   *
   * 对齐 Flutter `FittedBox(scaleDown)`：`min(1, 可用宽 / 自然宽)`。
   * 旧方案「逐级收窄间距」在竖屏不可行（gap 归零仍溢出 32dp）。
   */
  @State bottomScale: number = 1;

  /** 手势提示文本（居中胶囊；空串 = 隐藏）。 */
  @State gestureHint: string = '';
  /** 手势提示是否为图标态（双击播放/暂停；无胶囊底）。 */
  @State gestureHintIsIcon: boolean = false;
  /** 亮度/音量柱条百分比（-1 = 隐藏）。 */
  @State verticalBarPercent: number = -1;
  /** 柱条贴哪边（true = 左侧亮度）。 */
  @State verticalBarOnLeft: boolean = false;
  /** 长按临时倍速是否激活中。 */
  @State speedBoostActive: boolean = false;

  private controller: MpvXComponentController = new MpvXComponentController();
  private listener: ViewListener | null = null;
  private tickId: number = -1;
  private hideDeadlineMs: number = 0;

  aboutToAppear(): void {
    const host = HimiMpvNativeHost.getInstance();
    this.listener = new ViewListener(this);
    host.registerListener(this.listener);
    this.controller.setCallbacks(new ViewSurfaceCallbacks());
    this.showControls = host.controlsVisible;
    this.locked = host.state.locked;
    this.progressMs = host.positionNowMs();
    this.dragMs = this.progressMs;
    this.currentTime = this.nowClock();
    this.hideDeadlineMs = Date.now() + AUTO_HIDE_MS;
    this.tickId = setInterval((): void => {
      this.tick();
    }, TICK_MS);
    hilog.info(DOMAIN, TAG, 'view appeared');
  }

  aboutToDisappear(): void {
    const host = HimiMpvNativeHost.getInstance();
    if (this.listener !== null) {
      host.unregisterListener(this.listener);
      this.listener = null;
    }
    if (this.tickId >= 0) {
      clearInterval(this.tickId);
      this.tickId = -1;
    }
    // 手势提示/柱条定时器：不清理会在视图销毁后仍回调。
    if (this.hintTimerId >= 0) {
      clearInterval(this.hintTimerId);
      this.hintTimerId = -1;
    }
    if (this.barTimerId >= 0) {
      clearInterval(this.barTimerId);
      this.barTimerId = -1;
    }
    // XComponent 销毁会触发 onSurfaceDestroyed → detachSurface，此处无需重复。
    hilog.info(DOMAIN, TAG, 'view disappeared');
  }

  /** 宿主状态推送回调（平台主线程 = UI 线程，可直接更新 @State）。 */
  onStateChanged(): void {
    const host = HimiMpvNativeHost.getInstance();
    this.showControls = host.controlsVisible;
    this.activePanel = host.activePanel !== null ? host.activePanel : '';
    // 锁定态必须显式同步到 @State（见字段注释：宿主字段不在观察链上）。
    this.locked = host.state.locked;
    if (!this.dragging) {
      this.progressMs = host.positionNowMs();
      this.dragMs = this.progressMs;
    }
    this.revision++;
  }

  private tick(): void {
    const host = HimiMpvNativeHost.getInstance();
    this.currentTime = this.nowClock();
    if (!this.dragging) {
      this.progressMs = host.positionNowMs();
      this.dragMs = this.progressMs;
    }
    // 自动隐藏：播放中且到点（计划书 §5.6）。
    if (host.controlsVisible && !host.state.paused &&
      Date.now() > this.hideDeadlineMs) {
      host.setControlsVisible(false);
      return;
    }
    this.showControls = host.controlsVisible;
  }

  /**
   * 顶栏时钟文本：尊重 `clockFormat`（off/12h/24h）。
   *
   * 旧实现写死 24h 且**非房间模式恒显示**（Flutter 只在 TV 且格式非 off
   * 时显示），观感与 Flutter 不一致。文案照抄 `formatPlayerClock`：
   * 12h 档为 `上午 H:MM` / `下午 H:MM`（12 点补 12、去掉前导零）。
   */
  private nowClock(): string {
    const fmt = this.state().clockFormat;
    if (fmt === 'off') {
      return '';
    }
    const d = new Date();
    const m = d.getMinutes();
    const mm = m < 10 ? `0${m}` : `${m}`;
    if (fmt === '12h') {
      const period = d.getHours() < 12 ? '上午' : '下午';
      const h12 = d.getHours() % 12 === 0 ? 12 : d.getHours() % 12;
      return `${period} ${h12}:${mm}`;
    }
    const h = d.getHours();
    return `${h < 10 ? `0${h}` : `${h}`}:${mm}`;
  }

  private pokeAutoHide(): void {
    this.hideDeadlineMs = Date.now() + AUTO_HIDE_MS;
  }

  private onTapLayer(): void {
    const host = HimiMpvNativeHost.getInstance();
    host.toggleControls();
    if (host.controlsVisible) {
      this.pokeAutoHide();
    }
  }

  private onBack(): void {
    HimiMpvNativeHost.getInstance().handleBack();
  }

  private onTogglePlay(): void {
    this.pokeAutoHide();
    HimiMpvNativeHost.getInstance().optimisticTogglePaused();
  }

  // ── 手势（对齐 Flutter VideoGestureLayer + player_screen.dart）────

  /** 双击：播放/暂停 + 图标提示（500ms）。 */
  private onDoubleTapGesture(): void {
    const s = this.state();
    if (s.locked || !s.canControl) {
      return;
    }
    HimiMpvNativeHost.getInstance().optimisticTogglePaused();
    // 提示显示切换**之后**的动作图标（与 Flutter 一致）。
    this.showGestureIcon(s.paused ? 0xE4CD : 0xE47E);
  }

  /** 横拖累计像素（每 100px → ±5s）。 */
  private hDragAccumPx: number = 0;
  /** 纵拖起始点在左半屏（亮度）还是右半屏（音量）。 */
  private dragOnLeftSide: boolean = false;
  /** 纵拖本地回显（0..1）。 */
  private brightness01: number = 1.0;
  private volume01: number = 1.0;
  /** 拖动起点的亮度/音量（ArkUI offsetY 是相对起点的累计位移，
   *  必须以起点为基准换算，不能按增量累加）。 */
  private dragBaseBrightness: number = 1.0;
  private dragBaseVolume: number = 1.0;
  /** 提示自动隐藏定时器。 */
  private hintTimerId: number = -1;

  /** 拖动开始：记录起始侧与起点亮度/音量。 */
  private onPanStart(event: GestureEvent): void {
    const s = this.state();
    if (s.locked || !s.canControl) {
      return;
    }
    this.hDragAccumPx = 0;
    this.dragOnLeftSide = event.offsetX < this.areaWidth / 2;
    this.dragBaseBrightness = this.brightness01;
    this.dragBaseVolume = this.volume01;
  }

  /** 拖动中：|dx|>|dy| 判横拖 seek，否则纵拖亮度/音量。 */
  private onPanUpdate(event: GestureEvent): void {
    const s = this.state();
    if (s.locked || !s.canControl) {
      return;
    }
    // ArkUI PanGesture 的 offsetX/offsetY 是**相对起点的累计位移**，
    // 与 Flutter 的 primaryDelta（增量）不同：这里直接以起点为基准换算。
    const totalDx = event.offsetX;
    const totalDy = event.offsetY;
    if (Math.abs(totalDx) > Math.abs(totalDy)) {
      // 横拖 seek：每 100px → 5s，上限 ±60s。
      this.hDragAccumPx = totalDx;
      const deltaMs = Math.round(totalDx / 100 * 5000);
      const clamped = Math.max(-60000, Math.min(60000, deltaMs));
      const preview = Math.max(0, Math.min(s.durationMs, s.positionMs + clamped));
      this.showGestureHint(formatTime(preview));
    } else {
      // 纵拖：左亮度 / 右音量（600px 全量程）。totalDy 正值 = 手指下滑
      // → 亮度/音量下降（与 Flutter `_brightness - delta/600` 一致）。
      const delta01 = -totalDy / 600;
      if (this.dragOnLeftSide) {
        this.brightness01 = Math.max(0, Math.min(1, this.dragBaseBrightness + delta01));
        this.verticalBarPercent = Math.round(this.brightness01 * 100);
        this.verticalBarOnLeft = true;
      } else {
        this.volume01 = Math.max(0, Math.min(1, this.dragBaseVolume + delta01));
        this.verticalBarPercent = Math.round(this.volume01 * 100);
        this.verticalBarOnLeft = false;
        HimiMpvNativeHost.getInstance().optimisticSetVolume(this.volume01);
      }
      this.scheduleVerticalBarHide();
    }
  }

  /** 拖动结束：横拖按累计位移 seek。 */
  private onPanEnd(): void {
    const s = this.state();
    if (s.locked || !s.canControl) {
      return;
    }
    if (Math.abs(this.hDragAccumPx) < 10) {
      return;
    }
    const deltaMs = Math.round(this.hDragAccumPx / 100 * 5000);
    const clamped = Math.max(-60000, Math.min(60000, deltaMs));
    this.hDragAccumPx = 0;
    if (clamped === 0) {
      return;
    }
    const target = Math.max(0, Math.min(s.durationMs, s.positionMs + clamped));
    HimiMpvNativeHost.getInstance().optimisticSeek(target);
    const seconds = Math.round(clamped / 1000);
    this.showGestureHint(`${seconds > 0 ? '+' : ''}${seconds}s`);
  }

  /** 长按临时倍速：激活升到 2×。 */
  private onSpeedBoostStart(): void {
    const s = this.state();
    if (s.locked || !s.canControl || this.speedBoostActive) {
      return;
    }
    this.speedBoostActive = true;
    this.boostBaseSpeed = s.speed;
    HimiMpvNativeHost.getInstance().optimisticSetSpeed(this.boostBaseSpeed * 2.0);
    this.showGestureHint(`${(2.0).toFixed(1)}× 播放中`, -1, false);
  }

  /** 长按结束：还原到长按前档位。 */
  private onSpeedBoostEnd(): void {
    if (!this.speedBoostActive) {
      return;
    }
    this.speedBoostActive = false;
    HimiMpvNativeHost.getInstance().optimisticSetSpeed(this.boostBaseSpeed);
    this.gestureHint = '';
  }

  /** 长按临时倍速的基准档位（松手还原用）。 */
  private boostBaseSpeed: number = 1.0;

  /** 显示文本提示（800ms 后隐藏；[ms] 传 -1 表示常显）。 */
  private showGestureHint(text: string, ms: number = 800, withBackground: boolean = true): void {
    this.gestureHintIsIcon = !withBackground;
    this.gestureHint = text;
    if (this.hintTimerId >= 0) {
      clearInterval(this.hintTimerId);
      this.hintTimerId = -1;
    }
    if (ms < 0) {
      return;
    }
    this.hintTimerId = setInterval((): void => {
      this.gestureHint = '';
      if (this.hintTimerId >= 0) {
        clearInterval(this.hintTimerId);
        this.hintTimerId = -1;
      }
    }, ms);
  }

  /** 显示图标提示（500ms 后隐藏；无胶囊底）。 */
  private showGestureIcon(codePoint: number): void {
    this.showGestureHint(String.fromCodePoint(codePoint), 500, false);
  }

  /** 柱条 800ms 后隐藏。 */
  private scheduleVerticalBarHide(): void {
    if (this.barTimerId >= 0) {
      clearInterval(this.barTimerId);
    }
    this.barTimerId = setInterval((): void => {
      this.verticalBarPercent = -1;
      if (this.barTimerId >= 0) {
        clearInterval(this.barTimerId);
        this.barTimerId = -1;
      }
    }, 800);
  }

  /** 柱条隐藏定时器。 */
  private barTimerId: number = -1;

  /** 屏幕宽度（手势起始侧判定用；onAreaChange 喂入）。 */
  private areaWidth: number = 0;

  private openPanel(type: string): void {
    this.pokeAutoHide();
    HimiMpvNativeHost.getInstance().togglePanel(type);
  }

  private state(): NativePlayerUiState {
    return HimiMpvNativeHost.getInstance().state;
  }

  // ── 图标字形（Material Icons 码点；与 tool/native_icons.json 同源）──

  private backGlyph(): string {
    return String.fromCodePoint(0xE092);
  }

  private speedGlyph(): string {
    return String.fromCodePoint(0xE5E0);
  }

  private kernelGlyph(): string {
    return String.fromCodePoint(0xE40D);
  }

  private subtitleStyleGlyph(): string {
    return String.fromCodePoint(0xE683);
  }

  private decodeGlyph(): string {
    return String.fromCodePoint(0xE3DB);
  }

  private videoFitGlyph(): string {
    const fit: string = this.state().videoFit;
    if (fit === 'cover') {
      return String.fromCodePoint(0xE2CB);
    }
    if (fit === 'fill') {
      return String.fromCodePoint(0xE6FF);
    }
    if (fit === 'none') {
      return String.fromCodePoint(0xE0A3);
    }
    return String.fromCodePoint(0xE28C);
  }

  private rotateGlyph(): string {
    return String.fromCodePoint(0xF07BF);
  }

  private danmakuGlyph(): string {
    return this.state().danmakuEnabled
      ? String.fromCodePoint(0xE17E)
      : String.fromCodePoint(0xF04D2);
  }

  private versionGlyph(): string {
    return String.fromCodePoint(0xE30F);
  }

  private subtitleGlyph(): string {
    return String.fromCodePoint(0xE619);
  }

  private audioGlyph(): string {
    return String.fromCodePoint(0xE0B6);
  }

  private playlistGlyph(): string {
    return String.fromCodePoint(0xE4D4);
  }

  private prevGlyph(): string {
    return String.fromCodePoint(0xE5BE);
  }

  private playGlyph(): string {
    return String.fromCodePoint(0xE4CD);
  }

  private pauseGlyph(): string {
    return String.fromCodePoint(0xE47E);
  }

  private nextGlyph(): string {
    return String.fromCodePoint(0xE5BD);
  }

  private lockGlyph(): string {
    return String.fromCodePoint(0xE3AE);
  }

  // ── 布局判定 ───────────────────────────────────────────────────

  /** 倍速文本（1.0x / 1.25x …）。 */
  private trimSpeed(speed: number): string {
    const r = Math.round(speed * 10) / 10;
    return `${r}`;
  }

  /** Logo 是否显示：仅单人播放且有 logo。 */
  private showLogo(): boolean {
    const s = this.state();
    return !s.isRoom && s.logoUrl.length > 0;
  }

  /** 版本/线路按钮：非房间模式且有多版本。 */
  private showVersionButton(): boolean {
    return !this.state().isRoom && this.state().versions.length > 1;
  }

  /** 选集按钮：非房间模式且多集。 */
  private showEpisodeButton(): boolean {
    return !this.state().isRoom && this.state().episodes.length > 1;
  }

  /** 时间数显列宽：时长 ≥1h 用 HH:MM:SS 档（78），否则 MM:SS 档（56）。 */
  private timeCellWidth(): number {
    return this.state().durationMs >= 3600000 ? 78 : 56;
  }

  /** 是否有上一集。 */
  private hasPrev(): boolean {
    return this.state().currentEpisodeIndex > 0;
  }

  /** 是否有下一集。 */
  private hasNext(): boolean {
    const s = this.state();
    return s.currentEpisodeIndex >= 0 && s.currentEpisodeIndex + 1 < s.episodes.length;
  }

  /** 多集：transport 上一集/下一集仅此时显示，否则空占位（与 Flutter 一致）。 */
  private multiEpisode(): boolean {
    return this.state().episodes.length > 1;
  }

  /**
   * 顶栏尾组间距自适应（真实收窄，不出屏）：
   * 放量（实宽 ≤ 可用 85%）回 8；超出则逐级 8→4→2→0。
   */
  private adjustTopGap(): void {
    const avail = this.topRowW - 44 - 24;
    if (this.topTailW <= 0 || avail <= 0) {
      return;
    }
    if (this.topTailW * 1.15 < avail) {
      this.topGap = 8;
    } else if (this.topTailW > avail) {
      this.topGap = Math.max(0, this.topGap - 2);
    }
  }

  /**
   * 底栏右侧簇间距自适应：放量回 20；超出逐级 20→8→4→0（可用宽 =
   * (行宽-传输组)/2，与 Flutter PlayerBottomRow 三段语义一致）。
   */
  /**
   * 底栏右侧簇等比缩放（对齐 Flutter `FittedBox(scaleDown)`）。
   *
   * 可用宽 = `(控件行宽 - 传输组宽) / 2`（Flutter PlayerBottomRow 两个
   * Expanded 同宽 → 传输组精确居中，trailing 槽拿到这一半）。
   */
  private adjustBottomScale(): void {
    const avail = (this.ctrlRowW - this.transportW) / 2;
    if (this.bottomTailW <= 0 || avail <= 0) {
      this.bottomScale = 1;
      return;
    }
    this.bottomScale = this.bottomTailW > avail
      ? Math.min(1, avail / this.bottomTailW)
      : 1;
  }

  /** 版本/线路角标：显示线路数（与 Flutter sources.length 一致）。 */
  private versionBadge(): string {
    return `${this.state().versions.length}`;
  }

  /** 字幕角标：仅在有字幕流时显示数量（与 Flutter 一致）。 */
  private subtitleBadge(): string {
    const n = this.state().subtitleStreamCount;
    return n > 0 ? `${n}` : '';
  }

  /** 音轨角标：仅在有音轨流时显示数量（与 Flutter 一致）。 */
  private audioBadge(): string {
    const n = this.state().audioStreamCount;
    return n > 0 ? `${n}` : '';
  }

  /** 选集角标：集数（与 Flutter totalEpisodeCount 一致）。 */
  private episodeBadge(): string {
    return `${this.state().episodes.length}`;
  }

  /** 上一集（经面板命令回传 Dart）。 */
  private onPrevEpisode(): void {
    const host = HimiMpvNativeHost.getInstance();
    if (!this.hasPrev()) {
      return;
    }
    host.optimisticSelectEpisode(this.state().currentEpisodeIndex - 1);
  }

  /** 下一集。 */
  private onNextEpisode(): void {
    const host = HimiMpvNativeHost.getInstance();
    if (!this.hasNext()) {
      return;
    }
    host.optimisticSelectEpisode(this.state().currentEpisodeIndex + 1);
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // ── 视频层 ──
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.controller,
      })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        // 【兜底：尺寸同步】XComponent 的 onSurfaceChanged 在部分转屏场景
        // 不触发（子窗口尺寸变化但 surface 未重建），导致 mpv 仍按旧尺寸
        // 合成 → 竖屏画面被拉长铺满。这里用 onAreaChange 补一次同步：
        // 宿主的 surfaceChanged 有「尺寸未变则跳过」的幂等保护，重复调用无害。
        .onAreaChange((_old: Area, area: Area): void => {
          const w = area.width as number;
          const h = area.height as number;
          if (w > 0 && h > 0) {
            HimiMpvNativeHost.getInstance().surfaceChanged('', Math.trunc(w), Math.trunc(h));
          }
        });

      // ── 点按层：视频手势（对齐 Flutter VideoGestureLayer）──
      // 单击显隐控件；双击播放暂停；横拖 seek；纵拖左亮度/右音量；
      // 长按临时倍速。锁定中只保留单击（与 Flutter 一致）。
      //
      // ArkUI 的 `.gesture()` 最多收 2 个参数，多个手势必须用
      // `GestureGroup(Parallel)`——等价 Flutter 手势竞技场：单击/双击由
      // 框架按时间消歧，长按与拖动按位移消歧（位移超阈值即取消长按）。
      Column()
        .width('100%')
        .height('100%')
        .gesture(
          GestureGroup(GestureMode.Parallel,
            // 单击：面板打开先关，否则切换控件显隐。
            TapGesture({ count: 1 }).onAction((): void => {
              this.onTapLayer();
            }),
            // 双击：播放/暂停。
            TapGesture({ count: 2 }).onAction((): void => {
              this.onDoubleTapGesture();
            }),
            // 拖动：横拖 seek / 纵拖亮度音量。
            PanGesture({ direction: PanDirection.All })
              .onActionStart((event: GestureEvent): void => {
                this.onPanStart(event);
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.onPanUpdate(event);
              })
              .onActionEnd((): void => {
                this.onPanEnd();
              }),
            // 长按：临时倍速（松手还原）。
            LongPressGesture({ repeat: false })
              .onAction((): void => {
                this.onSpeedBoostStart();
              })
              .onActionEnd((): void => {
                this.onSpeedBoostEnd();
              })
              .onActionCancel((): void => {
                this.onSpeedBoostEnd();
              }),
          ),
        )
        // 【必须 Default，不能 Transparent】Stack 命中测试自上而下：
        // 控件条在上层，若本层用 Transparent 会与控件**同时**进入手势竞技场，
        // 而本层的 PanGesture（Parallel）会抢走触摸流 → 底部控件 onClick
        // 全部失效、面板遮罩点不关（真机回归）。Default 下控件先声明成功，
        // 本层不再介入；空视频区无控件声明，本层照常接管。
        .hitTestBehavior(HitTestMode.Default);

      // ── 弹幕层：视频之上、控件之下（原生渲染，Flutter 弹幕层随视频区
      //    退场 → 弹幕开关在原生 UI 下必须由本层生效）──
      DanmakuLayer({ revision: this.revision });

      if (this.showControls) {
        if (this.locked && !this.state().tvMode) {
          // ── 锁定态：仅左下锁钮（与进度条左数显同列）──
          this.LockOnlyBar();
        } else {
          this.TopBar();
          this.BottomBar();
        }
      }

      // ── 手势提示与亮度/音量柱条（视频之上、控件之下）──
      // 对齐 Flutter `_buildGestureHint` / `_buildVerticalBar` 的层级。
      if (this.gestureHint.length > 0) {
        Text(this.gestureHint)
          .fontFamily(this.gestureHintIsIcon ? NativePlayerIcons.FONT_FAMILY : '')
          .fontSize(this.gestureHintIsIcon ? 48 : 16)
          .fontWeight(this.gestureHintIsIcon ? FontWeight.Normal : FontWeight.Bold)
          .fontColor(this.gestureHintIsIcon ? '#B3FFFFFF' : Color.White)
          .padding(this.gestureHintIsIcon ? 0 : {
            left: 16, right: 16, top: 8, bottom: 8,
          })
          .backgroundColor(this.gestureHintIsIcon ? Color.Transparent : '#8C000000')
          .borderRadius(this.gestureHintIsIcon ? 0 : 16)
          .hitTestBehavior(HitTestMode.None)
          .align(Alignment.Center);
      }

      if (this.verticalBarPercent >= 0) {
        Text(`${this.verticalBarPercent}%`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(48)
          .height(160)
          .textAlign(TextAlign.Center)
          .backgroundColor('#8C000000')
          .borderRadius(16)
          .hitTestBehavior(HitTestMode.None)
          // 亮度柱在右、音量柱在左（与 Flutter 实现一致）。
          .align(this.verticalBarOnLeft ? Alignment.TopStart : Alignment.TopEnd)
          .margin({
            left: this.verticalBarOnLeft ? 16 : 0,
            top: 100,
            right: this.verticalBarOnLeft ? 0 : 16,
          });
      }

      // ── 二级面板（Phase 2）：遮住视频，点外/返回关闭 ──
      if (this.activePanel.length > 0) {
        NativePlayerPanel({
          panelType: this.activePanel,
          revision: this.revision,
        });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    // 手势起始侧判定（左亮度 / 右音量）需要屏幕宽度；竖屏判定（隐藏标题）
    // 需要宽高比。
    .onAreaChange((_old: Area, area: Area): void => {
      const w = area.width as number;
      const h = area.height as number;
      this.areaWidth = w;
      this.portrait = h > w && w > 0;
    });
  }

  /**
   * 手机锁定态底栏：对齐 Flutter `_buildLockOnlyControls`——
   * 底部渐变条（transparent → black@0.85，padding 16/10/16/12）内只放一个
   * 锁钮，且锁钮在**时间数显列宽**（56/78）内居中（与进度条左数显同轴）。
   *
   * 旧实现是全屏 Column + 裸 56×56 文本、无渐变底、锁钮贴 x=0，与 Flutter
   * 观感差异明显（真机回归）。
   */
  @Builder
  LockOnlyBar() {
    Column() {
      Row() {
        // 时间数显列宽内居中（Flutter: SizedBox(cellWidth, Align(center, ...))）。
        Row() {
          Text(String.fromCodePoint(this.locked
            ? NativePlayerIcons.ICON_LOCK
            : NativePlayerIcons.ICON_LOCK_OPEN))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(22)
            .fontColor(Color.White)
            .padding(8)
            .backgroundColor('#73000000')
            .borderRadius(18)
            .onClick((): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleLock();
            });
        }
        .width(this.timeCellWidth())
        .justifyContent(FlexAlign.Center);
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 12 })
      .justifyContent(FlexAlign.Start);
    }
    .width('100%')
    // 【必须 angle:180】ArkUI linearGradient 的 angle 是**方向角**：
    // 180 = 自上而下；90 = 对角（透明左上 → 黑右下），会把右侧整条压黑成
    // 「黑幕」（真机截图回归）。与 BottomBar 同值。
    .linearGradient({
      angle: 180,
      colors: [['#00000000', 0.0], ['#D9000000', 1.0]],
    })
    // 底部渐变条（非全屏高度）：wrap 高度 + 贴底，对齐 Flutter
    // `_buildLockOnlyControls`（Container with bottom gradient）。
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: '0%', y: '100%' })
    // 【空点击吸收】点背景不穿透到底层手势层（与顶/底栏一致）。
    .onClick((): void => {
    });
  }

  /** 顶栏：返回 / 标题 / 网速 | 内核胶囊（+倍速）| 时钟（TV）。 */
  @Builder
  TopBar() {
    Row() {
      Text(this.backGlyph())
        .fontFamily(NativePlayerIcons.FONT_FAMILY)
        .fontSize(22)
        .fontColor(Color.White)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick((): void => {
          this.onBack();
        });
      // 竖屏隐藏标题：竖屏可用宽窄，标题会被尾簇压成「…」（真机截图回归）。
      // 横屏保留（横屏有足够宽度显示完整标题）。
      if (!this.portrait) {
        Text(this.state().displayTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: 4, right: 8 });
      } else {
        // 竖屏仍需一个权重占位，否则尾簇会左移贴到返回键。
        Row()
          .layoutWeight(1)
          .margin({ left: 4, right: 8 });
      }
      // 右侧簇：项间距 8（Flutter SizedBox(8) 链）。
      Row({ space: this.topGap }) {
        if (this.state().networkSpeedText.length > 0) {
          Text(this.state().networkSpeedText)
            .fontSize(12)
            .fontColor('#B3FFFFFF');
        }
        if (!this.state().tvMode && !this.state().isRoom) {
          this.Chip(this.speedGlyph(), `${this.trimSpeed(this.state().speed)}x`, 20, true,
            this.activePanel === NativePlayerPanelType.speed, 'topSpeed', (): void => {
              this.openPanel(NativePlayerPanelType.speed);
            });
        }
        this.Chip('', this.state().engineLabel, 0, false,
          this.activePanel === NativePlayerPanelType.kernel, 'kernel', (): void => {
            this.openPanel(NativePlayerPanelType.kernel);
          });
        if (!this.state().tvMode) {
          this.IconChip(this.subtitleStyleGlyph(), 18, 6, true,
            this.activePanel === NativePlayerPanelType.display, 'topDisplay', (): void => {
              this.openPanel(NativePlayerPanelType.display);
            });
          // 解码：Erika 无解码档位 → 隐藏（对齐 Flutter）。
          if (this.state().engineLabel !== 'Erika') {
            this.IconChip(this.decodeGlyph(), 18, 6, true,
              this.activePanel === NativePlayerPanelType.decode, 'decode', (): void => {
                this.openPanel(NativePlayerPanelType.decode);
              });
          }
          // 画面比例：Erika 缩放不可用、房间不显示（对齐 Flutter）。
          if (!this.state().isRoom && this.state().engineLabel !== 'Erika') {
            this.IconChip(this.videoFitGlyph(), 22, 6, false,
              false, 'videoFit', (): void => {
                this.pokeAutoHide();
                HimiMpvNativeHost.getInstance().optimisticCycleVideoFit();
              });
          }
          this.IconChip(this.rotateGlyph(), 22, 6, false,
            false, 'rotate', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleOrientation();
            });
        }
        // 分享（仅房间模式；对齐 Flutter showShare）。
        // 时钟（仅 TV 且格式非 off；对齐 Flutter PlayerClockLayer：
        // `if (!tvMode || !format.enabled) return shrink`）。
        if (this.state().isRoom) {
          this.IconChip(String.fromCodePoint(NativePlayerIcons.ICON_SHARE), 22, 6, false,
            false, 'share', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().shareRoom();
            });
        } else if (this.state().tvMode && this.state().clockFormat !== 'off') {
          Text(this.nowClock())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#B3FFFFFF')
            .width(100)
            .height(48)
            .textAlign(TextAlign.End)
            .padding({ right: 0 });
        }
      }
      .alignItems(VerticalAlign.Center)
      // 尾组自适应：真实收窄间距（8→4→2→0）。markAnchor/position 都会
      // 真实位移布局（百分比基准随父容器漂移 → 控件跑位/被推出屏外，
      // 真机回归），scale 只改绘制不改占位——全部弃用。
      .onAreaChange((_old: Area, area: Area): void => {
        this.topTailW = area.width as number;
        this.adjustTopGap();
      });
    }
    .width('100%')
    // 顶栏避让刘海（Flutter 靠 MediaQuery.padding.top；子窗口开了全屏布局）。
    .padding({
      left: 12,
      right: 12,
      top: 10 + HimiMpvNativeHost.getInstance().safeAreaTop,
      bottom: 10,
    })
    .alignItems(VerticalAlign.Center)
    .onAreaChange((_old: Area, area: Area): void => {
      this.topRowW = area.width as number;
    })
    // 【空点击吸收】对齐 Flutter `_buildTopBar` 外层 GestureDetector：
    // 点条形背景被吸收、**不穿透**到底层手势层（否则一点背景就隐藏控件）。
    // 按钮自身的 onClick 优先，空 onClick 只兜住背景区域。
    .onClick((): void => {
    })
    .linearGradient({
      angle: 180,
      colors: [['#CC000000', 0.0], ['#00000000', 1.0]],
    });
  }

  /** 底栏：Logo / 进度条 / 播放组（手机居中·TV 置左）/ 右侧图标组。 */
  @Builder
  BottomBar() {
    Column() {
      if (this.showLogo()) {
        Image(this.state().logoUrl)
          .width(240)
          .height(44)
          .objectFit(ImageFit.Contain)
          .margin({ bottom: 4 });
      }
      Row() {
        Text(formatTime(this.dragging ? this.dragMs : this.progressMs))
          .fontSize(12)
          .fontColor('#B3FFFFFF')
          .width(this.timeCellWidth())
          .textAlign(TextAlign.End);
        Slider({
          value: this.dragging ? this.dragMs : this.progressMs,
          min: 0,
          max: this.state().durationMs > 0 ? this.state().durationMs : 1,
          step: 1000,
        })
          .layoutWeight(1)
          .selectedColor(SEL_COLOR)
          // 与 Flutter glassSliderTheme 对齐：未播段 = white@0.16
          //（旧值 #33FFFFFF = 0.20 偏亮，与 Flutter/安卓都不一致）。
          .trackColor('#29FFFFFF')
          // track 6dp + 8dp 半径蓝圆点拇指（直径 16），提示气泡关闭。
          .trackThickness(6)
          .trackBorderRadius(3)
          .blockColor(SEL_COLOR)
          .blockSize({ width: 16, height: 16 })
          .showTips(false)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.pokeAutoHide();
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
              this.dragging = true;
              this.dragMs = value;
            } else if (mode === SliderChangeMode.End) {
              this.dragging = false;
              this.dragMs = value;
              this.progressMs = value;
              HimiMpvNativeHost.getInstance().optimisticSeek(Math.round(value));
            }
          });
        Text(formatTime(this.state().durationMs))
          .fontSize(12)
          .fontColor('#B3FFFFFF')
          .width(this.timeCellWidth())
          .textAlign(TextAlign.Start);
      }
      // TV + 片头片尾功能开启时，长按进度条 → 标记卡。
      // 对齐 Flutter `segmentTvMark = _segmentFeatureEnabled && tvMode`；
      // 旧实现无条件绑定，手机上长按进度条会误弹标记卡。
      .gesture(
        this.state().tvMode && this.state().segmentEnabled
          ? LongPressGesture().onAction((): void => {
            this.pokeAutoHide();
            HimiMpvNativeHost.getInstance().togglePanel(NativePlayerPanelType.segment);
          })
          : undefined,
      )
      .width('100%')
      .alignItems(VerticalAlign.Center);

      this.ControlRow();
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    // 底栏避让手势条（Flutter：`12 + MediaQuery.padding.bottom`）。
    .padding({
      left: 16,
      right: 16,
      top: 10,
      bottom: 14 + HimiMpvNativeHost.getInstance().safeAreaBottom,
    })
    // Flutter _buildControls：transparent → black@0.85 自上而下渐变。
    // angle 180 = 自上而下；angle 0 = 自左向右（会把整条横向压黑成硬边
    // 「黑幕」，即真机回归观感）。
    .linearGradient({
      angle: 180,
      colors: [['#00000000', 0.0], ['#D9000000', 1.0]],
    })
    // 【空点击吸收】对齐 Flutter `_buildControls` 外层 GestureDetector：
    // 点条形背景被吸收、不穿透到底层手势层（否则一点背景就隐藏控件）。
    .onClick((): void => {
    })
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: '0%', y: '100%' });
  }

  /** 控件行：播放组（手机居中 / TV 置左）+ 右侧图标组。 */
  @Builder
  ControlRow() {
    Stack({ alignContent: Alignment.Center }) {
      // 传输组：项间距 8（Flutter SizedBox(8)），单集/电影 prev/next 空占位 28。
      // 关键：**不设 width('100%')**，让 Row 保持内容宽度，靠外层
      // Stack(alignContent: Center) 精确水平居中（设 width 100% + Start
      // 会撑满整行并左对齐 → 播放键偏左，真机回归）。
      Row({ space: 8 }) {
        if (this.multiEpisode()) {
          this.TransportGlyph(this.prevGlyph(), 28, this.hasPrev(), 'prev', (): void => {
            this.pokeAutoHide();
            this.onPrevEpisode();
          });
        } else {
          // 单集/电影：空占位保持播放键居中（与 Flutter SizedBox(28) 一致）。
          Row().width(28).height(28);
        }
        this.TransportGlyph(this.playGlyph(), 36, this.state().canControl, 'play', (): void => {
          this.onTogglePlay();
        });
        if (this.multiEpisode()) {
          this.TransportGlyph(this.nextGlyph(), 28, this.hasNext(), 'next', (): void => {
            this.pokeAutoHide();
            this.onNextEpisode();
          });
        } else {
          Row().width(28).height(28);
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .onAreaChange((_old: Area, area: Area): void => {
        this.transportW = area.width as number;
      });

      // 【右侧簇自适应】对齐 Flutter `FittedBox(scaleDown, alignment:
      // centerRight)`。
      //
      // 结构：外层全宽槽位（Stack 贴右）→ 内层**自然宽** Row（测自然宽）
      // → scale 朝右缘收缩。
      //
      // 旧方案「逐级收窄间距 20→8→4→0」不可行：竖屏可用宽 ~96dp，4 个图标
      // 在 gap=0 时仍需 128dp → 仍溢出 32dp，最右两项被裁（真机截图回归）。
      // 缩放从**自然宽**（gap 20）起算，与 Flutter 同语义。
      Stack({ alignContent: Alignment.End }) {
        Row({ space: 20 }) {
          this.IconChip(this.danmakuGlyph(), 24, 4, false,
            this.state().danmakuEnabled, 'danmaku', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleDanmaku();
            });
          if (this.showVersionButton()) {
            this.BadgeIconChip(this.versionGlyph(), this.versionBadge(),
              this.activePanel === NativePlayerPanelType.version, 'version', (): void => {
                this.openPanel(NativePlayerPanelType.version);
              });
          }
          if (this.state().tvMode) {
            this.IconChip(this.subtitleStyleGlyph(), 24, 4, false,
              this.activePanel === NativePlayerPanelType.display, 'tvDisplay', (): void => {
                this.openPanel(NativePlayerPanelType.display);
              });
          }
          this.BadgeIconChip(this.subtitleGlyph(), this.subtitleBadge(),
            this.activePanel === NativePlayerPanelType.subtitle, 'subtitle', (): void => {
              this.openPanel(NativePlayerPanelType.subtitle);
            });
          this.BadgeIconChip(this.audioGlyph(), this.audioBadge(),
            this.activePanel === NativePlayerPanelType.audio, 'audio', (): void => {
              this.openPanel(NativePlayerPanelType.audio);
            });
          if (this.showEpisodeButton()) {
            this.BadgeIconChip(this.playlistGlyph(), this.episodeBadge(),
              this.activePanel === NativePlayerPanelType.episode, 'episode', (): void => {
                this.openPanel(NativePlayerPanelType.episode);
              });
          }
          if (this.state().tvMode && !this.state().isRoom) {
            this.Chip(this.speedGlyph(), `${this.trimSpeed(this.state().speed)}x`, 24, true,
              this.activePanel === NativePlayerPanelType.speed, 'bottomSpeed', (): void => {
                this.openPanel(NativePlayerPanelType.speed);
              });
          }
        }
        .alignItems(VerticalAlign.Center)
        // scale 只改渲染不改布局：内层 Row 仍按自然宽占位、贴右。
        // 用 transform 的 centerX/centerY 指定变换锚点在**右缘 + 垂直中**，
        // 让缩放朝右缘收缩（本 SDK 无 transformOrigin 属性）。
        .transform({
          scaleX: this.bottomScale,
          scaleY: this.bottomScale,
          centerX: '100%',
          centerY: '50%',
        })
        .onAreaChange((_old: Area, area: Area): void => {
          // onAreaChange 报的是**布局宽** = 自然宽（scale 不参与布局）。
          this.bottomTailW = area.width as number;
          this.adjustBottomScale();
        });
      }
      // 【不要 height('100%')】外层 Stack 若撑满 ControlRow，会让 Column
      // 高度异常、底栏内容整体被顶到屏幕上方（真机截图回归）。只保留
      // width('100%') 撑满横向槽位。
      .width('100%');

      // 左侧簇：手机模式锁钮（Flutter 底栏 leading 槽 PlayerLockButton）。
      // 未锁显 lock_open（点击上锁），已锁显 lock（点击解锁）；列宽与
      // 进度条左数显同宽（timeCellWidth），保证与上方时间数显同轴。
      if (!this.state().tvMode && !this.state().isRoom) {
        Row() {
          Text(String.fromCodePoint(this.locked
            ? NativePlayerIcons.ICON_LOCK
            : NativePlayerIcons.ICON_LOCK_OPEN))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(22)
            .fontColor('#B3FFFFFF')
            .width(this.timeCellWidth())
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick((): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleLock();
            });
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .justifyContent(FlexAlign.Start);
      }

      if (this.locked && this.state().tvMode) {
        Row() {
          Text(String.fromCodePoint(NativePlayerIcons.ICON_LOCK))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(22)
            .fontColor('#B3FFFFFF')
            .onClick((): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleLock();
            });
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .justifyContent(FlexAlign.Start);
      }
    }
    .width('100%')
    .onAreaChange((_old: Area, area: Area): void => {
      this.ctrlRowW = area.width as number;
    });
  }

  /** 文字胶囊（倍速/内核/TV 倍速）。 */
  @Builder
  Chip(icon: string, label: string, iconSize: number, plain: boolean, active: boolean, key: string,
    onTap: () => void) {
    Row() {
      if (icon.length > 0) {
        Text(icon)
          .fontFamily(NativePlayerIcons.FONT_FAMILY)
          .fontSize(iconSize)
          .fontColor(active ? SEL_COLOR : Color.White);
      }
      if (label.length > 0) {
        Text(label)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(active ? SEL_COLOR : (plain ? '#B3FFFFFF' : Color.White))
          .margin({ left: 4 });
      }
    }
    // 倍速为纯图标+文字（Flutter 无底，padding 4）；内核为玻璃胶囊
    //（Flutter _decodeChipDecoration：白 22%→10% 渐变 + 白 24% 描边）。
    .padding(plain ? PAD_PLAIN : PAD_CHIP)
    .linearGradient(plain ? CHIP_GRAD_CLEAR : CHIP_GRAD)
    .borderRadius(10)
    // TV 焦点环优先（3px #C1C2FE），否则常规芯片描边（打开态强调色）。
    .border(this.focusedKey === key
      ? BORDER_FOCUS
      : (active ? BORDER_ACTIVE : (plain ? BORDER_NONE : BORDER_CHIP)))
    // TV 遥控器可达：可聚焦（非 TV 设备 focusable 不影响触摸）。
    .focusable(true)
    .focusOnTouch(true)
    .stateStyles({ pressed: pressedFeedback })
    .onFocus((): void => { this.focusedKey = key; })
    .onBlur((): void => { this.focusedKey = ''; })
    .onClick(onTap);
  }

  /**
   * 图标玻璃方块。glass=true 为顶栏芯片（tune/memory：18 图标 + 6 内边距 +
   * 玻璃底，Flutter _decodeChipDecoration）；glass=false 为裸图标
   //（底栏 24 图标 + 4 内边距 / 顶栏比例转屏 22 图标 + 6 内边距）。
   */
  @Builder
  IconChip(icon: string, iconSize: number, pad: number, glass: boolean, active: boolean, key: string,
    onTap: () => void) {
    Text(icon)
      .fontFamily(NativePlayerIcons.FONT_FAMILY)
      .fontSize(iconSize)
      .fontColor(active ? SEL_COLOR : Color.White)
      .padding(pad)
      .linearGradient(glass ? CHIP_GRAD : CHIP_GRAD_CLEAR)
      .borderRadius(10)
      .border(this.focusedKey === key
        ? BORDER_FOCUS
        : (glass ? (active ? BORDER_ACTIVE : BORDER_CHIP) : BORDER_NONE))
      .focusable(true)
      .focusOnTouch(true)
      .stateStyles({ pressed: pressedFeedback })
      .onFocus((): void => { this.focusedKey = key; })
      .onBlur((): void => { this.focusedKey = ''; })
      .onClick(onTap);
  }

  /**
   * 带角标的图标玻璃方块（版本/字幕/音轨/选集）。
   *
   * 角标：#6366F1 正圆底 + 9px 白字，贴图标右上（right:-6 top:-4，与
   * Flutter `_buildControlButton` 的 Positioned 一致）；badge 为空串时不渲染。
   *
   * 关键修复（真机截图回归）：旧实现用 constraintSize + borderRadius(9)，
   * 文本宽超过 14 时会变成椭圆/胶囊（"47" 明显压扁）。Flutter 的
   * BoxShape.circle 画的是「内切于最短边的正圆」，这里改用**定宽定高**
   * 容器 + borderRadius 取边长一半，保证恒为正圆；边长按文本长度阶梯取值
   * （1~2 位 14dp，3 位起 18dp）。
   */
  @Builder
  BadgeIconChip(icon: string, badge: string, active: boolean, key: string, onTap: () => void) {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.IconChip(icon, 24, 4, false, active, key, onTap);
      if (badge.length > 0) {
        Text(badge)
          .fontSize(9)
          .fontColor(Color.White)
          .backgroundColor(SEL_COLOR)
          .width(this.badgeSide(badge))
          .height(this.badgeSide(badge))
          .borderRadius(this.badgeSide(badge) / 2)
          .textAlign(TextAlign.Center)
          .align(Alignment.Center)
          // Flutter Positioned(right:-6, top:-4)：相对 24 图标边。本 Stack 含
          // 4 内边距（图标位于 4..28），换算为 margin right -2 / top 0。
          .margin({ right: -2 });
      }
    }
  }

  /** 角标正圆边长（dp）：1~2 位 14，3 位起 18（文本加 padding 后仍内切）。 */
  private badgeSide(badge: string): number {
    return badge.length >= 3 ? 18 : 14;
  }

  /** 传输组按钮（上一集/播放/下一集）。 */
  @Builder
  TransportGlyph(icon: string, size: number, enabled: boolean, key: string, onTap: () => void) {
    Text(icon)
      .fontFamily(NativePlayerIcons.FONT_FAMILY)
      .fontSize(size)
      .fontColor(enabled ? Color.White : '#3DFFFFFF')
      .padding(4)
      .focusable(enabled)
      .focusOnTouch(true)
      .border(this.focusedKey === key
        ? { width: 3, color: FOCUS_RING_COLOR, radius: 12 }
        : { width: 0, color: Color.Transparent })
      .stateStyles({ pressed: pressedFeedback })
      .onFocus((): void => { this.focusedKey = key; })
      .onBlur((): void => { this.focusedKey = ''; })
      .onClick((): void => {
        // 不可用（无上一集/无下一集/不可控制）时仍给按下反馈，只是不执行
        // 动作——否则用户点击后毫无视觉响应，误以为控件失效（真机回归）。
        if (enabled) {
          onTap();
        }
      });
  }
}
