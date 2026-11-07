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
  /** 622：是否可控制播放（房间观众 false → 拖进度不生效并回弹）。 */
  canControl: boolean = true;

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
        // 【600 双保险】时长未知时 max 不能是 1——旧兜底会让任何非零
        // value 都算出 ratio=1（进度条顶到最右）。改用「至少覆盖当前
        // 位置」的兜底，保证 value <= max 恒成立。
        max: this.durationMs > 0
          ? this.durationMs
          : Math.max(this.dragging ? this.dragMs : this.posMs, 1),
        step: 1000,
        onChange: (v: number): void => {
          this.onInteract();
          this.dragging = true;
          this.dragMs = v;
        },
        onCommit: (v: number): void => {
          this.onInteract();
          this.dragging = false;
          // 622：房间观众不得拖进度（回弹到当前权威位置）。
          if (!this.canControl) {
            this.dragMs = this.posMs;
            return;
          }
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

  /**
   * 是否有可播放内容（607，**必须 @State**）。
   *
   * 【真机回归：删除正在播放的资源后画面停在最后一帧】Flutter 侧删除当前
   * 集时置 `_isPlayerReady = false` → 视频区走占位分支（`▶ + 请从资源面板
   * 选择要播放的内容`）。原生侧此前**完全没有**占位 UI，删除后停在最后
   * 一帧（看起来像「没删掉」）。
   */
  @State playerReady: boolean = true;
  /** 跳过片头/片尾提示（'' = 隐藏，'intro' / 'outro'；Dart 推送驱动）。 */
  @State skipPrompt: string = '';
  /** Logo 地址（'' = 不显示；房间模式无 logo）。稳定层直读，不进重建块。 */
  @State logoUrl: string = '';

  /**
   * 控件层（顶栏 + 底栏）可用宽高（600，**必须 @State**）。
   *
   * 【真机回归：房间模式控件是全屏的】资源面板展开时视频区已收窄
   * （`VideoStack` 的 layoutWeight），但控件层挂在根 Stack 上、宽高都是
   * `'100%'`（全屏）→ 顶栏/底栏横跨整屏、压在资源面板上。
   *
   * 对齐安卓 `applyVideoSplit` 的语义：
   * - **横屏分栏**：只收宽度（视频区底就是屏幕底）→
   *   `controlsW = 屏宽 - ROOM_PANEL_WIDTH`，`controlsH = 0`（用 100% 高）；
   * - **竖屏分栏**：只收高度（视频区宽就是屏幕宽）→
   *   `controlsW = 0`（用 100% 宽），`controlsH = 屏高 - ROOM_PANEL_HEIGHT`；
   * - **未分栏**：两者 0 → 回落 `'100%'`，行为与分栏前完全一致。
   */
  @State controlsW: number = 0;
  @State controlsH: number = 0;

  /**
   * 视频区宽高（602，**必须 @State**）。
   *
   * 【真机回归：横竖屏切换短暂黑屏】`VideoStack()` 原本在 `if (portrait) {
   * Column{VideoStack} } else { Row{VideoStack} }` 两个分支里各调用一次——
   * ArkUI 的 if/else 条件翻转会**整体销毁旧分支、创建新分支**，里面的
   * `XComponent` 随之销毁重建（onSurfaceDestroyed → 解绑 → 黑一帧 →
   * onSurfaceCreated → 重绑 → 画面回来）。
   *
   * 修法：视频层提到分支**之外**、只在根 Stack 里存在一份实例，方向切换
   * 只移动资源面板、不动视频。尺寸改用显式值（0 = '100%'）：
   * - 横屏分栏：`videoW = 屏宽 - ROOM_PANEL_WIDTH`，`videoH = 0`；
   * - 竖屏分栏：`videoW = 0`，`videoH = 屏高 - ROOM_PANEL_HEIGHT`；
   * - 未分栏：两者 0 → 铺满。
   */
  @State videoW: number = 0;
  @State videoH: number = 0;

  /**
   * 视频区**实测**宽高（vp）——625。
   *
   * 与 `videoW`/`videoH`（分栏收窄的**显式**值）不同：这里是 Flex 实际
   * 分配给视频子节点的尺寸（未分栏时 = 全屏）。用于按视频比例算
   * XComponent 的 letterbox 尺寸。
   */
  @State videoAreaW: number = 0;
  @State videoAreaH: number = 0;

  /**
   * XComponent 实测尺寸（vp）——`onAreaChange` 缓存，供 tick 兜底同步。
   *
   * 【623 真机回归：鸿蒙房间面板初始展开时画布拉伸】`XComponent` 的
   * `onAreaChange` 在「面板初始就展开」场景可能**早于 Flex 布局完成**
   * （拿到全屏尺寸）→ mpv 按全屏画布合成 → 画面被拉伸铺满。
   * 「隐藏再显示面板」时尺寸二次变化、onAreaChange 正确触发 → 正常。
   *
   * 修法：缓存实测值，`tick()` 每 250ms 纠一次（`handleSurfaceChanged`
   * 内部有 `prevW !== width` 幂等保护，重复调用无副作用）。
   */
  private xcWidth: number = 0;
  private xcHeight: number = 0;

  /**
   * 资源行播放/暂停图标重建纪元（600，**必须 @State**）。
   *
   * 【真机回归：资源列表前的播放/暂停图标状态不变化】`RoomEpisodeRow` 读
   * `state().paused` 是宿主普通字段（不在 ArkUI 观察链上），而 `RoomPanel`
   * 又不在任何 `ForEach` 重建块里 → 暂停/恢复时面板节点不重建 → 图标停在
   * 建列表那一刻的值。
   *
   * 只在 `paused | currentEpisodeIndex` 变化时自增（不用 tick 每 250ms
   * 推进——那会把列表滚动位置每 250ms 归零）。
   */
  @State roomPlayEpoch: number = 0;
  private roomPlaySig: string = '';

  /**
   * 房间资源面板显隐（605，**必须 @State**）。
   *
   * 【真机回归：点面板开关「收起」后视频全屏了，但面板还在】
   * `build()` 里的 `if (this.roomPanelVisible())` 读的是
   * `this.state().resourcePanelOpen`——宿主**普通字段**，不在 ArkUI 观察链
   * 上 → 这个 `if` 节点**不会随状态变化重新求值**，面板节点一直留在树里。
   * 而 `videoW`/`videoH` 是 `@State`（会刷新）→ 视频区确实恢复了全屏，
   * 两者不同步 → 「视频全屏了但面板还在」。
   *
   * 修法：镜像到 `@State`，`if` 条件直读它才会随变化销毁/重建节点。
   */
  @State roomPanelShown: boolean = false;

  /**
   * 房间头部三个控件的数据源（605，**必须 @State**）。
   *
   * 【真机回归：初始房间无播放时头部缺搜索、人数、角色徽章】这三个控件
   * 的条件/文案读的是 `this.state().isHost` / `onlineUserCount` /
   * `audienceName`——宿主普通字段（不在观察链），只能靠面板节点重建才取到
   * 新值；而空房间时重建签名（paused|currentEpisodeIndex）恒定，节点根本
   * 不重建 → 永远停在首次渲染时的空值。
   *
   * 修法：镜像到 `@State`，`@Builder` 内直读 `@State` → 任何变化立即刷新
   * （不依赖重建纪元）。
   */
  @State roomIsHost: boolean = false;
  @State roomOnlineCount: number = 0;
  @State roomAudienceName: string = '';

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
  /**
   * 柱条轨道实测高度（vp）——624。
   *
   * ArkUI **不支持 `calc()`**，旧实现用
   * `margin({ left: \`calc(${percent}% - 6vp)\` })` 定位滑块 → 位置无效
   * （真机滑块跑到轨道外）。改为 `onAreaChange` 拿实测高度、按
   * `ratio * h` 算 `margin.top`（与安卓 `VerticalGaugeView` 自绘同精度）。
   */
  @State gaugeTrackH: number = 0;
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
    // 607：无播放内容 → 渲染占位提示（见 playerReady 注释）。
    this.playerReady = s.playerReady;
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
    // 605：房间面板显隐 + 头部三个控件的数据源镜像到 @State
    //（宿主普通字段不在 ArkUI 观察链上，见字段注释）。
    this.roomPanelShown = s.isRoom && s.resourcePanelOpen;
    this.roomIsHost = s.isHost;
    this.roomOnlineCount = s.onlineUserCount;
    this.roomAudienceName = s.audienceName;
    // 资源面板重建纪元（604 补全签名）。
    //
    // 【真机回归：空房间/未播放时头部缺搜索、人数、角色徽章】
    // 600 的签名只含 `paused | currentEpisodeIndex`——空房间时这两项恒定
    // → epoch 不推进 → `RoomPanel` 节点不重建 → 头部那些读宿主普通字段
    // （不在 ArkUI 观察链上）的条件永远取不到新值。
    //
    // 【真机回归：搜索添加的新资源不立即显示】同理——签名不含资源分组
    // 内容，新资源加进来后签名不变 → 列表不重建。
    //
    // 修法：签名补全所有**驱动面板渲染**的字段。分组内容用轻量签名
    //（组名/季数/各季集数），不逐条比 name/poster——那会每 tick 都变。
    // 【真机回归：资源列表无法展开子分支】604 的签名只算「组名:季数:各季
    // 集数」，**不含 collapsed**——折叠/展开只改折叠态，签名不变 → 列表
    // 不重建 → 箭头与内容都不变。605 补上组/季的折叠态。
    const groupsSig = this.state().resourceGroups
      .map((g: NativeResourceGroupUi): string =>
        `${g.name}:${g.collapsed}:${g.seasons.length}:${g.seasons
          .map((s: NativeSeasonGroupUi): string =>
            `${s.collapsed}/${s.episodes.length}`)
          .join(',')}`)
      .join('|');
    const playSig = `${this.paused}|${this.currentEpisodeIndex}`
      + `|${this.roomIsHost}|${this.roomOnlineCount}`
      + `|${this.roomAudienceName}|${this.roomPanelShown}`
      + `|${groupsSig}`
      + `|${this.state().broadcasts.length}`;
    if (playSig !== this.roomPlaySig) {
      this.roomPlaySig = playSig;
      this.roomPlayEpoch = this.roomPlayEpoch + 1;
    }
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
    // 600：房间面板开关 / 转屏都要重算控件层分栏收窄。
    this.updateControlsSplit();
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
    // 600：分栏收窄兜底（onAreaChange 在面板开关时不触发）。
    this.updateControlsSplit();
    // 623：画布尺寸兜底同步（面板初始展开时 onAreaChange 可能拿到全屏值）。
    this.syncSurfaceSize();
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

  /**
   * 控件层分栏收窄（600）。
   *
   * 对齐安卓 `applyVideoSplit`：横屏只收宽度（视频区底 == 屏幕底），竖屏
   * 只收高度（视频区宽 == 屏幕宽），未分栏时两者置 0（回落 '100%'）。
   *
   * 【必须显式调用】`onAreaChange` 只在**屏幕尺寸变化**时触发；房间面板
   * 开关时屏幕尺寸不变，只靠它会让收窄永远不生效（面板盖住控件）。
   * 因此 `onStateChanged`（每次状态推送）与 `tick`（250ms 兜底）都要调。
   */
  private updateControlsSplit(): void {
    const w = this.areaWidth;
    const h = this.areaHeight;
    // 605：用 @State 镜像（`roomPanelVisible()` 读宿主普通字段，与本方法
    // 的 @State 结果可能不同步）。
    const split = this.roomPanelShown && w > 0 && h > 0;
    if (split && !this.portrait) {
      this.controlsW = Math.max(1, w - ROOM_PANEL_WIDTH);
      this.controlsH = 0;
      // 602：视频层同样按显式宽度收窄（横屏视频区底 == 屏幕底）。
      this.videoW = Math.max(1, w - ROOM_PANEL_WIDTH);
      this.videoH = 0;
    } else if (split && this.portrait) {
      this.controlsW = 0;
      this.controlsH = Math.max(1, h - ROOM_PANEL_HEIGHT);
      // 602：竖屏视频区宽 == 屏幕宽，只收高度。
      this.videoW = 0;
      this.videoH = Math.max(1, h - ROOM_PANEL_HEIGHT);
    } else {
      this.controlsW = 0;
      this.controlsH = 0;
      this.videoW = 0;
      this.videoH = 0;
    }
  }

  /**
   * 623：画布尺寸兜底同步。
   *
   * 把 `XComponent` 最新实测尺寸（vp → px）同步给 mpv；尺寸未变时直接
   * 返回（`handleSurfaceChanged` 内部也有幂等保护，双重保险）。
   *
   * 为什么需要：`onAreaChange` 在「房间面板初始就展开」场景可能早于
   * Flex 布局完成 → 拿到全屏尺寸 → mpv 按错误画布合成 → 画面拉伸。
   */
  private syncSurfaceSize(): void {
    const wVp = this.xcWidth;
    const hVp = this.xcHeight;
    if (wVp <= 0 || hVp <= 0) {
      return;
    }
    const host = HimiMpvNativeHost.getInstance();
    const wPx = Math.trunc(this.getUIContext().vp2px(wVp));
    const hPx = Math.trunc(this.getUIContext().vp2px(hVp));
    if (wPx <= 0 || hPx <= 0) {
      return;
    }
    if (wPx === host.canvasWidth && hPx === host.canvasHeight) {
      return; // 尺寸未变：跳过（避免每 tick 重复 setProperty）
    }
    host.surfaceChanged('', wPx, hPx);
  }

  /**
   * 624：柱条滑块/光晕的 `margin.top`（vp）。
   *
   * 轨道从底部往上填充（值越大越高），故 top = (1 - ratio) * 轨道高 - 半径，
   * 使圆点中心落在填充顶端。轨道高由 `onAreaChange` 实测（ArkUI 无 calc）。
   *
   * @param radius 光晕 10 / 拇指 6
   */
  private gaugeThumbTop(radius: number): number {
    const h = this.gaugeTrackH;
    if (h <= 0) {
      return 0;
    }
    const ratio = Math.max(0, Math.min(1, this.verticalBarPercent / 100));
    return Math.max(0, (1 - ratio) * h - radius);
  }

  /**
   * 625：视频按比例适配可用区域的**显示宽**（vp）。
   *
   * 返回 -1 表示「未就绪/无法计算」→ 调用方回落到 `'100%'`（撑满）。
   *
   * 算法（与 mpv `keepaspect` 语义一致）：
   * - 视频比区域"更宽" → 以区域宽为准（上下留黑边）；
   * - 否则以区域高为准（左右留黑边）。
   */
  private videoFitW(): number {
    const vw: number = HimiMpvNativeHost.getInstance().state.videoWidth;
    const vh: number = HimiMpvNativeHost.getInstance().state.videoHeight;
    const aw: number = this.videoAreaW;
    const ah: number = this.videoAreaH;
    if (vw <= 0 || vh <= 0 || aw <= 0 || ah <= 0) {
      return -1;
    }
    const videoAspect = vw / vh;
    const areaAspect = aw / ah;
    return videoAspect > areaAspect ? aw : ah * videoAspect;
  }

  /** 625：视频按比例适配可用区域的**显示高**（vp）。-1 = 未就绪。 */
  private videoFitH(): number {
    const vw: number = HimiMpvNativeHost.getInstance().state.videoWidth;
    const vh: number = HimiMpvNativeHost.getInstance().state.videoHeight;
    const aw: number = this.videoAreaW;
    const ah: number = this.videoAreaH;
    if (vw <= 0 || vh <= 0 || aw <= 0 || ah <= 0) {
      return -1;
    }
    const videoAspect = vw / vh;
    const areaAspect = aw / ah;
    return videoAspect > areaAspect ? aw / videoAspect : ah;
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
    // 622：音量/亮度是**本地设备属性**，与房间同步无关 → 所有成员可调。
    // 只保留锁定态检查；横拖 seek 是播放控制，在下面单独检查 canControl。
    if (s.locked) {
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
      // 622：横拖 seek 是**播放控制** → 观众不允许。
      if (!s.canControl) {
        return;
      }
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
  /** 屏幕高度（600：控件层竖屏分栏收窄用；onAreaChange 喂入）。 */
  private areaHeight: number = 0;

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

  /**
   * 音量图标码位（对齐 Flutter `_buildVolumeBar`）：
   * 0 → off、<50 → down、其余 → up。
   */
  private volumeGlyphFor(percent: number): number {
    if (percent <= 0) {
      return NativePlayerIcons.ICON_VOLUME_OFF;
    }
    return percent < 50
      ? NativePlayerIcons.ICON_VOLUME_DOWN
      : NativePlayerIcons.ICON_VOLUME_UP;
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
    // 【608 真机回归：面板开关按钮飞出屏幕（竖屏超出界面）】修正。
    //
    // 604 起房间模式在 trailing 槽尾部加了 `panelToggle`（32vp + 间距），
    // 但这里**一直漏算它** → `natural` 少 52vp → `bottomScale` 算得偏大 →
    // 簇实际宽度超出 trailing 槽 → 按钮被挤出可视区（竖屏尤其明显）。
    if (this.state().isRoom) {
      blocks++;
    }
    const speedChip = this.state().tvMode && !this.state().isRoom;
    const widths = blocks * 32 + (speedChip ? 64 : 0);
    // panelToggle 额外带 `margin.left`（与图标簇的间距）——已含在 gaps 里。
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

  /**
   * 房间资源面板是否可见（房间模式 + 面板展开）。
   *
   * 【605：仅供诊断/表达式复用，不再用于 `build()` 的条件】
   * ArkUI 的 `if` 节点不会随宿主**普通字段**变化重新求值——渲染条件必须
   * 读 `@State roomPanelShown`（见该字段注释）。本方法保留是因为
   * `roomPanelShown` 的语义与它完全一致，便于对照排查。
   */
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
      //
      // 【真机回归：初始房间头部不显示搜索/人数/房主徽章】611 修正（第 5 轮）。
      //
      // 前 4 轮都在 ArkUI 里试「让兄弟节点不被压扁」的写法，但方向错了：
      // - 606 `constraintSize({ minWidth })` —— **无效**，`layoutWeight(1)`
      //   的优先级高于它；
      // - 607 `Blank()` —— **无效**，Blank 在 Row 里没能按预期撑开；
      // - 608/610 也没解决。
      //
      // 根因：**ArkUI 的 `layoutWeight` 与安卓 `LinearLayout` 权重语义不同**
      // ——安卓 `LayoutParams(0, WRAP_CONTENT, 1f)` 是「先测量兄弟节点的
      // 自身宽度，剩余空间才给权重节点」；而 ArkUI `layoutWeight(1)` 会
      // 直接抢占剩余空间，把兄弟压成 0 宽。
      //
      // 611 对齐安卓做法：改用 `Flex`，标题 `flexShrink(1)`（可收缩但不
      // 抢占），右侧三个控件 `flexShrink(0)`（固定尺寸、不参与收缩）——
      // 等价安卓给它们固定 `LayoutParams`。
      Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center }) {
        Text('资源')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 【612 真机回归：三个控件挤在标题左边、没有靠右】修正。
          //
          // 611 只给了 `flexShrink(1)`——它只是「空间不足时可收缩」，
          // **不会撑开**。标题按内容宽度（"资源" 2 字 ≈ 28vp），剩余空间
          // 没人占 → 右侧控件紧跟在标题后面（靠左）。
          // 安卓能靠右是因为 `LayoutParams(0, WRAP_CONTENT, 1f)` 的**权重
          // 1 让标题吃掉剩余空间**，把右侧控件推过去。
          //
          // 修法：补 `flexGrow(1)`（吃掉剩余空间）+ 保留 `flexShrink(1)`
          // （空间不足时压缩）——与安卓权重 1 等价。
          .flexGrow(1)
          .flexShrink(1)
          .margin({ right: 6 });
        // 搜索：房主 **且暂停中** 才显示（Flutter
        // `_roomData != null && _isHost && state != playing`）。
        // 605：读 @State 镜像（`this.state().isHost` 是宿主普通字段，不在
        // ArkUI 观察链 → 空房间时永远取不到值、控件不出现）。
        if (this.roomIsHost && this.paused) {
          Text(String.fromCodePoint(NativePlayerIcons.ICON_SEARCH))
            .fontFamily(NativePlayerIcons.FONT_FAMILY)
            .fontSize(20)
            .fontColor('#B3FFFFFF')
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            // 611：固定尺寸、不参与收缩（等价安卓 llp(dp(28), dp(28))）。
            .flexShrink(0)
            .margin({ right: 6 })
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
          Text(`${this.roomOnlineCount}`)
            .fontSize(11)
            .fontColor('#B3FFFFFF');
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor('#1FFFFFFF')
        .borderRadius(8)
        .alignItems(VerticalAlign.Center)
        // 611：固定尺寸、不参与收缩（等价安卓 llp(WRAP_CONTENT, dp(20))）。
        // `constraintSize` 只是保底，`flexShrink(0)` 才是「不被压扁」的正解。
        .constraintSize({ minWidth: 40, minHeight: 20 })
        .flexShrink(0)
        .margin({ right: 6 });
        // 角色徽章：房主 accent / 观众红。
        Text(this.roomIsHost
          ? '房主'
          : (this.roomAudienceName.length > 0 ? this.roomAudienceName : '观众'))
          .fontSize(11)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor(this.roomIsHost ? SEL_COLOR : '#E53935')
          .borderRadius(8)
          // 611：固定尺寸、不参与收缩（等价安卓 llp(WRAP_CONTENT, dp(20))）。
          .constraintSize({ minWidth: 32, minHeight: 20 })
          .flexShrink(0);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
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
      if (this.roomIsHost) {
        // 600：读 @State 镜像 `this.paused`（在观察链上）；旧实现读
        // `state().paused`（宿主普通字段，不在观察链）→ 图标不刷新。
        // 605：`isHost` 同样改读 @State（否则空房间时图标不出现）。
        Text(String.fromCodePoint(
          ep.isPlaying && !this.paused
            ? NativePlayerIcons.ICON_PAUSE_CIRCLE
            : NativePlayerIcons.ICON_PLAY_CIRCLE))
          .fontFamily(NativePlayerIcons.FONT_FAMILY)
          .fontSize(22)
          .fontColor(ep.isPlaying ? SEL_COLOR : '#8AFFFFFF')
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .margin({ right: 8 })
          // 【真机回归：资源行前面的播放/暂停控件点击没反应】607 修正。
          //
          // 604 修「删除按钮冒泡到切集」时把行容器的 onClick 移到了内容区
          // 容器（缩略图 + 集信息），但**遗漏了本图标**——它既没有自己的
          // onClick，也不再能靠父容器冒泡 → 点击完全无响应（死区）。
          //
          // Flutter 的 `TvFocusable(onTap)` 是独立点击：当前集→暂停/继续，
          // 其它集→切集。这里补齐同样语义。
          .onClick((): void => {
            if (ep.isPlaying) {
              this.host().optimisticTogglePaused();
            } else {
              this.host().optimisticSelectEpisode(ep.index);
            }
          })
          // 自身响应并阻止被遮挡节点：确保点击只作用于本图标、不穿透到
          // 内容区（否则会同时触发切集，出现双重动作）。
          .hitTestBehavior(HitTestMode.Block);
      }
      // 【604 真机回归：列表里删除无效（点了变成切集）】
      //
      // 旧结构：删除按钮是行容器 `Row` 的**子节点**，而 `Row` 自己有
      // onClick（切集/暂停）。ArkUI 的 onClick 会**冒泡到父节点** →
      // 点删除时先发 removeResourceEpisode、再触发一次切集，删除动作被
      // 掩盖。`ClickEvent` 上**没有** stopPropagation（只有 Hover/Mouse/
      // Touch/Key 有），无法就地阻止。
      //
      // 修法：把「缩略图 + 集信息」包进一个可点击容器，行容器 `Row` 本身
      // 不再挂 onClick。删除按钮与播放图标都是它的**兄弟节点** → 互不冒泡。
      // 与 Flutter（InkWell 包内容区 + IconButton 兄弟）和安卓（子 View
      // 各自 setOnClickListener）一致。
      Row() {
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
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        // 内容区点击：当前集→暂停/继续，其它集→切集。
        if (!this.roomIsHost) {
          return;
        }
        if (ep.isPlaying) {
          this.host().optimisticTogglePaused();
        } else {
          this.host().optimisticSelectEpisode(ep.index);
        }
      });

      // 删除（房主）—— 与内容区是兄弟节点，点击不再冒泡到切集逻辑。
      if (this.roomIsHost) {
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
      : { width: 0, color: Color.Transparent });
  }

  /**
   * 视频层 + 手势层（593/594 分栏复用）。
   *
   * 抽成 @Builder 是因为横屏 `Row` 与竖屏 `Column` 两个分支都要同一份
   * 视频内容——ArkTS 不能动态换容器类型，只能各写一份并共用本 @Builder。
   */
  @Builder
  VideoStack() {
    // 【599 结构性修复：单 Stack 包裹】594 抽 @Builder 时把原本在根 Stack
    // 上的手势层误搬了进来 → 本 @Builder 有 **3 个平级子节点**
    //（XComponent + 手势层 A + 手势层 B）。而它被放进 `Row()`：
    //   Row() { this.VideoStack(); this.RoomPanelSlot(); }
    // @Builder 展开后 Row 里是 4 个节点、其中 3 个都设 `'100%'` → 横向挤占，
    // XComponent 只占第一格（画面偏左/被裁），手势层被挤出屏外（点屏无
    // 反应），Row 尺寸异常又破坏根 Stack 后续控件层的定位基准（顶栏/底栏
    // 全部消失）。真机「每次进播放页都没控件、点屏幕完全没反应」根因。
    //
    // 修法：本 @Builder 只保留**一个顶层节点**（Stack），视频与手势层在
    // Stack 内叠放、各占 100%；分栏用的 layoutWeight/width/height 上移到
    // 这个 Stack 上（`layoutWeight` 与 `width('100%')` 同时设会后者优先，
    // 故展开用 'auto' + layoutWeight、收起用 '100%' + layoutWeight 0）。
    // 625：对齐改 **Center**——XComponent 按视频比例收窄后，黑边要在
    // 上下/左右**对称**分布（旧 Top 会把画面顶到上方）。
    Stack({ alignContent: Alignment.Center }) {
      // ── 视频层 ──
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.controller,
      })
        // 625：按**视频比例**布局（letterbox/pillarbox），不再撑满。
        //
        // 【真机回归：鸿蒙房间面板初始展开时画布拉伸】鸿蒙 `ohosvk`
        // （Vulkan）**不响应运行时 `ohos-surface-size` 重配 swapchain**
        // ——623 的 tick 兜底反复写属性也无效（真机验证）。
        //
        // 根治思路：不让 mpv 适配画布，而是**让画布本身**就是视频比例。
        // 这样 XComponent 的物理尺寸即正确比例，mpv 往里合成时无需缩放
        // → 结构上不可能拉伸。黑边由外层 Stack 的黑色背景提供。
        //
        // 未就绪（videoWidth/Height = 0）时回落 `'100%'` 撑满（保持旧行为）。
        .width(this.videoFitW() > 0 ? this.videoFitW() : '100%')
        .height(this.videoFitH() > 0 ? this.videoFitH() : '100%')
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
        //
        // 【必须挂在 XComponent 自己身上】挂在包裹它的 Stack 上会拿到外层
        // 尺寸（与视频实际画布未必一致），画质/拉伸问题会复发。
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
          // 623：缓存实测值，供 tick 兜底同步（见 xcWidth 注释）。
          this.xcWidth = wVp;
          this.xcHeight = hVp;
          hilog.info(DOMAIN, TAG,
            'area: %{public}dvp x %{public}dvp -> %{public}dpx x %{public}dpx',
            wVp, hVp, wPx, hPx);
          HimiMpvNativeHost.getInstance().surfaceChanged('', wPx, hPx);
        });

      // ── 手势层（视频之上，同尺寸叠放）──
      // 单击显隐控件；双击播放暂停；横拖 seek；纵拖左亮度/右音量；
      // 长按临时倍速。锁定中只保留单击（与 Flutter 一致）。
      //
      // ArkUI 的 `.gesture()` 最多收 2 个参数，多个手势必须用
      // `GestureGroup(Parallel)`——等价 Flutter 手势竞技场：单击/双击由
      // 框架按时间消歧，长按与拖动按位移消歧（位移超阈值即取消长按）。
      //
      // 【599 只保留这一层】590 引入时 Row 里已有一层、根 Stack 顶层又写了
      // 一层完全等价的（重复）；594 又把后者搬进本 @Builder → 同屏两个
      // 手势层抢触摸且被挤出屏外。现在全文件只此一处。
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
        // 【必须 Default，不能 Transparent】Stack 命中测试自上而下：
        // 控件条在上层，若本层用 Transparent 会与控件**同时**进入手势竞技场，
        // 而本层的 PanGesture（Parallel）会抢走触摸流 → 底部控件 onClick
        // 全部失效、面板遮罩点不关（真机回归）。Default 下控件先声明成功，
        // 本层不再介入；空视频区无控件声明，本层照常接管。
        .hitTestBehavior(HitTestMode.Default);
    }
    // 分栏尺寸（610）：回到 **layoutWeight 弹性**——视频层现在是 `Flex`
    // 的第一个子节点，由框架按父容器实测宽分配剩余空间，不参与数值反推。
    //
    // 【必须与 width/height 二选一】ArkUI 里 `layoutWeight` 与 `width('100%')`
    // 同时设置时后者优先、layoutWeight 失效（594 真机回归「视频不收窄、
    // 面板盖在上面」）。因此这里**只设 layoutWeight**，由 Flex 决定尺寸。
    //
    // 面板收起时 Flex 只有视频一个子节点 → layoutWeight(1) 自然铺满。
    .layoutWeight(1)
    // 625：实测 Flex 分配给视频子节点的尺寸，供 videoFitW/H 算 letterbox。
    // 挂在**视频子节点**上（不是根 Stack），拿到的是视频区而非全屏。
    .onAreaChange((_old: Area, area: Area): void => {
      const w = area.width as number;
      const h = area.height as number;
      if (w > 0 && w !== this.videoAreaW) {
        this.videoAreaW = w;
      }
      if (h > 0 && h !== this.videoAreaH) {
        this.videoAreaH = h;
      }
    });
  }

  /** 房间资源面板槽（593/594）：横屏右侧 320vp / 竖屏底部 280vp。 */
  @Builder
  RoomPanelSlot() {
    // 600：按 roomPlayEpoch 重建面板子树——`RoomEpisodeRow` 的播放/暂停
    // 图标读的是 `this.paused`（@State 镜像），但 `RoomPanel` 不在任何
    // ForEach 重建块里 → 暂停/恢复时节点不重建、图标不刷新（真机
    // 「资源列表前面的播放/暂停图标状态不变化」）。
    // key 随 epoch 变 → 旧节点销毁、新节点创建 → 图标取最新值。
    //
    // 【610 真机回归：横屏头部缺三控件 / 面板整个消失】602~608 这里一直
    // 用 `Stack` + `alignContent`（或更早的 `margin`）叠加定位，而那个
    // `Stack` 容器是全屏尺寸 → 面板贴到**全屏右缘**、落在资源面板下面；
    // 或 `margin.left = videoW` 因 `areaWidth` 在子窗口场景偏大而被裁到屏外。
    //
    // 610 起本 @Builder 只作为 `Flex` 的**流式子节点**参与布局——尺寸由
    // Flex 按父容器实测值分配（横屏固定 320vp、竖屏固定 280vp），
    // 不参与任何数值反推，从根上消除「跑到屏幕外」。
    ForEach([this.roomPlayEpoch], (epoch: number): void => {
      Column() {
        this.RoomPanel();
      }
      .width(this.portrait ? '100%' : ROOM_PANEL_WIDTH)
      .height(this.portrait ? ROOM_PANEL_HEIGHT : '100%');
    }, (epoch: number): string => `room-${epoch}`);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 【602：根 Stack 对齐改 TopStart】`Alignment.Top` 的**水平**对齐是
      // `Center`——控件层容器宽度是具体数值（屏宽 - 320vp，不足 100%）时
      // 会被水平居中，右缘被资源面板切掉（真机截图回归）。
      // `TopStart` 让不足宽的子节点贴左。已核实其余子节点全是 100%（不受
      // 影响），只有控件层会受此约束。
      //
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
      // ── 视频层（唯一实例，转屏不销毁重建）──
      //
      // 【真机回归：横竖屏切换短暂黑屏】594 用 `if (portrait) {
      // Column{VideoStack} } else { Row{VideoStack} }` 双分支各写一份
      // `VideoStack()`——ArkUI 条件翻转会**整体销毁旧分支、创建新分支**，
      // 里面的 `XComponent` 随之销毁重建（onSurfaceDestroyed → 解绑 →
      // 黑一帧 → onSurfaceCreated → 重绑 → 画面回来）。
      //
      // 602 修法：视频层提到分支**之外**、根 Stack 里只存在一份。方向切换
      // 只移动资源面板，视频节点完全不动 → 无黑屏。
      // 尺寸由 videoW/videoH 显式控制（见字段注释）。
      // ── 视频 + 房间资源面板：Flex 流式分栏（610）──
      //
      // 【610 真机回归：横屏头部仍缺三控件 / 面板整个消失】602~608 一直是
      // 「视频层常驻 + 面板用 Stack alignContent 或 margin 叠加定位」，而
      // 那个 Stack 容器是**全屏尺寸**（`width('100%')`）→ `TopEnd` 让面板贴
      // **全屏右缘**，正好落在资源面板下面（被盖住）；`margin.left = videoW`
      // 又依赖不可靠的 `areaWidth`（子窗口场景偏大 → 面板右缘被裁到屏外）。
      // 两者都会让面板跑到屏幕外，头部三个控件随之不可见。
      //
      // 修法：改回**流式布局**——`Flex` 把视频与面板作为兄弟节点排布，
      // 宽度由框架按父容器实测值分配（`layoutWeight(1)` 吃剩余），
      // 不参与任何数值反推。
      //
      // 【为什么用 Flex 而不是 if/else 换 Row/Column】
      // - `if/else` 换**容器类型**会让 ArkUI 整体销毁子树 → `XComponent`
      //   随之销毁重建 → 转屏黑一帧（594 真机回归）；
      // - `Flex` 的 `direction` 是**属性**，转屏只改属性、子树不销毁。
      //
      // 【方向语义】横屏 = Row（视频左、面板右 320vp）；
      // 竖屏 = Column（视频上、面板下 280vp）——对齐 Flutter
      // `Row(Expanded(video), SizedBox(320))` / `Column(Expanded, SizedBox(280))`。
      Flex({
        direction: this.portrait ? FlexDirection.Column : FlexDirection.Row,
      }) {
        // 【611 真机回归：删除后资源面板变整块黑色】修正。
        //
        // 607 把空态占位层放在根 `Stack` 上、且是 `width('100%') +
        // backgroundColor(Color.Black)` → **不透明黑底盖住了整个屏幕**，
        // 包括 `Flex` 里的资源面板（真机截图「面板整块黑色、标题列表全无」）。
        //
        // 修法：占位层放进 `Flex` 的**视频子节点**内（用 Stack 包住视频 +
        // 占位），只覆盖视频区，资源面板不受影响。
        Stack() {
          this.VideoStack();
          if (!this.playerReady) {
            Column() {
              Text(String.fromCodePoint(NativePlayerIcons.ICON_PLAY_CIRCLE))
                .fontFamily(NativePlayerIcons.FONT_FAMILY)
                .fontSize(64)
                .fontColor('#3DFFFFFF'); // Flutter Colors.white24
              Text('请从资源面板选择要播放的内容')
                .fontSize(14)
                .fontColor('#61FFFFFF') // Flutter Colors.white38
                .margin({ top: 16 });
            }
            .width('100%')
            .height('100%')
            // mpv `stop()` 后 surface 上仍残留最后一帧，占位层若不透明才
            // 能盖住（透明会让旧画面透出来，真机截图能看到人像隐约浮现）。
            .backgroundColor(Color.Black)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            // 不抢手势：点屏仍可显隐控件（与加载指示器同款）。
            .hitTestBehavior(HitTestMode.None);
          }
        }
        .layoutWeight(1);
        if (this.roomPanelShown) {
          this.RoomPanelSlot();
        }
      }
      .width('100%')
      .height('100%');

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
        // 624：宽高**都**取视频区（622 只改了高度 → 横屏分栏时宽度仍是
        // 全屏，水平居中偏右、转圈落到资源面板区域）。
        .width(this.videoW > 0 ? this.videoW : '100%')
        .height(this.videoH > 0 ? this.videoH : '100%')
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
        // 【600 流式布局：顶栏贴顶、Blank 弹性推底栏贴底】
        //
        // 旧实现底栏壳用 `.position({x:0, y:'100%'}) + markAnchor({y:'100%'})`
        // 绝对定位贴根 Stack 底缘。问题：
        // - 分栏后根 Stack 仍是全屏 → 底栏贴「全屏底」而不是「视频区底」
        //  （竖屏时被资源面板完全盖住）；
        // - 百分比定位 + 其他属性叠加会跑位（597 的 `.translate` 就是这么
        //   把控件推到屏幕外的）。
        //
        // 改为 **Column + Blank 流式布局**：容器高度 = 视频区高
        // （`controlsH`，未分栏时 100%），顶栏在顶部、Blank 吃掉中间剩余、
        // 底栏自然落在容器底缘。不依赖任何百分比定位与平移属性。
        Column() {
          if (this.locked && !this.state().tvMode) {
            // ── 锁定态：仅左下锁钮（贴容器底，与进度条左数显同列）──
            // Blank 在前把锁钮推到视频区底缘（对齐 Flutter
            // `_buildLockOnlyControls` 的底部渐变条）。
            Blank();
            ForEach([this.controlsEpoch], (epoch: number): void => {
              this.LockOnlyBar({ rev: this.renderTick });
            }, (epoch: number): string => `ctl-${epoch}`);
          } else {
            // 【节点重建 = @Builder 子树唯一认的刷新】ForEach key 变化 → 旧节点
            // 销毁、新节点创建 → TopBar 重新执行 → 图标/角标全部取最新值
            //（与"隐藏再现"同一机制，由 controlsEpoch 即时触发）。
            ForEach([this.controlsEpoch], (epoch: number): void => {
              this.TopBar({ rev: this.renderTick });
            }, (epoch: number): string => `ctl-${epoch}`);

            // 弹性占位：把底栏推到容器（= 视频区）底缘。
            Blank();
            // ── 底栏壳（稳定层，不随 epoch 重建）──
            // 显隐条件与旧逻辑一致：仅「锁定 + 手机」走 LockOnlyBar、不出底栏；
            // 锁定 + TV 仍显示底栏（锁钮在 ControlRow 里）。
            // logo 进重建块会随每秒重建反复销毁/重载图片 → 闪烁（真机回归）；
            // 渐变/空点击吸收同样保持稳定。动态内容（进度行 + 控件行）
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
            });
          }
        }
        // 分栏收窄（对齐安卓 applyVideoSplit）：横屏收宽度、竖屏收高度；
        // 未分栏时 0 → 回落 '100%'（与分栏前的行为完全一致）。
        .width(this.controlsW > 0 ? this.controlsW : '100%')
        .height(this.controlsH > 0 ? this.controlsH : '100%')
        // 【602：控件层贴左靠根 Stack 的 alignContent】601 曾在这里加
        // `.align(Alignment.TopStart)`——那是**错的**：`.align()` 的语义是
        // 「组件内容在自身绘制区内的对齐」，不能定位组件在父 Stack 中的
        // 位置，真机截图证实无效（控件仍居中）。
        // 正确修法是根 Stack 改 `Alignment.TopStart`（见 build 顶部注释）。
        .alignItems(HorizontalAlign.Start)
        // 不挡下层手势层：控件条自身有 onClick 吸收点击，空白区放行。
        .hitTestBehavior(HitTestMode.Transparent);
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
        // 623：容器尺寸取**视频区**（旧实现 100%/100% 是全屏 → 分栏时
        // 提示落到资源面板区域，双击播放/暂停图标不在画布中心）。
        .width(this.videoW > 0 ? this.videoW : '100%')
        .height(this.videoH > 0 ? this.videoH : '100%')
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
        // 623：同手势提示，容器取视频区尺寸（画布内居中）。
        .width(this.videoW > 0 ? this.videoW : '100%')
        .height(this.videoH > 0 ? this.videoH : '100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None);
      }

      if (this.verticalBarPercent >= 0) {
        // 音量/亮度柱条（624：三端样式统一 + 长度 40%）。
        //
        // 参数逐项对齐 Flutter `_buildVerticalBar` / 安卓
        // `VerticalGaugeView`：
        //   宽 36 · 圆角 18 · 黑54 底
        //   [图标 18 white70，上边距 12]
        //   [间距 8]
        //   [轨道：粗 4 白24% + 填充 accent + 光晕 r10 alpha0x40 + 拇指 r6 白]
        //   [间距 8]
        //   [数值 11 white70，纯数字无 % 号]
        //
        // 位置：容器取**视频区**尺寸（624 修：旧实现 `width('100%')` 是
        // 全屏 → 亮度条贴全屏右缘、落到资源面板上）。
        // 长度：上下各留 30% → 柱条高 40%（用户要求「缩短点」）。
        Column() {
          Column() {
            // 图标：音量随百分比切换（off/down/up），亮度固定。
            Text(String.fromCodePoint(this.verticalBarOnLeft
              ? NativePlayerIcons.ICON_BRIGHTNESS
              : this.volumeGlyphFor(this.verticalBarPercent)))
              .fontFamily(NativePlayerIcons.FONT_FAMILY)
              .fontSize(18)
              .fontColor('#B3FFFFFF')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 12 });

            // 轨道区（图标下间距 8 → 数值上间距 8）
            Stack({ alignContent: Alignment.Top }) {
              // 未填充整段（白24%，粗 4）
              Row()
                .width(4)
                .height('100%')
                .backgroundColor('#3DFFFFFF')
                .borderRadius(2);
              // 已填充段：从**底部**往上（值越大越高，与 Flutter
              // `RotatedBox(-1)` / 安卓 `trackBottom - filled` 同向）。
              //
              // 【625 真机回归：填充从顶部往下长，方向反了】旧实现用
              // `.align(Alignment.Bottom)` —— **ArkUI 的 `.align()` 只控制
              // 组件内容在其绘制区域内的对齐，不定位组件在父 Stack 中的
              // 位置**（AGENTS.md 已记录该坑）。故它跟随外层
              // `alignContent: Alignment.Top` 顶部对齐。
              //
              // 修法：用**容器级** `alignContent`（真正决定子节点在容器内
              // 的位置）——嵌套一层 `Stack({ alignContent: Bottom })`。
              Stack({ alignContent: Alignment.Bottom }) {
                Row()
                  .width(4)
                  .height(`${this.verticalBarPercent}%`)
                  .backgroundColor(this.verticalBarOnLeft ? '#FFD54F' : '#6366F1')
                  .borderRadius(2);
              }
              .width('100%')
              .height('100%');
              // 光晕（Flutter overlayRadius:10 / 安卓 GAUGE_OVERLAY=10）
              Row()
                .width(20)
                .height(20)
                .borderRadius(10)
                .backgroundColor(this.verticalBarOnLeft ? '#FFD54F' : '#6366F1')
                .opacity(0.25)
                .margin({
                  top: this.gaugeThumbTop(10),
                });
              // 拇指（Flutter thumbRadius:6 / 安卓 GAUGE_THUMB=6）
              Row()
                .width(12)
                .height(12)
                .borderRadius(6)
                .backgroundColor(Color.White)
                .margin({
                  top: this.gaugeThumbTop(6),
                });
            }
            .width('100%')
            .layoutWeight(1)
            .margin({ top: 8, bottom: 8 })
            // 624：实测轨道高度（ArkUI 无 calc()，滑块/光晕位置靠它算准）。
            .onAreaChange((_old: Area, area: Area): void => {
              const h = area.height as number;
              if (h > 0 && h !== this.gaugeTrackH) {
                this.gaugeTrackH = h;
              }
            });

            // 数值（Flutter 只显示数字，无 % 号）
            Text(`${this.verticalBarPercent}`)
              .fontSize(11)
              .fontColor('#B3FFFFFF')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8 });
          }
          .width(36)
          .backgroundColor('#8C000000')
          .borderRadius(18);
        }
        .width(this.videoW > 0 ? this.videoW : '100%')
        .height(this.videoH > 0 ? this.videoH : '100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(this.verticalBarOnLeft ? HorizontalAlign.End : HorizontalAlign.Start)
        .padding({
          left: this.verticalBarOnLeft ? 0 : 20,
          right: this.verticalBarOnLeft ? 20 : 0,
          // 624：长度 40%（上下各留 30%）。
          top: (this.videoH > 0 ? this.videoH : 400) * 0.30,
          bottom: (this.videoH > 0 ? this.videoH : 400) * 0.30,
        })
        .hitTestBehavior(HitTestMode.None);
      }

      // ── 二级面板（Phase 2）：遮住视频，点外/返回关闭 ──
      if (this.activePanel.length > 0) {
        NativePlayerPanel({
          panelType: this.activePanel,
          revision: this.revision,
          // 603：横屏房间模式收窄到视频区（否则面板压在资源面板上）。
          videoW: this.videoW,
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
      this.areaHeight = h;
      this.portrait = h > w && w > 0;
      // 600：控件层分栏收窄（见 updateControlsSplit 注释）。
      this.updateControlsSplit();
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
    // 底部渐变条（非全屏高度）：wrap 高度，对齐 Flutter
    // `_buildLockOnlyControls`（Container with bottom gradient）。
    //
    // 【600 去掉百分比定位】旧实现用 `.position({y:'100%'}) +
    // markAnchor({y:'100%'})` 贴根 Stack 底缘——分栏后那是「全屏底」而非
    // 「视频区底」，且百分比定位与任何附加属性叠加都会跑位（597 的
    // `.translate` 就是这么把控件推到屏幕外的）。
    // 现在它已在控件层 Column 内、前面有 `Blank()` 弹性占位 → 天然贴
    // 容器（= 视频区）底缘，不需要任何定位属性。
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
        // 分享（仅房间**房主**；对齐 Flutter showShare）。
        // 622：观众隐藏分享——只有房主能分享房间。用 Visibility.Hidden
        // 占位（等价安卓 INVISIBLE），保持顶栏尾部布局不塌。
        // 时钟（仅 TV 且格式非 off；对齐 Flutter PlayerClockLayer：
        // `if (!tvMode || !format.enabled) return shrink`）。
        if (this.state().isRoom) {
          // 622：观众隐藏分享（@Builder 返回 void，不能链式加 .visibility
          // ——用容器包一层控制可见性，保持占位不塌）。
          Row() {
            this.IconChip(String.fromCodePoint(NativePlayerIcons.ICON_SHARE), 22, 6, false,
              false, 'share', (): void => {
                this.pokeAutoHide();
                HimiMpvNativeHost.getInstance().shareRoom();
              }, 1);
          }
          .visibility(this.state().isHost ? Visibility.Visible : Visibility.Hidden);
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
        // 622：房间观众不可拖进度（ProgressRow 内会回弹）。
        canControl: this.canControl,
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
        // 【真机回归：房间模式锁控件消失（横竖屏都没了）】601 修正。
        //
        // 旧条件 `!tvMode && !isRoom` 在房间模式下把锁钮整个跳过 → 用户
        // 无法锁定屏幕。Flutter 的 `showPhoneLock = phoneControls &&
        // showLockButton(tvMode)` **与房间模式无关**；安卓侧同样是
        // `lockButton.visibility = if (!tv) VISIBLE else GONE`。
        // 这里对齐两端：只看 tvMode，不看 isRoom。
        if (!this.state().tvMode) {
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
          }, this.canControl);
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
          }, this.canControl);
        if (this.episodeCount > 1) {
          this.TransportGlyph(this.nextGlyph(), 28,
            this.currentEpisodeIndex >= 0 && this.currentEpisodeIndex + 1 < this.episodeCount,
            'next', (): void => {
              this.pokeAutoHide();
              this.onNextEpisode();
            }, this.canControl);
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
          // 【真机回归：面板开关控件太靠右】606 修正。
          //
          // 604 把 panelToggle 放进了内层 `Row({ space: 20 * bottomScale })`
          // ——那个间距是图标簇内部用的（20×缩放），与安卓的 trailing 槽
          // 子项布局不同，真机上按钮贴到最右边缘、与其它图标脱节。
          //
          // 安卓的 panelToggleButton 是 trailing 槽的**独立子项**
          //（`llp(dp(32), dp(32), NPTheme.CONTROL_GAP)`）。这里同样放在
          // trailing 槽内（图标簇之后，由槽的 justifyContent: End 排布）。
          if (this.state().isRoom) {
            // 【@Builder 调用不能接链式属性】`this.IconChip(...)` 返回 void，
            // 不能写 `.margin(...)`（ArkTS 报 "Property 'margin' does not
            // exist on type 'void'"）。用外层 Row 承载间距。
            Row() {
              this.IconChip(
                String.fromCodePoint(NativePlayerIcons.ICON_OPEN_IN_FULL),
                24, 4, false, false, 'panelToggle',
                (): void => {
                  this.pokeAutoHide();
                  this.host().sendCommand('toggleResourcePanel', null);
                },
                this.bottomScale);
            }
            // 与图标簇之间留 CONTROL_GAP（对齐安卓 marginStart）；
            // 右侧再留 8vp——【607 真机回归：按钮几乎压线资源面板边界】
            // `controlsW` 已生效（底栏只到视频区），但本按钮是 trailing 槽
            // 最末元素，右缘正好落在控件层右缘（= 视频区/面板分界），
            // 视觉上「压在资源面板上」。安卓靠 bottomBar 的 16dp padding
            // 留白，这里补一层显式右间距。
            .margin({ left: 20 * this.bottomScale, right: 8 });
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
  TransportGlyph(icon: string, size: number, enabled: boolean, key: string, onTap: () => void,
    visible: boolean = true) {
    Text(icon)
      // 622：房间观众隐藏播放/切集控件（用 Hidden 占位，布局不塌）。
      .visibility(visible ? Visibility.Visible : Visibility.Hidden)
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
