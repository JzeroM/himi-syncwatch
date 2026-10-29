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
import { MpvXComponentController, MpvSurfaceCallbacks } from '../plugin/HimiMpvSurface';

const TAG = 'HimiNativePlayerView';
const DOMAIN = 0x0001;

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
        // ── 顶部条 ──
        Row() {
          Text('‹')
            .fontSize(30)
            .fontColor(Color.White)
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .backgroundColor('#66000000')
            .borderRadius(20)
            .onClick((): void => {
              this.onBack();
            });
          Text(this.state().title.length > 0 ? this.state().title : this.state().mediaTitle)
            .fontSize(16)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: 8 });
          Text(this.currentTime)
            .fontSize(14)
            .fontColor('#CCFFFFFF')
            .margin({ right: 12 });
          // 选集（有集数据才显示）
          if (this.state().episodes.length > 0) {
            Text('选集')
              .fontSize(13)
              .fontColor(this.activePanel === NativePlayerPanelType.episode ? '#4C8DFF' : '#CCFFFFFF')
              .padding({ left: 8, right: 8 })
              .onClick((): void => {
                this.openPanel(NativePlayerPanelType.episode);
              });
          }
          // 线路（有多版本才显示）
          if (this.state().versions.length > 1) {
            Text('线路')
              .fontSize(13)
              .fontColor(this.activePanel === NativePlayerPanelType.version ? '#4C8DFF' : '#CCFFFFFF')
              .padding({ left: 8, right: 8 })
              .onClick((): void => {
                this.openPanel(NativePlayerPanelType.version);
              });
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .linearGradient({
          angle: 180,
          colors: [['#99000000', 0.0], ['#00000000', 1.0]],
        });

        // ── 底部条 ──
        Column() {
          // 诊断行（Phase 1 验收关键字段）
          Text(nativeDiagSummary(this.state()))
            .fontSize(10)
            .fontColor('#99FFFFFF')
            .maxLines(2)
            .width('100%');

          Row() {
            Text(formatTime(this.dragging ? this.dragMs : this.progressMs))
              .fontSize(13)
              .fontColor(Color.White)
              .width(58)
              .textAlign(TextAlign.Start);
            Slider({
              value: this.dragging ? this.dragMs : this.progressMs,
              min: 0,
              max: this.state().durationMs > 0 ? this.state().durationMs : 1,
              step: 1000,
            })
              .layoutWeight(1)
              .selectedColor('#FF4C8DFF')
              .trackColor('#33FFFFFF')
              .onChange((value: number, mode: SliderChangeMode): void => {
                this.pokeAutoHide();
                if (mode === SliderChangeMode.Begin ||
                  mode === SliderChangeMode.Moving) {
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
              .fontSize(13)
              .fontColor(Color.White)
              .width(58)
              .textAlign(TextAlign.End);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row() {
            // 播放/暂停
            Text(this.state().paused ? '▶' : '⏸')
              .fontSize(24)
              .fontColor(Color.White)
              .padding(8)
              .onClick((): void => {
                this.onTogglePlay();
              });
            // 倍速（Phase 2：点开面板）
            Text(`${this.state().speed}x`)
              .fontSize(14)
              .fontColor(this.activePanel === NativePlayerPanelType.speed ? '#4C8DFF' : '#CCFFFFFF')
              .padding({ left: 10, right: 10 })
              .onClick((): void => {
                this.openPanel(NativePlayerPanelType.speed);
              });
            // 音轨
            Text('音轨')
              .fontSize(13)
              .fontColor(this.activePanel === NativePlayerPanelType.audio ? '#4C8DFF' : '#CCFFFFFF')
              .padding({ left: 8, right: 8 })
              .onClick((): void => {
                this.openPanel(NativePlayerPanelType.audio);
              });
            // 字幕
            Text('字幕')
              .fontSize(13)
              .fontColor(this.activePanel === NativePlayerPanelType.subtitle ? '#4C8DFF' : '#CCFFFFFF')
              .padding({ left: 8, right: 8 })
              .onClick((): void => {
                this.openPanel(NativePlayerPanelType.subtitle);
              });
            Blank();
            if (this.state().hdrOutput) {
              Text('HDR')
                .fontSize(12)
                .fontColor('#FFFFC84C')
                .padding(4)
                .backgroundColor('#33FFC84C')
                .borderRadius(4);
            }
            Text(this.state().buffering ? '缓冲中' : '')
              .fontSize(12)
              .fontColor('#CCFFFFFF')
              .margin({ left: 8 });
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 14 })
        .linearGradient({
          angle: 0,
          colors: [['#99000000', 0.0], ['#00000000', 1.0]],
        })
        .position({ x: 0, y: '100%' })
        .markAnchor({ x: '0%', y: '100%' });
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
}
