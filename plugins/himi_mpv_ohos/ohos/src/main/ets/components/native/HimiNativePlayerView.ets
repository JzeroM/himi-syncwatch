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

/** 控件自动隐藏延时（播放中）。 */
const AUTO_HIDE_MS = 4000;

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

@Component
export struct HimiNativePlayerView {
  @State revision: number = 0;
  @State showControls: boolean = true;
  @State progressMs: number = 0;
  @State dragMs: number = 0;
  @State dragging: boolean = false;
  @State currentTime: string = '';
  @State activePanel: string = '';
  /** TV 焦点态：记录当前聚焦控件的 key，条件描边实现焦点环。 */
  @State focusedKey: string = '';

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
    // XComponent 销毁会触发 onSurfaceDestroyed → detachSurface，此处无需重复。
    hilog.info(DOMAIN, TAG, 'view disappeared');
  }

  /** 宿主状态推送回调（平台主线程 = UI 线程，可直接更新 @State）。 */
  onStateChanged(): void {
    const host = HimiMpvNativeHost.getInstance();
    this.showControls = host.controlsVisible;
    this.activePanel = host.activePanel !== null ? host.activePanel : '';
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

  private nowClock(): string {
    const d = new Date();
    const h = d.getHours();
    const m = d.getMinutes();
    return `${h < 10 ? '0' : ''}${h}:${m < 10 ? '0' : ''}${m}`;
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
        .backgroundColor(Color.Black);

      // ── 点按层：点屏显隐（位于视频之上、控件之下）──
      Column()
        .width('100%')
        .height('100%')
        .gesture(
          TapGesture().onAction((): void => {
            this.onTapLayer();
          }),
        )
        .hitTestBehavior(HitTestMode.Transparent);

      if (this.showControls) {
        if (this.state().locked && !this.state().tvMode) {
          // ── 锁定态：仅左下锁钮（与进度条左数显同列）──
          this.LockOnlyBar();
        } else {
          this.TopBar();
          this.BottomBar();
        }
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
    .backgroundColor(Color.Black);
  }

  /** 手机锁定态：仅左下锁钮（与进度条左数显同列）。 */
  @Builder
  LockOnlyBar() {
    Column() {
      Row() {
        Text(String.fromCodePoint(NativePlayerIcons.ICON_LOCK))
          .fontFamily(NativePlayerIcons.FONT_FAMILY)
          .fontSize(22)
          .fontColor('#B3FFFFFF')
          .width(56)
          .height(56)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.pokeAutoHide();
            HimiMpvNativeHost.getInstance().optimisticToggleLock();
          });
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom);
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 90,
      colors: [['#00000000', 0.0], ['#99000000', 1.0]],
    })
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: '0%', y: '100%' });
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
      Text(this.state().displayTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 4, right: 8 });
      // 右侧簇：项间距 8（Flutter SizedBox(8) 链）。
      Row({ space: 8 }) {
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
          this.IconChip(this.decodeGlyph(), 18, 6, true,
            this.activePanel === NativePlayerPanelType.decode, 'decode', (): void => {
              this.openPanel(NativePlayerPanelType.decode);
            });
          this.IconChip(this.videoFitGlyph(), 22, 6, false,
            false, 'videoFit', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticCycleVideoFit();
            });
          this.IconChip(this.rotateGlyph(), 22, 6, false,
            false, 'rotate', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleOrientation();
            });
        } else {
          Text(this.currentTime)
            .fontSize(13)
            .fontColor('#B3FFFFFF')
            .width(100)
            .height(48)
            .textAlign(TextAlign.Center);
        }
      }
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
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
          .trackColor('#33FFFFFF')
          // 与 Flutter 观感对齐（NativePlayerTheme）：track 6dp + 8dp 半径
          // 蓝圆点拇指（直径 16），提示气泡关闭（原始毫秒值无意义）。
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
      // TV 长按进度条 → 片头片尾标记卡（与 Flutter onLongPress 一致）。
      .gesture(
        LongPressGesture().onAction((): void => {
          this.pokeAutoHide();
          HimiMpvNativeHost.getInstance().togglePanel(NativePlayerPanelType.segment);
        }),
      )
      .width('100%')
      .alignItems(VerticalAlign.Center);

      this.ControlRow();
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 14 })
    .linearGradient({
      angle: 0,
      colors: [['#00000000', 0.0], ['#CC000000', 1.0]],
    })
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: '0%', y: '100%' });
  }

  /** 控件行：播放组（手机居中 / TV 置左）+ 右侧图标组。 */
  @Builder
  ControlRow() {
    Stack({ alignContent: Alignment.Center }) {
      // 传输组：项间距 8（Flutter SizedBox(8)），单集/电影 prev/next 空占位 28。
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
      .justifyContent(FlexAlign.Start)
      .width('100%');

      // 右侧簇：项间距 20（Flutter SizedBox(20) 链）。
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
      .width('100%')
      .justifyContent(FlexAlign.End);

      if (this.state().locked && this.state().tvMode) {
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
    .width('100%');
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
      .onFocus((): void => { this.focusedKey = key; })
      .onBlur((): void => { this.focusedKey = ''; })
      .onClick(onTap);
  }

  /**
   * 带角标的图标玻璃方块（版本/字幕/音轨/选集）。
   * 角标：#6366F1 圆底 + 9px 白字，贴图标右上（right:-6 top:-4，与 Flutter
   * _buildControlButton 的 Positioned 一致）；badge 为空串时不渲染。
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
          .borderRadius(9)
          .padding({ left: 2, right: 2, top: 2, bottom: 2 })
          .constraintSize({ minWidth: 14, minHeight: 14 })
          .textAlign(TextAlign.Center)
          // Flutter Positioned(right:-6, top:-4)：相对 24 图标边。本 Stack 含
          // 4 内边距（图标位于 4..28），换算为 margin right -2 / top 0。
          .margin({ right: -2 });
      }
    }
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
      .onFocus((): void => { this.focusedKey = key; })
      .onBlur((): void => { this.focusedKey = ''; })
      .onClick((): void => {
        if (enabled) {
          onTap();
        }
      });
  }
}
