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
import { window } from '@kit.ArkUI';
import settings from '@ohos.settings';
import {
  HimiMpvNativeHost,
  NativePlayerUiState,
  NativePlayerViewListener,
  NativePlayerPanelType,
  NativeResourceGroupUi,
  NativeSeasonGroupUi,
  NativeResourceItemUi,
  nativeDiagSummary,
} from './HimiMpvNativeHost';
import { NativePlayerPanel, segmentMarkReject } from './NativePlayerPanel';
import { NativePlayerIcons } from './NativePlayerIcons';
import { DanmakuLayer } from './DanmakuLayer';
import { GlassSlider } from './GlassSlider';
import { MpvXComponentController, MpvSurfaceCallbacks } from '../plugin/HimiMpvSurface';

const TAG = 'HimiNativePlayerView';

/**
 * 房间资源面板宽度（vp，590）。
 *
 * 与 Flutter `_buildResponsiveLayout` 横屏分栏 `SizedBox(width: 320)` 逐值一致。
 * 展开时视频区同步收窄该宽度（否则面板盖住视频）。
 */
const ROOM_PANEL_WIDTH = 320;

/**
 * 房间资源面板高度（594，竖屏上下结构）。
 *
 * 与 Flutter `_buildResponsiveLayout` 竖屏分支 `SizedBox(height: 280)`
 * 逐值一致。竖屏时面板贴视频区下缘、占满宽度。
 */
const ROOM_PANEL_HEIGHT = 280;

/** 面板分隔线（与 NativePlayerPanel.PANEL_DIVIDER 同值，白 12%）。 */
const ROOM_PANEL_DIVIDER = '#1FFFFFFF';

/** 手势方向判定阈值（vp；对齐 Android ViewConfiguration 默认 8dp 量级）。 */
const PAN_SLOP = 8;
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

/**
 * 进度行（左时间 + 玻璃滑杆 + 右时间）——**自驱刷新**子组件。
 *
 * 【拖动触摸一致性根因】旧实现进度/时间写进控件层 epoch 签名（播放中每
 * 秒变、拖动中每帧变）→ 签名一变销毁重建整棵控件子树（含滑杆）→ 触摸
 * 序列被打断、手指与拇指脱节（真机回归：拖动进度条触摸位置不一致）。
 * 本组件自带 100ms timer 写 @State（DanmakuLayer/DisplayValueText 同款
 * 已验证机制）：进度/时间自己走秒，拖动全程组件不重建。
 */
@Component
struct ProgressRow {
  @Prop durationMs: number = 0;
  /** TV 长按进度条标记片头/片尾（false = 不启用，对齐 Flutter）。 */
  segmentMarkEnabled: boolean = false;
  /** 抬手 seek（绝对毫秒）。 */
  onSeek: (v: number) => void = (v: number): void => {};
  /** 交互延后自动隐藏。 */
  onInteract: () => void = (): void => {};
  /** TV 长按 → 片头片尾标记卡。 */
  onSegmentMark: () => void = (): void => {};

  /** 当前位置（100ms 自驱；拖动中冻结，显示拖动值）。 */
  @State posMs: number = 0;
  @State dragging: boolean = false;
  @State dragMs: number = 0;
  private timer: number = -1;

  aboutToAppear(): void {
    this.posMs = HimiMpvNativeHost.getInstance().positionNowMs();
    this.timer = setInterval((): void => {
      if (!this.dragging) {
        this.posMs = HimiMpvNativeHost.getInstance().positionNowMs();
      }
    }, 100);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Row() {
      Text(formatTime(this.dragging ? this.dragMs : this.posMs))
        .fontSize(12)
        .fontColor('#B3FFFFFF')
        .width(this.durationMs >= 3600000 ? 78 : 56)
        .textAlign(TextAlign.End);
      GlassSlider({
        value: this.dragging ? this.dragMs : this.posMs,
        min: 0,
        max: this.durationMs > 0 ? this.durationMs : 1,
        step: 1000,
        onChange: (v: number): void => {
          this.onInteract();
          this.dragging = true;
          this.dragMs = v;
        },
        onCommit: (v: number): void => {
          this.onInteract();
          this.dragging = false;
          this.dragMs = v;
          this.posMs = v;
          this.onSeek(v);
        },
      })
        .layoutWeight(1);
      Text(formatTime(this.durationMs))
        .fontSize(12)
        .fontColor('#B3FFFFFF')
        .width(this.durationMs >= 3600000 ? 78 : 56)
        .textAlign(TextAlign.Start);
    }
    // TV + 片头片尾功能开启时，长按进度条 → 标记卡（对齐 Flutter）。
    .gesture(this.segmentMarkEnabled
      ? LongPressGesture().onAction((): void => {
        this.onInteract();
        this.onSegmentMark();
      })
      : undefined)
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }
}

/**
 * @Builder 按引用传递载体（真机回归：控件状态不实时变的终极根因）。
 *
 * ArkUI 官方语义：@Builder **按值传递**（number/string/boolean）时，状态
 * 变化不会刷新 @Builder 内部 UI；**按引用传递（对象）**才会刷新——对象
 * 属性绑定 @State，属性变化触发 @Builder 重新执行。锁控件之所以"看起来
 * 正常"，是因为它走的是 build() 条件**值翻转**的分支销毁重建，不是
 * @Builder 刷新。
 *
 * 用法：顶层 @Builder 签名收 `$$: ControlsRef`，调用点传对象字面量
 * `{ rev: this.renderTick }`（rev 每 250ms + 每次状态推送必变）。
 */
class ControlsRef {
  rev: number = 0;
}

@Component
export struct HimiNativePlayerView {
  @State revision: number = 0;
  /**
   * 渲染触发计数——**必须在 build() 条件表达式里直读**。
   *
   * 根因（真机回归：点播放/暂停等所有控件状态不立刻变，隐藏再现才变）：
   * ArkUI 细粒度刷新只跟踪 **build() 体**里的直读依赖，@Builder 体内与
   * 方法调用里的读取不触发重绘。镜像值（paused 等）都对，但父组件从不
   * 重绘 → 屏幕停在旧帧；showControls 是 build() 直读的，所以隐藏/再现
   * 必然重跑 build()、新状态一次性生效。renderTick 直读进条件后：
   * 状态推送（onStateChanged）与 tick 兜底（250ms）都 bump 它 → 全树
   * 重绘，与「隐藏再现」同机制、但即时发生。
   */
  @State renderTick: number = 0;
  /**
   * 控件重建纪元——**@Builder 子树唯一认的刷新：节点重建**。
   *
   * 五轮真机实验证明（567~571 全败、隐藏再现恒生效）：@Builder 子树只在
   * 节点销毁重建（if 条件值翻转 / ForEach key 变化）时拿新值，任何数据级
   * 传递（镜像 @State / 表达式内联 / 按值参数 / 按引用参数）都不刷新。
   * 修法：动态值签名变化 → epoch 自增 → build() 里 ForEach 的 key 变化 →
   * 旧节点销毁重建（与"隐藏再现"同一机制，由状态变化即时触发）。
   */
  @State controlsEpoch: number = 0;
  /** 上次重建时的动态值签名（防无谓重建：静止时零开销）。 */
  private controlsSig: string = '';
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

  /**
   * 宿主动态字段的 @State 镜像（与 `locked` 同一已验证模式）。
   *
   * 宿主 `state().X` 是普通字段，**不在 ArkUI 观察链上**——只靠 revision
   * 间接触发重建不可靠（真机回归：点播放/暂停图标不实时变，要等控件
   * 隐藏再现才更新）。所有驱动图标/文案的动态字段必须显式镜像到
   * @State 并在 syncFromHost() 同步。tvMode/isRoom/logoUrl 会话内不变，
   * 不镜像。
   */
  @State paused: boolean = true;
  @State danmakuEnabled: boolean = false;
  @State speed: number = 1.0;
  @State videoFit: string = 'contain';
  @State canControl: boolean = true;
  @State engineLabel: string = '';
  @State displayTitle: string = '';
  @State networkSpeedText: string = '';
  @State durationMs: number = 0;
  @State currentEpisodeIndex: number = -1;
  @State episodeCount: number = 0;
  @State versionCount: number = 0;
  @State subtitleStreamCount: number = 0;
  @State audioStreamCount: number = 0;
  @State clockFormat: string = '24h';
  @State segmentEnabled: boolean = false;
  /**
   * 加载指示器可见位（589，**必须 @State**）。
   *
   * 【真机回归：正常播放还一直转圈】`build()` 里旧写法是
   * `if (this.state().showLoading)`——`this.state()` 是宿主的**普通对象**，
   * 不在 ArkUI 观察链上；而该 if 节点既不在 `ForEach([controlsEpoch])`
   * 重建块里，也没有直读任何 @State → ArkUI 细粒度更新不会把它纳入更新
   * 集合 → 条件只在创建时求值一次，起播前算出的 `true` 永久保留。
   *
   * 修法：显式镜像到 @State 并在 build() 直读（条件翻转即销毁/重建节点）。
   */
  @State showLoading: boolean = false;
  /** 跳过片头/片尾提示（'' = 隐藏，'intro' / 'outro'；Dart 推送驱动）。 */
  @State skipPrompt: string = '';
  /** Logo 地址（'' = 不显示；房间模式无 logo）。稳定层直读，不进重建块。 */
  @State logoUrl: string = '';

  /** 顶栏宽度 / 尾组内容宽（onAreaChange 喂入，转屏自适应收窄间距）。 */
  @State topRowW: number = 0;
  @State topTailW: number = 0;
  /** 顶栏尾组间距（8→4→2→0 逐级收窄，全部控件保持可见）。 */
  @State topGap: number = 8;
  /** 底栏 trailing 槽实宽（权重槽 = (行宽-传输组)/2，onAreaChange 喂入）。 */
  @State trailingSlotW: number = 0;
  /**
   * 底栏右侧簇等比缩放比（1 = 不缩）。
   *
   * 对齐 Flutter `FittedBox(scaleDown)` / 安卓 ScaleDownBox：
   * `min(1, 可用宽 / 自然宽)`。缩放落在**真实布局参数**（字号/内边距/间距
   * 按比例缩小）而非 transform——transform 只改渲染不改占位，命中区要么
   * 跟着缩到点不中、要么与视觉错位（真机回归：竖屏底部控件点了没反应）。
   * 参数级缩放的命中区与视觉恒等。
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
  /** TopBar @Builder 执行计数（诊断探针用，见 topBarProbe）。 */
  private topBarProbeTick: number = 0;

  /**
   * 真机诊断探针：TopBar 每次 @Builder 执行自增，每 20 次打一条 hilog。
   * 按引用刷新生效时应约 5s 一条（250ms × 20）；若装机后无日志，说明
   * 该 SDK 的 @Builder 按引用刷新未生效 → 需改走子组件 + @Prop。
   * 返回 0，以无副作用属性位挂载（enabled 恒 true，不影响交互）。
   */
  private topBarProbe(): number {
    this.topBarProbeTick++;
    if (this.topBarProbeTick % 20 === 1) {
      hilog.debug(DOMAIN, TAG, 'TopBar @Builder 重执行 x%{public}d', this.topBarProbeTick);
    }
    return 0;
  }

  aboutToAppear(): void {
    const host = HimiMpvNativeHost.getInstance();
    this.listener = new ViewListener(this);
    host.registerListener(this.listener);
    this.controller.setCallbacks(new ViewSurfaceCallbacks());
    this.showControls = host.controlsVisible;
    this.progressMs = host.positionNowMs();
    this.dragMs = this.progressMs;
    this.currentTime = this.nowClock();
    this.syncFromHost();
    this.initBrightness();
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

  /**
   * 宿主状态 → @State 镜像（见镜像字段注释：宿主字段不在观察链上，
   * 显式复制是实时刷新的唯一可靠手段）。
   */
  private syncFromHost(): void {
    const host = HimiMpvNativeHost.getInstance();
    const s = host.state;
    this.locked = s.locked;
    this.paused = s.paused;
    this.danmakuEnabled = s.danmakuEnabled;
    this.speed = s.speed;
    this.videoFit = s.videoFit;
    this.canControl = s.canControl;
    this.engineLabel = s.engineLabel;
    this.displayTitle = s.displayTitle();
    this.networkSpeedText = s.networkSpeedText;
    this.durationMs = s.durationMs;
    this.currentEpisodeIndex = s.currentEpisodeIndex;
    this.episodeCount = s.episodes.length;
    this.versionCount = s.versions.length;
    this.subtitleStreamCount = s.subtitleStreamCount;
    this.audioStreamCount = s.audioStreamCount;
    this.clockFormat = s.clockFormat;
    this.segmentEnabled = s.segmentEnabled;
    // 加载指示器（589）：宿主字段不在观察链上，必须镜像到 @State，
    // build() 才能随状态推送/250ms tick 即时收起。
    this.showLoading = s.showLoading;
    // 跳过提示边沿处理（对齐 Flutter `_evaluateSkipPrompt`/`_dismissSkipPrompt`）：
    // 出现（''→非空）：强制显示控件 + 重置自动隐藏（胶囊所在底栏随之可见）；
    // 消失（非空→''）：重置计时，给用户完整 5 秒操作窗口。
    // 赋值前比对旧值天然防递归（syncFromHost 每 tick 都跑）。
    if (s.skipPrompt.length > 0 && this.skipPrompt.length === 0) {
      host.setControlsVisible(true);
      this.pokeAutoHide();
    } else if (s.skipPrompt.length === 0 && this.skipPrompt.length > 0) {
      this.pokeAutoHide();
    }
    this.skipPrompt = s.skipPrompt;
    this.logoUrl = s.isRoom ? '' : s.logoUrl;
  }

  /**
   * 动态值签名比对 → 控件重建纪元推进（见 controlsEpoch 注释）。
   * 覆盖全部驱动控件形态/文案的值；进度按秒量化（时间显示 1s 粒度）。
   */
  private refreshControlsEpoch(): void {
    // 【签名只收低频形态量】进度/拖动是高频量（播放中每秒、拖动中每帧变），
    // 进签名会反复销毁重建控件子树（含滑杆）→ 触摸序列被打断、手指与拇指
    // 脱节（真机回归）。进度行/数值文本由自驱子组件刷新，不靠重建。
    const sig = `${this.paused}|${this.danmakuEnabled}|${this.videoFit}|${this.speed}`
      + `|${this.canControl}|${this.engineLabel}|${this.displayTitle}|${this.networkSpeedText}`
      + `|${this.durationMs}|${this.currentEpisodeIndex}|${this.episodeCount}|${this.versionCount}`
      + `|${this.subtitleStreamCount}|${this.audioStreamCount}|${this.segmentEnabled}|${this.skipPrompt}`
      + `|${this.locked}|${this.activePanel}|${this.bottomScale}|${this.currentTime}`;
    if (sig === this.controlsSig) {
      return;
    }
    this.controlsSig = sig;
    this.controlsEpoch = this.controlsEpoch + 1;
  }

  /** 宿主状态推送回调（平台主线程 = UI 线程，可直接更新 @State）。 */
  onStateChanged(): void {
    const host = HimiMpvNativeHost.getInstance();
    this.showControls = host.controlsVisible;
    this.activePanel = host.activePanel !== null ? host.activePanel : '';
    this.syncFromHost();
    if (!this.dragging) {
      this.progressMs = host.positionNowMs();
      this.dragMs = this.progressMs;
    }
    // 显式赋值（不用 ++ 后缀自增，确保经过 @State setter 触发重建）。
    this.revision = this.revision + 1;
    // 渲染触发器：状态一到就全树重绘（见 renderTick 注释）。
    this.renderTick = this.renderTick + 1;
    // 推送即刻推进控件重建纪元（图标/形态即时切换）。
    this.refreshControlsEpoch();
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
      // 跳过片头/片尾提示有效期内保持控件可见（对齐 Flutter
      // `_onControlsIdleHide` 的 `_skipPromptSegment != null → reset`）：
      // 胶囊在底栏内，控件被带走胶囊就消失（真机回归）。顺延而非冻结——
      // 只跳过不重置 deadline 的话提示一消失会被立刻藏掉。
      if (host.state.skipPrompt.length > 0) {
        this.pokeAutoHide();
      } else {
        host.setControlsVisible(false);
        return;
      }
    }
    this.showControls = host.controlsVisible;
    // 兜底自愈：漏掉 notify 的更新路径最迟一个 tick 周期（250ms）纠正；
    // 缩放比同样自愈（集数/角标变化会改变簇自然宽）。
    this.syncFromHost();
    this.adjustBottomScale();
    this.renderTick = this.renderTick + 1;
    this.refreshControlsEpoch();
  }

  /**
   * 顶栏时钟文本：尊重 `clockFormat`（off/12h/24h）。
   *
   * 旧实现写死 24h 且**非房间模式恒显示**（Flutter 只在 TV 且格式非 off
   * 时显示），观感与 Flutter 不一致。文案照抄 `formatPlayerClock`：
   * 12h 档为 `上午 H:MM` / `下午 H:MM`（12 点补 12、去掉前导零）。
   */
  private nowClock(): string {
    const fmt = this.clockFormat;
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

  /**
   * 顶栏返回按钮：直发 requestBack 退出（对齐安卓 backButton →
   * `commandSink.send({type: requestBack})`）。
   *
   * 分层返回语义（先关面板 → 再隐控件 → 最后退出）只属于**系统返回键**
   * （handleBack，见 NativePlayer.ets onBackPress）。旧实现按钮也走分层：
   * 控件可见时点返回只把整套控件藏掉，表现为「返回点了没反应」（真机回归）。
   */
  private onBack(): void {
    HimiMpvNativeHost.getInstance().sendCommand('requestBack', null);
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

  /**
   * 手势方向锁（591）：0 = 未定，1 = 横向 seek，2 = 纵向亮度/音量。
   *
   * 旧实现每帧重判方向 → 斜向拖动来回切换，上滑时误触发 seek。
   */
  private dragAxis: number = 0;
  /** 纵拖起始点在左半屏（亮度）还是右半屏（音量）。 */
  private dragOnLeftSide: boolean = false;
  /**
   * 纵拖本地回显（0..1）。
   *
   * 【初值 = 系统当前亮度】与安卓一致（安卓取窗口 screenBrightness、无则
   * 跟随系统）：进页面读窗口亮度 → 窗口值（<0 = 未覆盖）则读系统亮度
   * （settings.SCREEN_BRIGHTNESS_STATUS/255）→ 兜底 0.8。旧实现写死 1.0
   * → 首次下滑从 100% 开始、与系统实际亮度不符（真机回归）。
   */
  private brightness01: number = 0.8;
  private volume01: number = 1.0;
  /** 拖动起点的亮度/音量（ArkUI offsetY 是相对起点的累计位移，
   *  必须以起点为基准换算，不能按增量累加）。 */
  private dragBaseBrightness: number = 1.0;
  private dragBaseVolume: number = 1.0;
  /** 提示自动隐藏定时器。 */
  private hintTimerId: number = -1;

  /**
   * 亮度初值 = 系统当前亮度（对齐安卓：窗口亮度未覆盖时跟随系统）。
   * 窗口已覆盖（setWindowBrightness 后 brightness>=0）优先用窗口值。
   */
  private initBrightness(): void {
    try {
      const win = window.findWindow('himi_native_player');
      const wVal = win.getWindowProperties().brightness;
      if (wVal !== undefined && wVal >= 0) {
        this.brightness01 = wVal;
        return;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'findWindow 亮度读取失败: %{public}s', String(e));
    }
    try {
      const raw = settings.getValueSync(getContext(this),
        settings.display.SCREEN_BRIGHTNESS_STATUS, '204');
      this.brightness01 = Math.max(0, Math.min(1, Number.parseFloat(raw) / 255));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '系统亮度读取失败（兜底 0.8）: %{public}s', String(e));
      this.brightness01 = 0.8;
    }
    hilog.info(DOMAIN, TAG, '亮度初值 %{public}s', `${this.brightness01}`);
  }

  /** 亮度写入窗口（同安卓 `window.attributes.screenBrightness` 语义）。 */
  private applyWindowBrightness(): void {
    try {
      window.findWindow('himi_native_player').setWindowBrightness(this.brightness01);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowBrightness 失败: %{public}s', String(e));
    }
  }

  /** 拖动开始：记录起始侧与起点亮度/音量。 */
  private onPanStart(event: GestureEvent): void {
    const s = this.state();
    if (s.locked || !s.canControl) {
      return;
    }
    this.hDragAccumPx = 0;
    this.dragAxis = 0;
    // 【必须 fingerList】Pan 的 offsetX 是累计位移（起点恒 0）→ 半屏判定
    // 永远判左屏、音量手势永远不触发（真机回归，同长按分区教训）。
    // localX 与手势层（全屏）同基准。
    const startX = event.fingerList.length > 0
      ? event.fingerList[0].localX
      : event.offsetX as number;
    this.dragOnLeftSide = startX < this.areaWidth / 2;
    this.dragBaseBrightness = this.brightness01;
    this.dragBaseVolume = this.volume01;
  }

  /**
   * 拖动中：横拖 seek / 纵拖亮度音量。
   *
   * 【方向锁（591）】旧实现每帧用 |dx|>|dy| 重判方向：斜向拖动会在横/纵
   * 之间来回切换 → 上滑时误触发 seek（真机回归「向上滑进度条会变」）。
   * 现在首次超阈值时**一次性定轴**（dragAxis），之后只走该轴分支。
   */
  private onPanUpdate(event: GestureEvent): void {
    const s = this.state();
    if (s.locked || !s.canControl) {
      return;
    }
    // ArkUI PanGesture 的 offsetX/offsetY 是**相对起点的累计位移**，
    // 与 Flutter 的 primaryDelta（增量）不同：这里直接以起点为基准换算。
    const totalDx = event.offsetX;
    const totalDy = event.offsetY;
    if (this.dragAxis === 0) {
      if (Math.abs(totalDx) <= PAN_SLOP && Math.abs(totalDy) <= PAN_SLOP) {
        return; // 位移未超阈值，方向未定
      }
      this.dragAxis = Math.abs(totalDx) > Math.abs(totalDy) ? 1 : 2;
    }
    if (this.dragAxis === 1) {
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
        // 亮度真正写窗口亮度（旧实现只改本地显示，拖了没效果）。
        this.applyWindowBrightness();
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
    // 591：只有锁定为横向才 seek（纵向手势不该改进度）。
    if (this.dragAxis !== 1 || Math.abs(this.hDragAccumPx) < 10) {
      this.dragAxis = 0;
      return;
    }
    const deltaMs = Math.round(this.hDragAccumPx / 100 * 5000);
    const clamped = Math.max(-60000, Math.min(60000, deltaMs));
    this.hDragAccumPx = 0;
    this.dragAxis = 0;
    if (clamped === 0) {
      return;
    }
    const target = Math.max(0, Math.min(s.durationMs, s.positionMs + clamped));
    HimiMpvNativeHost.getInstance().optimisticSeek(target);
    const seconds = Math.round(clamped / 1000);
    this.showGestureHint(`${seconds > 0 ? '+' : ''}${seconds}s`);
  }

  /**
   * 长按三分区（对齐 Flutter `_onVideoLongPressStart`）：
   * 左 1/3 设片头、右 1/3 设片尾、中间临时 2× 倍速；片头片尾功能未开
   * （或 TV/锁定/面板打开）时全区退化为倍速。
   */
  private onLongPressZone(event: GestureEvent): void {
    // 【必须 fingerList】GestureEvent.offsetX 是 Pan 的**累计位移**语义，
    // 长按不动位移恒为 0 → 恒判左区（真机回归：长按右边也设片头）。
    // SDK 明确 fingerList "Used in LongPressGesture"，localX 与手势层
    // （全屏）同基准，可直接与 areaWidth 比较分区。
    const x = event.fingerList.length > 0
      ? event.fingerList[0].localX
      : event.offsetX as number;
    hilog.debug(DOMAIN, TAG,
      'longPress x=%{public}s/%{public}s segEnabled=%{public}s',
      `${Math.round(x)}`, `${Math.round(this.areaWidth)}`, `${this.segmentGestureEnabled()}`);
    if (this.segmentGestureEnabled()) {
      if (x < this.areaWidth / 3) {
        this.markSegmentFromGesture('intro');
        return;
      }
      if (x > this.areaWidth * 2 / 3) {
        this.markSegmentFromGesture('outro');
        return;
      }
    }
    this.onSpeedBoostStart();
  }

  /** 长按标记片头/片尾启用条件（对齐 Flutter `_segmentMarkGestureEnabled`）。 */
  private segmentGestureEnabled(): boolean {
    return !this.state().tvMode && this.segmentEnabled && !this.locked
      && this.activePanel.length === 0 && this.canControl
      && this.verticalBarPercent < 0;
  }

  /**
   * 长按标记片头/片尾（对齐 Flutter `_onSegmentMarkSelected` + `_markSegmentAt`）：
   * 校验（0 秒 / 片头 3 秒门槛 `introGateMs` / 结尾）→ 无旧标记直接标记并
   * 提示「已设置…」；有旧标记直开二次确认卡（更新/清除/取消）。
   */
  private markSegmentFromGesture(kind: string): void {
    const host = HimiMpvNativeHost.getInstance();
    const pos = host.positionNowMs();
    const existing = kind === 'intro'
      ? this.state().segmentIntroEndMs
      : this.state().segmentOutroStartMs;
    if (pos <= 0) {
      this.showGestureHint('当前位置为 0，无法标记', 1500);
      return;
    }
    if (kind === 'intro' && pos < 3000) {
      this.showGestureHint('播放 3 秒后才能设置片头', 1500);
      return;
    }
    if (this.durationMs > 0 && pos >= this.durationMs) {
      this.showGestureHint('当前位置已到结尾，无法标记', 1500);
      return;
    }
    // 范围约束（588）：片头 ≤10%、片尾 ≥70%（与 Dart SegmentMarkRules 一致）。
    const reject = segmentMarkReject(kind, pos, this.durationMs);
    if (reject !== null) {
      this.showGestureHint(reject, 1500);
      return;
    }
    if (existing !== null) {
      // 已有旧标记：直开二次确认（Flutter dialog 在原生双窗不可见）。
      host.openSegmentConfirm(kind);
      return;
    }
    host.optimisticSetSegmentMark(kind);
    this.showGestureHint(
      `已设置${kind === 'intro' ? '片头结束点' : '片尾开始点'} ${formatTime(pos)}`, 1500);
  }

  /** 长按临时倍速：激活升到 2×（松手还原）。 */
  private onSpeedBoostStart(): void {
    const s = this.state();
    if (s.locked || !s.canControl || this.speedBoostActive) {
      return;
    }
    this.speedBoostActive = true;
    this.boostBaseSpeed = s.speed;
    HimiMpvNativeHost.getInstance().optimisticSetSpeed(this.boostBaseSpeed * 2.0);
    // 提示本体见 build() 的倍速胶囊（对齐 Flutter `_buildSpeedBoostChip`）。
    // 旧实现误用 gestureHint 图标态（48px 图标字体渲染文字）→ 巨大
    // 「播放中」（真机截图回归）。
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
    const fit: string = this.videoFit;
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

  /** Logo 显示条件已内联为 `this.logoUrl.length > 0`（@State 直读，可刷新）。 */

  /** 时间数显列宽：时长 ≥1h 用 HH:MM:SS 档（78），否则 MM:SS 档（56）。
   *  【渲染直读】UI 里直接写 `this.durationMs >= 3600000 ? 78 : 56`，
   *  不得包进方法（方法体读取不进依赖集，列宽不刷新）。 */

  /** 是否有上一集。 */
  private hasPrev(): boolean {
    return this.currentEpisodeIndex > 0;
  }

  /** 是否有下一集。 */
  private hasNext(): boolean {
    return this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex + 1 < this.episodeCount;
  }

  /** 多集判断在 UI 里直写 `this.episodeCount > 1`（见渲染直读注释）。 */

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
   * 右侧簇自然宽（**解析式**，不实测）：可见项每块 32dp（24 图标 +
   * 4×2 内边距）、间距 20dp，TV 倍速芯片含文字按 64dp 估。
   *
   * 【禁止实测自然宽】簇渲染在权重槽内会被槽宽夹住：父槽只给 96vp 时
   * 实测也只有 96 → scale 恒为 1、永不缩小（真机回归：竖屏挤+出屏）。
   */
  private trailingNaturalWidth(): number {
    let blocks = 1; // 弹幕
    if (!this.state().isRoom && this.versionCount > 1) {
      blocks++;
    }
    if (this.state().tvMode) {
      blocks++; // 显示调节
    }
    blocks += 2; // 字幕 + 音轨
    if (!this.state().isRoom && this.episodeCount > 1) {
      blocks++;
    }
    const speedChip = this.state().tvMode && !this.state().isRoom;
    const widths = blocks * 32 + (speedChip ? 64 : 0);
    const gaps = (blocks - 1 + (speedChip ? 1 : 0)) * 20;
    return widths + gaps;
  }

  /** 底栏右侧簇等比缩放（对齐 Flutter `FittedBox(scaleDown)` / 安卓 ScaleDownBox）。 */
  private adjustBottomScale(): void {
    const avail = this.trailingSlotW;
    const natural = this.trailingNaturalWidth();
    if (natural <= 0 || avail <= 0) {
      this.bottomScale = 1;
      return;
    }
    const raw = natural > avail ? avail / natural : 1;
    // 死区 0.03 + 量化 0.05 档：取整微抖不来回重排；量化取下整恒不溢出。
    if (Math.abs(raw - this.bottomScale) < 0.03) {
      return;
    }
    this.bottomScale = Math.max(0.3, Math.min(1, Math.floor(raw * 20) / 20));
    hilog.debug(DOMAIN, TAG,
      'bottomScale natural=%{public}d avail=%{public}d -> %{public}s',
      natural, avail, `${this.bottomScale}`);
  }

  /** 上一集（经面板命令回传 Dart）。 */
  private onPrevEpisode(): void {
    const host = HimiMpvNativeHost.getInstance();
    if (!this.hasPrev()) {
      return;
    }
    host.optimisticSelectEpisode(this.currentEpisodeIndex - 1);
  }

  /** 下一集。 */
  private onNextEpisode(): void {
    const host = HimiMpvNativeHost.getInstance();
    if (!this.hasNext()) {
      return;
    }
    host.optimisticSelectEpisode(this.currentEpisodeIndex + 1);
  }

  /** 宿主单例（资源面板交互用）。 */
  private host(): HimiMpvNativeHost {
    return HimiMpvNativeHost.getInstance();
  }

  /** 房间资源面板是否可见（房间模式 + 面板展开）。 */
  private roomPanelVisible(): boolean {
    const s = this.state();
    return s.isRoom && s.resourcePanelOpen;
  }

  /**
   * 房间资源面板（592，逐项复刻 Flutter `_buildResourcePanel`）。
   *
   * 原生 UI 是全屏子窗口，会盖住 Flutter 的资源面板。结构对齐 Flutter：
   * `#1A1A2E` 底 + 头部（资源/搜索/人数胶囊/角色徽章）+ 分组列表
   * （组 → 季 → 集）+ 播报板 120vp。
   *
   * 图标一律走 `NativePlayerIcons` 字体（与 Flutter Material Icons 同源），
   * 不用 emoji/文本符号。
   */
  @Builder
  RoomPanel() {
    Column() {
      // ── 头部：Expanded(资源) | 搜索 | 人数胶囊 | 角色徽章 ──
      Row({ space: 6 }) {
        Text('资源')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        // 搜索：房主 **且未在播放** 才显示（Flutter
        // `_roomData != null && _isHost && state != playing`）。
        // 596：房主 **且暂停中** 才显示（Flutter
        // `_roomData != null && _isHost && state != playing`）。
        // 595 写成 `!paused`（播放中显示），逻辑反了。
        if (this.state().isHost && this.state().paused) {
          Text(String.fromCodePoint(NativePlayerIcons.ICON_SEARCH))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(20)
            .fontColor('#B3FFFFFF')
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .onClick((): void => {
              this.host().sendCommand('openResourceSearch', null);
            });
        }
        // 人数胶囊：people 图标 12 + 数字 11（底 white12 圆角 8）。
        Row({ space: 3 }) {
          Text(String.fromCodePoint(NativePlayerIcons.ICON_PEOPLE))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(12)
            .fontColor('#B3FFFFFF')
            .width(12)
            .height(12)
            .textAlign(TextAlign.Center);
          Text(`${this.state().onlineUserCount}`)
            .fontSize(11)
            .fontColor('#B3FFFFFF');
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor('#1FFFFFFF')
        .borderRadius(8)
        .alignItems(VerticalAlign.Center);
        // 角色徽章：房主 accent / 观众红。
        Text(this.state().isHost
          ? '房主'
          : (this.state().audienceName.length > 0 ? this.state().audienceName : '观众'))
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.state().isHost ? SEL_COLOR : '#E53935')
          .borderRadius(8);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 0.5 }, color: ROOM_PANEL_DIVIDER });

      // ── 分组列表（padding vertical 4，对齐 Flutter ListView）──
      List() {
        ForEach(this.state().resourceGroups, (g: NativeResourceGroupUi, gi: number) => {
          // 组标题（chevron + 组名 + 计数）
          ListItem() {
            Row() {
              Text(String.fromCodePoint(g.collapsed
                ? NativePlayerIcons.ICON_CHEVRON_RIGHT
                : NativePlayerIcons.ICON_EXPAND_MORE))
                .fontFamily(NativePlayerIcons.FONT_FAMILY)
                .fontSize(20)
                .fontColor('#B3FFFFFF')
                .width(20);
              Text(g.name)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ left: 4 });
              Text(g.countLabel())
                .fontSize(12)
                .fontColor('#8AFFFFFF');
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor('#16213E')
            .onClick((): void => {
              const fields: Map<string, Object> = new Map<string, Object>();
              fields.set('index', gi);
              this.host().sendCommand('toggleResourceGroup', fields);
            });
          }
          // 展开内容：电影直接列集；剧集按季分组
          if (!g.collapsed) {
            if (g.isMovie) {
              ForEach(g.seasons.length > 0 ? g.seasons[0].episodes : [],
                (ep: NativeResourceItemUi, ei: number) => {
                  ListItem() {
                    this.RoomEpisodeRow(ep);
                  }
                }, (ep: NativeResourceItemUi, ei: number): string => `mv-${gi}-${ei}-${ep.index}`);
            } else {
              ForEach(g.seasons, (season: NativeSeasonGroupUi, si: number) => {
                // 季标题（chevron + 第N季 + (N集)）
                ListItem() {
                  Row() {
                    Text(String.fromCodePoint(season.collapsed
                      ? NativePlayerIcons.ICON_CHEVRON_RIGHT
                      : NativePlayerIcons.ICON_EXPAND_MORE))
                      .fontFamily(NativePlayerIcons.FONT_FAMILY)
                      .fontSize(16)
                      .fontColor('#8AFFFFFF')
                      .width(16);
                    Text(`第${season.seasonNumber}季`)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#B3FFFFFF')
                      .layoutWeight(1)
                      .margin({ left: 4 });
                    Text(`(${season.episodes.length}集)`)
                      .fontSize(11)
                      .fontColor('#62FFFFFF');
                  }
                  .width('100%')
                  .padding({ left: 24, right: 12, top: 6, bottom: 6 })
                  .alignItems(VerticalAlign.Center)
                  .backgroundColor('#1A1A2E')
                  .onClick((): void => {
                    const fields: Map<string, Object> = new Map<string, Object>();
                    fields.set('groupIndex', gi);
                    fields.set('seasonIndex', si);
                    this.host().sendCommand('toggleResourceSeason', fields);
                  });
                }
                if (!season.collapsed) {
                  ForEach(season.episodes, (ep: NativeResourceItemUi, ei: number) => {
                    ListItem() {
                      this.RoomEpisodeRow(ep);
                    }
                  }, (ep: NativeResourceItemUi, ei: number): string => `ep-${gi}-${si}-${ei}-${ep.index}`);
                }
              }, (season: NativeSeasonGroupUi, si: number): string => `sn-${gi}-${si}-${season.collapsed}`);
            }
          }
        }, (g: NativeResourceGroupUi, gi: number): string => `rg-${gi}-${g.collapsed}`);
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 4, bottom: 4 });

      // ── 播报板 120vp（campaign 图标 + 播报 (N) + 列表）──
      Column() {
        Row({ space: 4 }) {
          Text(String.fromCodePoint(NativePlayerIcons.ICON_CAMPAIGN))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(12)
            .fontColor('#B3FFFFFF')
            .width(12)
            .height(12)
            .textAlign(TextAlign.Center);
          Text(`播报 (${this.state().broadcasts.length})`)
            .fontSize(11)
            .fontColor('#B3FFFFFF');
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .alignItems(VerticalAlign.Center);

        List() {
          ForEach(this.state().broadcasts, (line: string, bi: number) => {
            ListItem() {
              Text(line)
                .fontSize(11)
                .fontColor('#8AFFFFFF')
                .width('100%')
                .padding({ left: 10, right: 10, top: 2, bottom: 2 });
            }
          }, (line: string, bi: number): string => `bc-${bi}-${line}`);
          // 空态居中（对齐 Flutter `暂无消息`）。
          if (this.state().broadcasts.length === 0) {
            ListItem() {
              Text('暂无消息')
                .fontSize(11)
                .fontColor('#3DFFFFFF')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 8, bottom: 8 });
            }
          }
        }
        .width('100%')
        .layoutWeight(1);
      }
      .width('100%')
      .height(120)
      .border({ width: { top: 0.5 }, color: ROOM_PANEL_DIVIDER });
    }
    .width(this.portrait ? '100%' : ROOM_PANEL_WIDTH)
    .height(this.portrait ? ROOM_PANEL_HEIGHT : '100%')
    .backgroundColor('#1A1A2E')
    .alignItems(HorizontalAlign.Start);
  }

  /**
   * 单条资源行（逐项复刻 Flutter `_buildEpisodeListItem`）。
   *
   * `[左 3vp accent 边] 播放/暂停(房主) 缩略图56×36 集信息 删除(房主)`
   */
  @Builder
  RoomEpisodeRow(ep: NativeResourceItemUi) {
    Row() {
      // 当前集左 3vp accent 竖条（Flutter Border(left, 3)）。
      // 596：当前集左边框改为容器 border（不占布局宽）。
      // 旧实现用独立 `Column().width(3)` 占位——视觉上「多一条竖条」且把
      // 右侧内容右推。这里删掉占位，改在行容器上画左 3vp 边框（见行尾
      // `.border({ width: { left: 3 }, color: SEL_COLOR })`）。
      // 播放/暂停（房主）
      if (this.state().isHost) {
        Text(String.fromCodePoint(
          ep.isPlaying && !this.state().paused
            ? NativePlayerIcons.ICON_PAUSE_CIRCLE
            : NativePlayerIcons.ICON_PLAY_CIRCLE))
          .fontFamily(NativePlayerIcons.FONT_FAMILY)
          .fontSize(22)
          .fontColor(ep.isPlaying ? SEL_COLOR : '#8AFFFFFF')
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .margin({ right: 8 });
      }
      // 缩略图 56×36（圆角 4；无图时灰底 + movie 图标）
      Stack({ alignContent: Alignment.Center }) {
        if (ep.poster.length > 0) {
          Image(ep.poster)
            .width(56)
            .height(36)
            .objectFit(ImageFit.Cover)
            .borderRadius(4);
        } else {
          Column()
            .width(56)
            .height(36)
            .backgroundColor('#424242')
            .borderRadius(4);
          Text(String.fromCodePoint(NativePlayerIcons.ICON_MOVIE))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(16)
            .fontColor('#9E9E9E');
        }
      }
      .width(56)
      .height(36)
      .margin({ right: 8 });

      // 集信息
      Column() {
        if (ep.isMovie()) {
          Text(ep.name)
            .fontSize(12)
            .fontColor(ep.isPlaying ? Color.White : '#8AFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
        } else {
          Text(ep.episodeCode())
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(ep.isPlaying ? SEL_COLOR : '#B3FFFFFF')
            .width('100%');
          Text(ep.name)
            .fontSize(12)
            .fontColor(ep.isPlaying ? Color.White : '#8AFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      // 删除（房主）
      if (this.state().isHost) {
        Text(String.fromCodePoint(NativePlayerIcons.ICON_CLOSE))
          .fontFamily(NativePlayerIcons.FONT_FAMILY)
          .fontSize(18)
          .fontColor('#3DFFFFFF')
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            const fields: Map<string, Object> = new Map<string, Object>();
            fields.set('index', ep.index);
            this.host().sendCommand('removeResourceEpisode', fields);
          });
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(ep.isPlaying ? '#4D6366F1' : Color.Transparent)
    // 596：当前集左 3vp accent 边框（Flutter Border(left, 3)，不占布局宽）。
    .border(ep.isPlaying
      ? { width: { left: 3 }, color: SEL_COLOR }
      : { width: 0, color: Color.Transparent })
    .onClick((): void => {
      if (!this.state().isHost) {
        return;
      }
      if (ep.isPlaying) {
        this.host().optimisticTogglePaused();
      } else {
        this.host().optimisticSelectEpisode(ep.index);
      }
    });
  }

  /**
   * 视频层 + 手势层（593/594 分栏复用）。
   *
   * 抽成 @Builder 是因为横屏 `Row` 与竖屏 `Column` 两个分支都要同一份
   * 视频内容——ArkTS 不能动态换容器类型，只能各写一份并共用本 @Builder。
   */
  @Builder
  VideoStack() {
      // ── 视频层 ──
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.controller,
      })
        // 尺寸由外层分栏容器决定（见 build 顶部）：房间面板展开时视频区
        // 收窄（593/594），横屏收窄宽度、竖屏收窄高度。
        //
        // 【坑】`layoutWeight(1)` 与 `width/height('100%')` 同时设置时后者
        // 优先，layoutWeight 失效 → 视频不收窄、面板盖在上面（真机回归）。
        // 因此必须二选一：展开用 layoutWeight（吃掉剩余空间），收起用 100%。
        .width(this.roomPanelVisible() ? 'auto' : '100%')
        .height(this.roomPanelVisible() ? 'auto' : '100%')
        .layoutWeight(this.roomPanelVisible() ? 1 : 0)
        .backgroundColor(Color.Black)
        // 【兜底：尺寸同步】XComponent 的 onSurfaceChanged 在部分转屏场景
        // 不触发（子窗口尺寸变化但 surface 未重建），导致 mpv 仍按旧尺寸
        // 合成 → 竖屏画面被拉长铺满。这里用 onAreaChange 补一次同步：
        // 宿主的 surfaceChanged 有「尺寸未变则跳过」的幂等保护，重复调用无害。
        //
        // 【单位陷阱（586 真机「画面变糊」根因）】Area.width/height 的单位是
        // **vp**，而 mpv 的 `ohos-surface-size` 只接受 **px**。旧实现直接把
        // vp 当 px 传给 surfaceChanged：真机 1260×2720px（density≈3.06）
        // 被写成 411×914 → mpv 在 1/3 分辨率的小画布上合成，再由合成器
        // 放大铺满全屏。宽高比一致故**不变形，只变糊**。
        // onAreaChange 在 onSurfaceChanged 之后触发，等于把正确值反复覆盖
        // 成错误值 —— 不是偶发，是稳定复现。必须经 vp2px 换算。
        .onAreaChange((_old: Area, area: Area): void => {
          const wVp = area.width as number;
          const hVp = area.height as number;
          if (wVp <= 0 || hVp <= 0) {
            return;
          }
          const wPx = Math.trunc(this.getUIContext().vp2px(wVp));
          const hPx = Math.trunc(this.getUIContext().vp2px(hVp));
          if (wPx <= 0 || hPx <= 0) {
            return;
          }
          hilog.info(DOMAIN, TAG,
            'area: %{public}dvp x %{public}dvp -> %{public}dpx x %{public}dpx',
            wVp, hVp, wPx, hPx);
          HimiMpvNativeHost.getInstance().surfaceChanged('', wPx, hPx);
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
            // 长按三分区：左 1/3 设片头、右 1/3 设片尾、中间临时倍速
            // （对齐 Flutter `_onVideoLongPressStart`；功能未开时全区退化为倍速）。
            LongPressGesture({ repeat: false })
              .onAction((event: GestureEvent): void => {
                this.onLongPressZone(event);
              })
              .onActionEnd((): void => {
                this.onSpeedBoostEnd();
              })
              .onActionCancel((): void => {
                this.onSpeedBoostEnd();
              }),
          ),
        )
      // ── 手势层（视频之上）──
      Column()
        .width('100%')
        .height('100%')
        .gesture(
          GestureGroup(GestureMode.Parallel,
            TapGesture({ count: 1 }).onAction((): void => {
              this.onTapLayer();
            }),
            TapGesture({ count: 2 }).onAction((): void => {
              this.onDoubleTapGesture();
            }),
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
            LongPressGesture({ repeat: false })
              .onAction((event: GestureEvent): void => {
                this.onLongPressZone(event);
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

  }

  /** 房间资源面板槽（593/594）：横屏右侧 320vp / 竖屏底部 280vp。 */
  @Builder
  RoomPanelSlot() {
    Column() {
      this.RoomPanel();
    }
    .width(this.portrait ? '100%' : ROOM_PANEL_WIDTH)
    .height(this.portrait ? ROOM_PANEL_HEIGHT : '100%');
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // ── 视频 + 房间资源面板：Row 分栏（590）──
      // 【必须流式布局】鸿蒙禁止 position/markAnchor 百分比定位（真机跑位
      // 回归，见 test/native_player_theme_test.dart）：尾组曾用
      // `.position({x:'100%',y:'50%'})`，百分比基准是父容器、Stack 高度不定
      // → 控件跑到屏幕中部/屏外。
      //
      // 【594 竖屏上下结构】用 Flex + direction 动态切换：
      // - 横屏（`Row`）：视频左、面板右 320vp（Flutter
      //   `Row(Expanded(video), SizedBox(320))`）；
      // - 竖屏（`Column`）：视频上、面板下 280vp（Flutter
      //   `Column(Expanded(video), SizedBox(280))`）。
      // ArkTS 不能在 build() 里动态换容器类型，Flex 的 direction 是
      // 唯一可行手段。
      // ── 视频 + 房间资源面板分栏（593/594）──
      // 【必须流式布局】鸿蒙禁止 position/markAnchor 百分比定位（真机跑位
      // 回归，见 test/native_player_theme_test.dart）：尾组曾用
      // `.position({x:'100%',y:'50%'})`，百分比基准是父容器、Stack 高度不定
      // → 控件跑到屏幕中部/屏外。
      //
      // 【594 竖屏上下结构】用 if/else 双分支（Row / Column 各写一份）。
      // 不用 `Flex({direction})`：ArkTS 对三元表达式推断方向枚举会报
      // `arkts-no-any-unknown`（CI 实测），显式分支最稳。
      // - 横屏 Row：视频左、面板右 320vp（Flutter
      //   `Row(Expanded(video), SizedBox(320))`）；
      // - 竖屏 Column：视频上、面板下 280vp（Flutter
      //   `Column(Expanded(video), SizedBox(280))`）。
      if (this.roomPanelVisible() && this.portrait) {
        Column() {
          this.VideoStack();
          this.RoomPanelSlot();
        }
        .width('100%')
        .height('100%');
      } else {
        Row() {
          this.VideoStack();
          if (this.roomPanelVisible()) {
            this.RoomPanelSlot();
          }
        }
        .width('100%')
        .height('100%');
      }

      // ── 加载指示器（586）：居中转圈，在控件层**之下**（对齐 Flutter
      //    `_buildVideoArea` 的 `CircularProgressIndicator`——转圈期间顶栏/
      //    底栏仍可点返回）。显示时机由快照的 `showLoading` 统一决定
      //    （首帧未出 **或** 缓冲中），安卓读同一位。
      //
      //    旧实现**完全没有**加载指示器：鸿蒙起播那几秒是纯黑，什么都不转。
      //
      //    【589 必须读 @State】旧写法 `this.state().showLoading` 是宿主普通
      //    字段（不在 ArkUI 观察链上），该 if 节点也不在 epoch 重建块里 →
      //    条件只求值一次，起播前的 true 永久保留（真机「播放中一直转圈」）。
      if (this.showLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color('#6366F1');
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        // 转圈不抢手势（点屏仍可显隐控件）。用 None 而非 Transparent：
        // Transparent 会让本层与下层**同时**进入手势竞技场，全屏层会抢走
        // 触摸流（565 真机回归的老坑）；None 表示本层及子节点完全不参与命中。
        .hitTestBehavior(HitTestMode.None);
      }

      // ── 弹幕层：视频之上、控件之下（原生渲染，Flutter 弹幕层随视频区
      //    退场 → 弹幕开关在原生 UI 下必须由本层生效）──
      DanmakuLayer({ revision: this.revision });

      // `this.renderTick >= 0` 恒真——作用是把渲染触发器**直读进 build()
      // 体**：ArkUI 只对 build() 直读依赖触发重绘，@Builder 体内的镜像
      // 读取不触发（真机回归：控件状态不立刻变）。见 renderTick 注释。
      //
      // 【按引用传递 = @Builder 刷新触发器】ArkUI @Builder 按值传递（number）
      // 不随状态刷新（570 rev:number 失败的根因）；按引用传递对象时，对象
      // 属性绑定的 @State 变化会触发 @Builder 重新执行 → 整条链一次性刷新。
      // renderTick 每 250ms + 每次状态推送必变 → 控件层持续刷新。
      if (this.showControls && this.renderTick >= 0) {
        // 【节点重建 = @Builder 子树唯一认的刷新】ForEach key 变化 → 旧节点
        // 销毁、新节点创建 → TopBar/LockOnlyBar 重新执行 → 图标/角标全部取
        // 最新值（与"隐藏再现"同一机制，由 controlsEpoch 即时触发）。
        ForEach([this.controlsEpoch], (epoch: number): void => {
          if (this.locked && !this.state().tvMode) {
            // ── 锁定态：仅左下锁钮（与进度条左数显同列）──
            this.LockOnlyBar({ rev: this.renderTick });
          } else {
            this.TopBar({ rev: this.renderTick });
          }
        }, (epoch: number): string => `ctl-${epoch}`);

        if (!this.locked || this.state().tvMode) {
          // ── 底栏壳（稳定层，不随 epoch 重建）──
          // 显隐条件与旧逻辑一致：仅「锁定 + 手机」走 LockOnlyBar、不出底栏；
          // 锁定 + TV 仍显示底栏（锁钮在 ControlRow 里）。
          // logo 进重建块会随每秒重建反复销毁/重载图片 → 闪烁（真机回归）；
          // 渐变/定位/空点击吸收同样保持稳定。动态内容（进度行 + 控件行）
          // 在壳内的独立 ForEach 里按 epoch 重建取新值。
          Column() {
            if (this.logoUrl.length > 0) {
              Image(this.logoUrl)
                .width(240)
                .height(44)
                .objectFit(ImageFit.Contain)
                .margin({ bottom: 4 });
            }
            ForEach([this.controlsEpoch], (epoch: number): void => {
              this.BottomBar({ rev: this.renderTick });
            }, (epoch: number): string => `bb-${epoch}`);
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
          .linearGradient({
            angle: 180,
            colors: [['#00000000', 0.0], ['#D9000000', 1.0]],
          })
          // 【空点击吸收】点条形背景被吸收、不穿透到底层手势层。
          .onClick((): void => {
          })
          .position({ x: 0, y: '100%' })
          .markAnchor({ x: '0%', y: '100%' })
          // 【真机回归：竖屏没有进度条和底栏】597 修正。
          //
          // `position y:'100%'` 贴的是**根 Stack 底缘**（全屏高）。竖屏
          // 分栏后资源面板占底部 280vp → 底栏整个落在面板下方、被完全
          // 盖住（用户看到「竖屏没有进度条和底栏」）。
          //
          // 用 `translate` 上移面板高度（vp 数值，非百分比定位，不触发
          // 真机跑位），底栏底缘正好落在视频区底缘。
          .translate({
            y: (this.roomPanelVisible() && this.portrait) ? -ROOM_PANEL_HEIGHT : 0,
          });
        }
      }

      // ── 手势提示与亮度/音量柱条（视频之上、控件之下）──
      // 对齐 Flutter `_buildGestureHint` / `_buildVerticalBar` 的层级。
      if (this.gestureHint.length > 0) {
        // 【全屏居中容器】align 对齐属性在根 Stack 子节点上不生效（真机：
        // 提示词/提示图标跑到顶栏居中）——用显式全屏 Column + justify/align
        // 居中，提示词与提示图标都落屏幕正中（对齐 Flutter _buildGestureHint）。
        Column() {
          Text(this.gestureHint)
            .fontFamily(this.gestureHintIsIcon ? NativePlayerIcons.FONT_FAMILY : '')
            .fontSize(this.gestureHintIsIcon ? 48 : 16)
            .fontWeight(this.gestureHintIsIcon ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(this.gestureHintIsIcon ? '#B3FFFFFF' : Color.White)
            .padding(this.gestureHintIsIcon ? 0 : {
              left: 16, right: 16, top: 8, bottom: 8,
            })
            .backgroundColor(this.gestureHintIsIcon ? Color.Transparent : '#8C000000')
            .borderRadius(this.gestureHintIsIcon ? 0 : 16);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None);
      }

      // ── 长按临时倍速提示：画面中央玻璃小胶囊（对齐 Flutter
      //    `_buildSpeedBoostChip`：fast_forward 18 + 「2.0× 播放中」14/w600，
      //    圆角 16、内边距 h16 v8）。旧实现误用 gestureHint 图标态
      //    （48px 图标字体渲染文字）→ 巨大「播放中」（真机截图回归）。
      if (this.speedBoostActive) {
        Column() {
          Row() {
            // 码位取单一来源常量（禁手改数字）：旧硬编码错误码位渲染成
            // 「4G」字形（真机回归），必须走 native_icons.json 的 fastForward。
            Text(String.fromCodePoint(NativePlayerIcons.ICON_FAST_FORWARD))
              .fontFamily(NativePlayerIcons.FONT_FAMILY)
              .fontSize(18)
              .fontColor(Color.White);
            Text(`${(2.0).toFixed(1)}× 播放中`)
              .fontSize(14)
              .fontWeight(600)
              .fontColor(Color.White)
              .margin({ left: 6 });
          }
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#8C000000')
          .borderRadius(16);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None);
      }

      if (this.verticalBarPercent >= 0) {
        // 侧别对齐安卓 paintVerticalBar（Flutter 注释与实现相反、以实现
        // 为准）：**亮度柱在右、音量柱在左**。用全屏容器定位（align 属性
        // 在根 Stack 子节点不生效，同手势提示的教训）。
        Column() {
          Text(`${this.verticalBarPercent}%`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(48)
            .height(160)
            .textAlign(TextAlign.Center)
            .backgroundColor('#8C000000')
            .borderRadius(16);
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(this.verticalBarOnLeft ? HorizontalAlign.End : HorizontalAlign.Start)
        .padding({ left: this.verticalBarOnLeft ? 0 : 16, right: this.verticalBarOnLeft ? 16 : 0 })
        .hitTestBehavior(HitTestMode.None);
      }

      // ── 二级面板（Phase 2）：遮住视频，点外/返回关闭 ──
      if (this.activePanel.length > 0) {
        NativePlayerPanel({
          panelType: this.activePanel,
          revision: this.revision,
          // 597：竖屏房间模式把面板/遮罩收窄到视频区（否则伸到资源面板）。
          bottomInset: (this.roomPanelVisible() && this.portrait) ? ROOM_PANEL_HEIGHT : 0,
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
  LockOnlyBar($$: ControlsRef) {
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
        .width(this.durationMs >= 3600000 ? 78 : 56)
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
    // 597：竖屏分栏时上移面板高度，让锁钮落在视频区底缘（不再被资源
    // 面板盖住 → 真机「锁定态切资源后锁控件消失」的鸿蒙同源问题）。
    .translate({
      y: (this.roomPanelVisible() && this.portrait) ? -ROOM_PANEL_HEIGHT : 0,
    })
    // 【空点击吸收】点背景不穿透到底层手势层（与顶/底栏一致）。
    .onClick((): void => {
    });
  }

  /** 顶栏：返回 / 标题 / 网速 | 内核胶囊（+倍速）| 时钟（TV）。 */
  @Builder
  TopBar($$: ControlsRef) {
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
        Text(this.displayTitle)
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
        if (this.networkSpeedText.length > 0) {
          Text(this.networkSpeedText)
            .fontSize(12)
            .fontColor('#B3FFFFFF');
        }
        if (!this.state().tvMode && !this.state().isRoom) {
          this.Chip(this.speedGlyph(), `${this.trimSpeed(this.speed)}x`, 20, true,
            this.activePanel === NativePlayerPanelType.speed, 'topSpeed', (): void => {
              this.openPanel(NativePlayerPanelType.speed);
            }, 1);
        }
        this.Chip('', this.engineLabel, 0, false,
          this.activePanel === NativePlayerPanelType.kernel, 'kernel', (): void => {
            this.openPanel(NativePlayerPanelType.kernel);
          }, 1);
        if (!this.state().tvMode) {
          this.IconChip(this.subtitleStyleGlyph(), 18, 6, true,
            this.activePanel === NativePlayerPanelType.display, 'topDisplay', (): void => {
              this.openPanel(NativePlayerPanelType.display);
            }, 1);
          // 解码：Erika 无解码档位 → 隐藏（对齐 Flutter）。
          if (this.engineLabel !== 'Erika') {
            this.IconChip(this.decodeGlyph(), 18, 6, true,
              this.activePanel === NativePlayerPanelType.decode, 'decode', (): void => {
                this.openPanel(NativePlayerPanelType.decode);
              }, 1);
          }
          // 画面比例：Erika 缩放不可用、房间不显示（对齐 Flutter）。
          if (!this.state().isRoom && this.engineLabel !== 'Erika') {
            this.IconChip(this.videoFitGlyph(), 22, 6, false,
              false, 'videoFit', (): void => {
                this.pokeAutoHide();
                HimiMpvNativeHost.getInstance().optimisticCycleVideoFit();
              }, 1);
          }
          this.IconChip(this.rotateGlyph(), 22, 6, false,
            false, 'rotate', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleOrientation();
            }, 1);
        }
        // 分享（仅房间模式；对齐 Flutter showShare）。
        // 时钟（仅 TV 且格式非 off；对齐 Flutter PlayerClockLayer：
        // `if (!tvMode || !format.enabled) return shrink`）。
        if (this.state().isRoom) {
          this.IconChip(String.fromCodePoint(NativePlayerIcons.ICON_SHARE), 22, 6, false,
            false, 'share', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().shareRoom();
            }, 1);
        } else if (this.state().tvMode && this.clockFormat !== 'off') {
          Text(this.currentTime)
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
      // 顶栏宽后到也要重算（只在尾簇 onAreaChange 里算会拿到 0 的顶栏宽，
      // 一次之后就不再更新——与底栏缩放同类的陈旧测量问题）。
      this.adjustTopGap();
    })
    // 【空点击吸收】对齐 Flutter `_buildTopBar` 外层 GestureDetector：
    // 点条形背景被吸收、**不穿透**到底层手势层（否则一点背景就隐藏控件）。
    // 按钮自身的 onClick 优先，空 onClick 只兜住背景区域。
    .onClick((): void => {
    })
    .linearGradient({
      angle: 180,
      colors: [['#CC000000', 0.0], ['#00000000', 1.0]],
    })
    // 【真机诊断探针】@Builder 每次重执行都会求值本表达式（enabled 恒
    // true 无副作用），日志验证按引用刷新是否生效（见 topBarProbe）。
    .enabled(this.topBarProbe() >= 0);
  }

  /** 底栏：Logo / 进度条 / 播放组（手机居中·TV 置左）/ 右侧图标组。 */
  @Builder
  BottomBar($$: ControlsRef) {
    Column() {
      // logo 移至 build() 的底栏壳（稳定层）：进 epoch 重建块会随每秒重建
      // 反复销毁/重载图片 → 闪烁（真机回归）。
      // 进度行自驱（ProgressRow）：不再进 epoch 签名——旧实现播放中每秒、
      // 拖动中每帧重建整棵控件子树（含滑杆）→ 触摸序列被打断、手指与拇指
      // 脱节（真机回归）。
      ProgressRow({
        durationMs: this.durationMs,
        segmentMarkEnabled: this.state().tvMode && this.segmentEnabled,
        onSeek: (v: number): void => {
          HimiMpvNativeHost.getInstance().optimisticSeek(Math.round(v));
        },
        onInteract: (): void => {
          this.pokeAutoHide();
        },
        onSegmentMark: (): void => {
          this.pokeAutoHide();
          HimiMpvNativeHost.getInstance().togglePanel(NativePlayerPanelType.segment);
        },
      });

      this.ControlRow();

      // ── 诊断行（586）：对齐安卓 `NativePlayerScreenView.diagText`。
      //    仅 `showDebug`（设置页「同步调试」）为真时显示，薄文本整行宽。
      //    关键字段 `canvas=` 是 mpv 实际合成画布尺寸（px）——真机「画面
      //    变糊」就是它被写成了 1/3 尺寸，一眼可核验。
      if (this.state().showDebug) {
        Text(this.diagLine())
          .fontSize(10)
          .fontColor('#99FFFFFF')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 });
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  /**
   * 底部诊断行文本（对齐安卓 buildDiag 的字段顺序）。
   *
   * `canvas=` 取宿主亲自收到的画布尺寸（px），不是 Dart 上报值——这是
   * 验证「mpv 画布 = 屏幕物理像素」的唯一可靠口径。
   */
  private diagLine(): string {
    const s = this.state();
    const host = HimiMpvNativeHost.getInstance();
    const vo = s.currentVo.length > 0 ? s.currentVo : (s.voConfigured.length > 0 ? s.voConfigured : '-');
    const hw = s.hwdecCurrent.length > 0 ? s.hwdecCurrent : '-';
    const canvas = `${host.canvasWidth}x${host.canvasHeight}`;
    const video = s.debugLines.length > 0 ? ` | ${s.debugLines[0]}` : '';
    return `vo=${vo} | hwdec=${hw} | surface=${s.surfaceAttached ? 'att' : '未附着'} | canvas=${canvas}${video}`;
  }

  /**
   * 控件行：`leading 槽(权重 1, 贴左) | 传输组 | trailing 槽(权重 1, 贴右)`。
   *
   * 结构等价 Flutter `PlayerBottomRow(centered: true)` / 安卓 buttonRow——
   * 两个等宽权重槽让传输组**精确居中**，trailing 槽可用宽 =
   * `(行宽-传输组)/2`，槽内簇按需等比缩小（adjustBottomScale）。
   *
   * 【不得叠全宽兄弟容器】旧结构是 Stack{ 传输组 | 全宽右侧簇 | 全宽锁钮行 }：
   * 锁钮行/右侧簇铺满整行、盖在传输组上面，触摸全被上层容器吞掉 →
   * 「底部控件点了没反应」（真机回归）。三槽 Row 平铺，无遮挡层。
   */
  @Builder
  ControlRow() {
    Row() {
      // leading 槽（权重 1，贴左）：手机锁钮 / TV 锁定态锁钮，与进度条时间
      // 数显同轴（同列宽）；无锁钮时空占位保传输组精确居中。
      Row() {
        if (!this.state().tvMode && !this.state().isRoom) {
          Text(String.fromCodePoint(this.locked
            ? NativePlayerIcons.ICON_LOCK
            : NativePlayerIcons.ICON_LOCK_OPEN))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(22)
            .fontColor('#B3FFFFFF')
            .width(this.durationMs >= 3600000 ? 78 : 56)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick((): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleLock();
            });
        } else if (this.locked && this.state().tvMode) {
          Text(String.fromCodePoint(NativePlayerIcons.ICON_LOCK))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(22)
            .fontColor('#B3FFFFFF')
            .onClick((): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleLock();
            });
        }
        // 跳过片头/片尾胶囊（对齐安卓底栏 leading 槽设计：锁钮旁玻璃胶囊，
        // 圆角 14 / padding h12 v8 / 图标 20 + 6 + 13px w600；片头=skip_next、
        // 片尾=skip_previous，与 Flutter `isIntro ? skip_next : skip_previous`
        // 一致）。显隐由 Dart `_skipPromptSegment` 推送驱动（含 8 秒自动消失、
        // 章节/手动标记解析），点击回传 `skipSegment` 由 Dart 执行跳转语义。
        if (this.skipPrompt.length > 0 && this.segmentEnabled) {
          Row() {
            Text(String.fromCodePoint(this.skipPrompt === 'intro' ? 0xE5BD : 0xE5BE))
              .fontFamily(NativePlayerIcons.FONT_FAMILY)
              .fontSize(20)
              .fontColor(Color.White);
            Text(this.skipPrompt === 'intro' ? '跳过片头' : '跳过片尾')
              .fontSize(13)
              .fontWeight(600)
              .fontColor(Color.White)
              .margin({ left: 6 });
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#8C000000')
          .borderRadius(14)
          // 防撑行：胶囊在权重槽内不得把整行撑出屏幕（真机竖屏回归）。
          .constraintSize({ maxWidth: 132 })
          .margin({ left: 8 })
          .onClick((): void => {
            this.pokeAutoHide();
            HimiMpvNativeHost.getInstance().sendCommand('skipSegment', null);
          });
        }
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start);

      // 传输组：项间距 8（Flutter SizedBox(8)），单集/电影 prev/next 空占位 28。
      // 不设 width：保持内容宽度，由两侧等宽权重槽保证精确居中。
      // 【条件内联直读】if/参数里的方法调用隐藏状态依赖（不刷新）。
      Row({ space: 8 }) {
        if (this.episodeCount > 1) {
          this.TransportGlyph(this.prevGlyph(), 28, this.currentEpisodeIndex > 0, 'prev', (): void => {
            this.pokeAutoHide();
            this.onPrevEpisode();
          });
        } else {
          // 单集/电影：空占位保持播放键居中（与 Flutter SizedBox(28) 一致）。
          Row().width(28).height(28);
        }
        // 【必须内联直读 this.paused】图标选择不能藏进方法调用——方法体
        // 内的读取不进 ArkUI 细粒度依赖集，播放/暂停图标不会实时切换
        //（真机回归：点播放/暂停形态不变，隐藏再现才更新）。
        this.TransportGlyph(this.paused ? this.playGlyph() : this.pauseGlyph(), 36,
          this.canControl, 'play', (): void => {
            this.onTogglePlay();
          });
        if (this.episodeCount > 1) {
          this.TransportGlyph(this.nextGlyph(), 28,
            this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex + 1 < this.episodeCount,
            'next', (): void => {
              this.pokeAutoHide();
              this.onNextEpisode();
            });
        } else {
          Row().width(28).height(28);
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center);

      // 【右侧簇自适应】对齐 Flutter `FittedBox(scaleDown, alignment:
      // centerRight)` / 安卓 ScaleDownBox：可用宽不足时等比缩小（字号/
      // 内边距/间距全部按 bottomScale 收缩，真实布局级缩放，命中区与视觉
      // 恒等），簇贴右。旧方案「逐级收窄间距 20→8→4→0」不可行：竖屏可用
      // 宽 ~96dp，4 个图标在 gap=0 时仍需 128dp → 仍溢出 32dp（真机截图回归）。
      Row() {
        Row({ space: 20 * this.bottomScale }) {
          this.IconChip(this.danmakuEnabled
            ? String.fromCodePoint(0xE17E)
            : String.fromCodePoint(0xF04D2), 24, 4, false,
            this.danmakuEnabled, 'danmaku', (): void => {
              this.pokeAutoHide();
              HimiMpvNativeHost.getInstance().optimisticToggleDanmaku();
            }, this.bottomScale);
          if (!this.state().isRoom && this.versionCount > 1) {
            this.BadgeIconChip(this.versionGlyph(), `${this.versionCount}`,
              this.activePanel === NativePlayerPanelType.version, 'version', (): void => {
                this.openPanel(NativePlayerPanelType.version);
              }, this.bottomScale);
          }
          if (this.state().tvMode) {
            this.IconChip(this.subtitleStyleGlyph(), 24, 4, false,
              this.activePanel === NativePlayerPanelType.display, 'tvDisplay', (): void => {
                this.openPanel(NativePlayerPanelType.display);
              }, this.bottomScale);
          }
          this.BadgeIconChip(this.subtitleGlyph(),
            this.subtitleStreamCount > 0 ? `${this.subtitleStreamCount}` : '',
            this.activePanel === NativePlayerPanelType.subtitle, 'subtitle', (): void => {
              this.openPanel(NativePlayerPanelType.subtitle);
            }, this.bottomScale);
          this.BadgeIconChip(this.audioGlyph(),
            this.audioStreamCount > 0 ? `${this.audioStreamCount}` : '',
            this.activePanel === NativePlayerPanelType.audio, 'audio', (): void => {
              this.openPanel(NativePlayerPanelType.audio);
            }, this.bottomScale);
          if (!this.state().isRoom && this.episodeCount > 1) {
            this.BadgeIconChip(this.playlistGlyph(), `${this.episodeCount}`,
              this.activePanel === NativePlayerPanelType.episode, 'episode', (): void => {
                this.openPanel(NativePlayerPanelType.episode);
              }, this.bottomScale);
          }
          if (this.state().tvMode && !this.state().isRoom) {
            this.Chip(this.speedGlyph(), `${this.trimSpeed(this.speed)}x`, 24, true,
              this.activePanel === NativePlayerPanelType.speed, 'bottomSpeed', (): void => {
                this.openPanel(NativePlayerPanelType.speed);
              }, this.bottomScale);
          }
        }
        .alignItems(VerticalAlign.Center);
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.End)
      .onAreaChange((_old: Area, area: Area): void => {
        // 权重槽实宽即右侧簇可用宽（(行宽-传输组)/2）。
        this.trailingSlotW = area.width as number;
        this.adjustBottomScale();
      });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  /** 文字胶囊（倍速/内核/TV 倍速）；s = 等比缩放比（底栏竖屏自适应，顶栏恒 1）。 */
  @Builder
  Chip(icon: string, label: string, iconSize: number, plain: boolean, active: boolean, key: string,
    onTap: () => void, s: number) {
    Row() {
      if (icon.length > 0) {
        Text(icon)
          .fontFamily(NativePlayerIcons.FONT_FAMILY)
          .fontSize(iconSize * s)
          .fontColor(active ? SEL_COLOR : Color.White);
      }
      if (label.length > 0) {
        Text(label)
          .fontSize(12 * s)
          .fontWeight(FontWeight.Medium)
          .fontColor(active ? SEL_COLOR : (plain ? '#B3FFFFFF' : Color.White))
          .margin({ left: 4 * s });
      }
    }
    // 倍速为纯图标+文字（Flutter 无底，padding 4）；内核为玻璃胶囊
    //（Flutter _decodeChipDecoration：白 22%→10% 渐变 + 白 24% 描边）。
    // 缩放态下内边距按比例收缩（真实布局级缩放，与字号同步）。
    .padding(s >= 1
      ? (plain ? PAD_PLAIN : PAD_CHIP)
      : (plain
        ? { left: 4 * s, right: 4 * s, top: 4 * s, bottom: 4 * s }
        : { left: 9 * s, right: 9 * s, top: 6 * s, bottom: 6 * s }))
    .linearGradient(plain ? CHIP_GRAD_CLEAR : CHIP_GRAD)
    .borderRadius(10)
    // TV 焦点环优先（3px #C1C2FE），否则常规芯片描边（打开态强调色）。
    .border(this.focusedKey === key
      ? BORDER_FOCUS
      : (active ? BORDER_ACTIVE : (plain ? BORDER_NONE : BORDER_CHIP)))
    // TV 遥控器可达：可聚焦（非 TV 设备 focusable 不影响触摸）。
    .focusable(true)
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
    onTap: () => void, s: number) {
    Text(icon)
      .fontFamily(NativePlayerIcons.FONT_FAMILY)
      .fontSize(iconSize * s)
      .fontColor(active ? SEL_COLOR : Color.White)
      .padding(pad * s)
      .linearGradient(glass ? CHIP_GRAD : CHIP_GRAD_CLEAR)
      .borderRadius(10)
      .border(this.focusedKey === key
        ? BORDER_FOCUS
        : (glass ? (active ? BORDER_ACTIVE : BORDER_CHIP) : BORDER_NONE))
      .focusable(true)
      .stateStyles({ pressed: pressedFeedback })
      .onFocus((): void => { this.focusedKey = key; })
      .onBlur((): void => { this.focusedKey = ''; })
      // 【热区补偿】缩放态热区会跟着缩小到难命中（见 hitRegion）。
      .responseRegion(this.hitRegion(iconSize, pad, s))
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
  BadgeIconChip(icon: string, badge: string, active: boolean, key: string, onTap: () => void,
    s: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.IconChip(icon, 24, 4, false, active, key, onTap, s);
      if (badge.length > 0) {
        Text(badge)
          .fontSize(9 * s)
          .fontColor(Color.White)
          .backgroundColor(SEL_COLOR)
          .width(this.badgeSide(badge) * s)
          .height(this.badgeSide(badge) * s)
          .borderRadius(this.badgeSide(badge) * s / 2)
          .textAlign(TextAlign.Center)
          .align(Alignment.Center)
          // Flutter Positioned(right:-6, top:-4)：相对 24 图标边。本 Stack 含
          // 4 内边距（图标位于 4..28），换算为 margin right -2 / top 0。
          .margin({ right: -2 * s });
      }
    }
  }

  /**
   * 角标正圆边长（vp，三端统一）：1~2 位 15、3 位 19、4 位起 24。
   *
   * 与 Flutter `NativePlayerTheme.badgeSizeFor` / 安卓 `badgeDiameterDp`
   * 逐值一致（旧实现按位数 14/18，与另两端大小不一）。
   */
  private badgeSide(badge: string): number {
    if (badge.length >= 4) {
      return 24;
    }
    if (badge.length === 3) {
      return 19;
    }
    return 15;
  }

  /**
   * 缩放态热区补偿（对齐安卓 ScaleDownBox 的 HIT_SLOP 语义）。
   *
   * 竖屏缩到 0.5 档时 24 图标只剩 ~16dp 热区，很难点中（真机「点了没
   * 反应」）。横向各扩到相邻间距的一半（gap 20×s 的一半 = 10×s，不与
   * 邻居重叠）、纵向扩 6×s。s=1 保持默认热区（扩大会与顶栏邻接芯片
   * 互相误触）。
   */
  private hitRegion(iconSize: number, pad: number, s: number): Rectangle[] {
    if (s >= 1) {
      return [{ x: 0, y: 0, width: '100%', height: '100%' }];
    }
    return [{
      x: -10 * s,
      y: -6 * s,
      width: iconSize + 2 * pad + 20 * s,
      height: iconSize * 1.35 + 2 * pad + 12 * s,
    }];
  }

  /** 传输组按钮（上一集/播放/下一集）。 */
  @Builder
  TransportGlyph(icon: string, size: number, enabled: boolean, key: string, onTap: () => void) {
    Text(icon)
      .fontFamily(NativePlayerIcons.FONT_FAMILY)
      .fontSize(size)
      .fontColor(enabled ? Color.White : '#3DFFFFFF')
      .padding(4)
      // 【不设 focusOnTouch】触摸获焦会画系统焦点框——真机「点击控件
      // 带选择框」（真机回归）。TV 遥控器导航仍可获焦显示焦点环。
      .focusable(enabled)
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
