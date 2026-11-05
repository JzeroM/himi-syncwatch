/**
 * Phase 2 二级面板（计划书 §5.2）——Flutter 风格对齐版。
 *
 * 视觉规格照抄 Flutter 侧（lib/screens/player/widgets/selector_side_panel.dart
 * + glass_config.dart），保证 Surface 路径与 Texture 路径切换时观感一致：
 * - 布局：右侧浮层（贴右 12，宽 320，上避顶栏、下避控制条），非底部弹出；
 * - 容器：玻璃卡片（backdropEffect 真模糊 + 0x1F1A1D23 着色 + rim 边框，圆角 16）；
 * - 选中态：靛蓝 #6366F1 + 加粗，右侧对勾占 18px 槽位对齐；
 * - 倍速：纵向列表（与 Flutter ListView 一致，非网格）；
 * - 排版：标题 15 加粗 / 选项行 14，padding h16 v12。
 *
 * 所有交互经 [HimiMpvNativeHost] 的 optimistic* 方法乐观更新 + 回传 Dart；
 * 面板数据来自宿主权威快照的 tracks/episodes/versions。
 */

import {
  HimiMpvNativeHost,
  NativePlayerUiState,
  NativeTrackUi,
  NativeEpisodeUi,
  NativeVersionUi,
  NativeEngineOptionUi,
} from './HimiMpvNativeHost';
import { NativePlayerIcons } from './NativePlayerIcons';
import { GlassSlider } from './GlassSlider';

/** 倍速档位（与 Flutter speedOptions 完全一致）。 */
const SPEED_STEPS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

/** 解码模式档位（与 Dart `decodeMode` 取值一致）。 */
const DECODE_MODES: string[] = ['auto', 'hw', 'sw'];

/**
 * 播放时间格式化：与 Dart `formatPlayerDuration` 一致——有小时用
 * `HH:MM:SS`（全补零），否则 `MM:SS`（分钟补零）。片头片尾卡显示标记位置用。
 */
function formatPlayerTime(ms: number): string {
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
    const hh = h < 10 ? `0${h}` : `${h}`;
    return `${hh}:${mm}:${ss}`;
  }
  return `${mm}:${ss}`;
}

/** 解码模式中文标签（与 Flutter `DecodeModePanel` / 安卓 `decodeModeLabel` 同值）。 */
function decodeModeLabel(mode: string): string {
  if (mode === 'auto') {
    return '智能';
  }
  if (mode === 'hw') {
    return '硬解';
  }
  if (mode === 'sw') {
    return '软解';
  }
  return mode;
}

/**
 * 解码模式说明（逐字对齐 Flutter `DecodeModePanel.descriptions`
 * 与安卓 `decodeModeDesc`）。
 *
 * 旧实现鸿蒙面板只有档位名、没有说明，且 auto 写作「自动」——与 MDK
 * （Flutter）面板不一致，切内核时观感突变。
 */
function decodeModeDesc(mode: string): string {
  if (mode === 'auto') {
    return '优先硬解，失败回退软解';
  }
  if (mode === 'hw') {
    return '纯硬解，失败不回退';
  }
  if (mode === 'sw') {
    return '纯软解，CPU 占用高';
  }
  return '';
}

/**
 * 片头/片尾标记范围校验（588）：片头结束点 ≤ 总时长 10%、片尾开始点
 * ≥ 总时长 70%。返回拒绝文案，null = 通过；时长未知（<=0）不校验。
 *
 * 与 Flutter `SegmentMarkRules.rejectReason` / 安卓 `segmentMarkReject`
 * 逐字逐值一致（整数运算，避免浮点边界差 1ms）。Dart 仍是权威校验点，
 * 这里前置拦截只为避免「已设置…」乐观提示后被 Dart 拒绝。
 */
export function segmentMarkReject(kind: string, positionMs: number, durationMs: number): string | null {
  if (durationMs <= 0) {
    return null;
  }
  if (kind === 'intro') {
    return positionMs > Math.floor(durationMs * 10 / 100)
      ? '片头结束点不能超过总时长的 10%'
      : null;
  }
  return positionMs < Math.ceil(durationMs * 70 / 100)
    ? '片尾开始点不能低于总时长的 70%'
    : null;
}

/** 显示调节滑杆行规格（标签 / 最小 / 最大 / 步长）。 */
class DisplaySliderSpec {
  key: string = '';
  label: string = '';
  min: number = 0;
  max: number = 1;
  step: number = 1;

  constructor(key: string, label: string, min: number, max: number, step: number) {
    this.key = key;
    this.label = label;
    this.min = min;
    this.max = max;
    this.step = step;
  }
}

/** 显示调节滑杆规格（字幕 3 行 + 弹幕 3 行，与 Flutter 显示调节一致）。 */
const DISPLAY_SLIDERS: DisplaySliderSpec[] = [
  new DisplaySliderSpec('subtitleScale', '大小', 0.5, 3.0, 0.05),
  new DisplaySliderSpec('subtitleMarginY', '位置', 0, 200, 2),
  new DisplaySliderSpec('subtitleDelayMs', '延迟', -5000, 5000, 100),
  new DisplaySliderSpec('danmakuSpeed', '速度', 0.5, 2.0, 0.05),
  new DisplaySliderSpec('danmakuFontSize', '大小', 0.5, 2.0, 0.05),
  new DisplaySliderSpec('danmakuOpacity', '透明度', 0.1, 1.0, 0.05),
];

/**
 * 显示调节「恢复默认」默认值——与安卓一致：
 * 字幕段 = Flutter `SubtitleStylePanel` 默认（mdk 初始化属性 1.0 / 22 / 0）；
 * 弹幕段 = 安卓 `AppSettings` 默认 = Flutter 播放器 onDanmakuReset 同值
 *（1.0 / 0.5 / 0.8）。
 */
const DEFAULT_SUBTITLE_SCALE = 1.0;
const DEFAULT_SUBTITLE_MARGIN_Y = 22;
const DEFAULT_SUBTITLE_DELAY_MS = 0;
const DEFAULT_DANMAKU_SPEED = 1.0;
const DEFAULT_DANMAKU_FONT_SIZE = 0.5;
const DEFAULT_DANMAKU_OPACITY = 0.8;

/**
 * 显示调节数值格式（照抄 Flutter：字幕段 SubtitleStylePanel、弹幕段
 * DanmakuStylePanel 的 format* 系列）。
 */
function displayValueText(key: string, v: number): string {
  if (key === 'subtitleScale' || key === 'danmakuSpeed' || key === 'danmakuFontSize') {
    return `${v.toFixed(2)}×`;
  }
  if (key === 'subtitleMarginY') {
    return `${Math.round(v)}px`;
  }
  if (key === 'subtitleDelayMs') {
    const sign = v > 0 ? '+' : '';
    return `${sign}${(v / 1000).toFixed(1)}s`;
  }
  return `${Math.round(v * 100)}%`; // danmakuOpacity
}

/**
 * 显示调节滑杆数值（**自驱刷新**子组件）。
 *
 * 【真机回归：拖滑杆数值不同步】数值文本在 @Builder（DisplayContent）里，
 * @Builder 子树只认节点重建——拖动时宿主状态变了文本不刷新。走
 * DanmakuLayer 已验证机制：子组件自带 timer 写 @State → build() 直读
 * → 100ms 级跟手刷新，Slider 本体不受重建影响（拖动不中断）。
 */
@Component
struct DisplayValueText {
  @Prop keyName: string = '';
  @State text: string = '';
  private timer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.timer = setInterval((): void => {
      this.refresh();
    }, 100);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private refresh(): void {
    const s = HimiMpvNativeHost.getInstance().state;
    let v = 0;
    if (this.keyName === 'subtitleScale') {
      v = s.subtitleScale;
    } else if (this.keyName === 'subtitleMarginY') {
      v = s.subtitleMarginY;
    } else if (this.keyName === 'subtitleDelayMs') {
      v = s.subtitleDelayMs;
    } else if (this.keyName === 'danmakuSpeed') {
      v = s.danmakuSpeed;
    } else if (this.keyName === 'danmakuFontSize') {
      v = s.danmakuFontSize;
    } else if (this.keyName === 'danmakuOpacity') {
      v = s.danmakuOpacity;
    }
    this.text = displayValueText(this.keyName, v);
  }

  build() {
    // 统一排版：数值 13 / w500 纯白（旧实现 12sp 半透明白，在弹层底上
    // 几乎看不见——这是「面板文字不统一」最明显的一处）。
    Text(this.text)
      .fontSize(13)
      .fontWeight(PANEL_BODY_WEIGHT)
      .fontColor(PANEL_TEXT)
      .width(48)
      .textAlign(TextAlign.End);
  }
}

/** 选中主色（照抄 Flutter Color(0xFF6366F1)）。 */
const SEL_COLOR = '#6366F1';

// ═══════════════════════════════════════════════════════════════
// 播放器弹层「深色磨砂」调色板（与 Flutter GlassConfig.playerPanel*、
// Android NPTheme.PANEL_GLASS_* 逐值一致）
// ═══════════════════════════════════════════════════════════════
//
// 【范围铁律】仅用于播放器内的**弹出面板**（右侧侧栏 / 解码 popover /
// 片头片尾卡）。顶栏、底栏、手势提示胶囊保持深色玻璃（浮在视频上必须
// 深色白字）。
/**
 * 深色磨砂基色（65% 不透明；留出空间让 backgroundEffect 的模糊视频透出）。
 *
 * 587 由 585 纯白 → 586 暖白 → 改深色：暖白即使压到 55% 仍是「一块亮板」，
 * 暗场景与视频亮度差过大、弹层出现瞬间刺眼，且把磨砂完全盖死。
 */
const PANEL_GLASS_BASE = '#A61A1D23';
/** 竖向渐变：顶部提亮 → 基色 → 底部略透（菲涅尔近似）。 */
const PANEL_GLASS_TOP = '#B31A1D23';
const PANEL_GLASS_BOTTOM = '#991A1D23';
/** 深色底定界描边（白 20%；深底必须靠亮边才有玻璃厚度感）。 */
const PANEL_GLASS_RIM = '#33FFFFFF';
/**
 * 面板文字（586 起**取消三色分级**，只留两级）。
 *
 * - PANEL_TEXT：正文一律纯白（选项行不再用强调色）；
 * - PANEL_TEXT_DIM：说明/占位白 70%。
 *
 * PANEL_TEXT_DIMER 保留为别名（历史调用点仍在用），值与 DIM 同级，
 * 避免同一面板里出现三种灰度。
 */
const PANEL_TEXT = '#FFFFFF';
const PANEL_TEXT_DIM = '#B3FFFFFF';
const PANEL_TEXT_DIMER = PANEL_TEXT_DIM;
/** 深色底分隔线（白 12%）。 */
const PANEL_DIVIDER = '#1FFFFFFF';
/** 深色底选中行底（accent@20%）。 */
const SEL_BG = '#336366F1';

// ── 播放器弹层统一排版（586，三端逐值对齐）──
// 标题 15/w600、正文 14/w500、说明 12/w500。Flutter 侧同名常量在
// `GlassConfig.playerPanel*Size`，安卓在 `NPTheme.PANEL_*`。
/** 面板标题 15 / w600。 */
const PANEL_TITLE_SIZE = 15;
const PANEL_TITLE_WEIGHT = 600;
/** 面板正文 14 / w500。 */
const PANEL_BODY_SIZE = 14;
const PANEL_BODY_WEIGHT = 500;
/** 说明/占位 12 / w500。 */
const PANEL_CAPTION_SIZE = 12;
const PANEL_CAPTION_WEIGHT = 500;

/** 面板着色（照抄 GlassConfig.panelTint = 0x1F1A1D23）。 */
const PANEL_TINT = '#1F1A1D23';
/** 液态玻璃：背景模糊半径 / 饱和度（对齐 Flutter GlassConfig blurSigma=20、saturation=1.6）。 */
const GLASS_BLUR_RADIUS = 20;
const GLASS_SATURATION = 1.6;
/** 顶部高光带（菲涅尔近似）与内缘暗描边。 */
const GLASS_HIGHLIGHT_TOP = '#B3FFFFFF';
const GLASS_INNER_RIM = '#33000000';
/** 常规面板圆角（Dart radiusPanel=16）。 */
const PANEL_RADIUS = 16;
/** 选集贴边（Flutter fullBleed）：仅左侧圆角 16。 */
const FULLBLEED_RADIUS: BorderRadiuses = { topLeft: 16, bottomLeft: 16, topRight: 0, bottomRight: 0 };
/** 常规面板外边距（Flutter selectorPanelBox：right 12 / top 48 / bottom 116）。 */
const PANEL_MARGIN: Margin = { right: 12 };
/** 常规面板上下避让（Flutter selectorPanelBox：top=safeTop+48 / bottom=116+safeBottom）。 */
const PANEL_PAD_TOP = 48;
const PANEL_PAD_BOTTOM = 116;
/** 选集贴边：无外边距。 */
const FULLBLEED_MARGIN: Margin = { right: 0 };
const FULLBLEED_PAD: Padding = { top: 0, bottom: 0 };
/** rim 边框（照抄 GlassConfig.rimColor 近似）。 */
const RIM_COLOR = '#33FFFFFF';

@Component
export struct NativePlayerPanel {
  @Prop panelType: string = '';
  @Prop revision: number = 0;
  /**
   * 底部避让高度（vp，597）。
   *
   * 竖屏房间模式下资源面板占底部 280vp（Flutter `Column(Expanded, SizedBox
   * 280))`）——本面板挂在根 Stack（全屏）上，若不避让，右侧浮层会伸到
   * 资源面板区域、遮罩也会盖住面板（真机「弹出面板不在视频区内」）。
   * 横屏/非房间传 0。
   */
  @Prop bottomInset: number = 0;
  /** 选集列表滚动控制器（打开时定位当前集）。 */
  private episodeScroller: Scroller = new Scroller();
  /** 片头片尾二次确认上下文（'' = 无，'intro' / 'outro' = 待确认）。 */
  @State confirmKind: string = '';
  /** 显示调节重建纪元（恢复默认 → 滑杆回位，见 DisplayContent 注释）。 */
  @State resetEpoch: number = 0;
  /** 确认来自长按手势（完成后关面板，对齐 Flutter dialog 关闭即结束）。 */
  private confirmFromGesture: boolean = false;

  private host: HimiMpvNativeHost = HimiMpvNativeHost.getInstance();

  aboutToAppear(): void {
    // 长按标记遇旧标记直开确认（对齐 Flutter `_onSegmentMarkSelected`）：
    // 取走宿主预设的 kind 直进确认模式。
    const kind = this.host.consumeSegmentConfirmKind();
    if (kind.length > 0) {
      this.confirmKind = kind;
      this.confirmFromGesture = true;
    }
  }

  /** 确认收尾：手势来源直接关面板；面板行视图来源回到行视图。 */
  private finishConfirm(): void {
    this.confirmKind = '';
    if (this.confirmFromGesture) {
      this.confirmFromGesture = false;
      this.close();
    }
  }

  private state(): NativePlayerUiState {
    return this.host.state;
  }

  private close(): void {
    this.host.closePanel();
  }

  /** 音轨列表（type=audio）。 */
  private audioTracks(): NativeTrackUi[] {
    return this.state().tracks.filter((t: NativeTrackUi): boolean => t.type === 'audio');
  }

  /** 字幕列表（type=sub）。 */
  private subtitleTracks(): NativeTrackUi[] {
    return this.state().tracks.filter((t: NativeTrackUi): boolean => t.type === 'sub');
  }

  /** 轨道显示名：Emby label（displayInfo）优先，回退 title/lang，兜底「轨 N」。 */
  private trackLabel(t: NativeTrackUi): string {
    if (t.label.length > 0) return t.label;
    if (t.title.length > 0) return t.title;
    if (t.lang.length > 0) return t.lang;
    return `轨 ${t.id}`;
  }

  build() {
    // 【对齐语义】片头片尾卡居中，其余面板一律贴右（对齐安卓侧面板）。
    // 上一轮用 .align(Alignment.End) 定位不生效（Column-in-Stack），面板被
    // Stack 默认居中（真机截图回归）——必须用 alignContent。
    Stack({
      alignContent: this.panelType === 'segment' ? Alignment.Center : Alignment.End,
    }) {
      // ── 遮罩垫底：点屏幕其他区域关闭（Flutter 面板不带遮罩，此处保留
      //    交互兜底；对齐安卓 panelScrim 的 setOnClickListener(close)）──
      // 关键：面板容器**不得 width('100%')**——全宽容器会把遮罩整块盖住，
      // 点空白处到不了遮罩，面板只能靠返回键收回（真机回归）。容器宽 =
      // 面板宽，屏幕其余区域直接落在遮罩上。
      Column()
        .width('100%')
        .height('100%')
        .onClick((): void => {
          this.close();
        });

      // ── 片头片尾：居中玻璃卡（照抄 SegmentMarkPanel，非右侧浮层）──
      if (this.panelType === 'segment') {
        this.SegmentCard();
      } else {
        // 右侧浮层拉伸全高（Flutter Positioned(top,bottom) 语义）：
        // 常规面板上避顶栏 48 / 下避控制条 116；选集面板贴边（fullBleed）。
        // 容器宽 = 面板宽（42% 钳 260~320），不铺满全屏（见上方遮罩注释）。
        //
        // 【再次点击控件即收回】本容器全高、无点击处理时会吞掉被面板覆盖的
        // 顶/底栏控件区点击（右侧控件全在 42% 宽区域内）→「再点按钮没反应」。
        // 加 onClick(close)：点控件区/空白外侧都收回（对齐安卓 panelScrim
        // 全覆盖语义：面板开着点任何非面板区都关）。面板自身空白由 SidePanel/
        // SegmentCard 的空点击吸收，不会误关。
        Column() {
          this.SidePanel();
        }
        .width('42%')
        .constraintSize({ minWidth: 260, maxWidth: 320 })
        .height('100%')
        .padding(this.panelType === 'episode'
          ? FULLBLEED_PAD
          : {
            top: PANEL_PAD_TOP + HimiMpvNativeHost.getInstance().safeAreaTop,
            bottom: PANEL_PAD_BOTTOM + HimiMpvNativeHost.getInstance().safeAreaBottom,
          })
        .margin(this.panelType === 'episode' ? FULLBLEED_MARGIN : PANEL_MARGIN)
        .onClick((): void => {
          this.close();
        });
      }
    }
    .width('100%')
    .height('100%')
    // 597：竖屏房间模式把可用区收窄到视频区（见 bottomInset 注释）。
    .padding({ bottom: this.bottomInset })
  }

  /** 右侧玻璃浮层（除片头片尾外的全部面板）。 */
  @Builder
  SidePanel() {
    Column() {
      // 标题（586 统一排版：15 / w600，左对齐，padding h16）
      Text(this.titleText())
        .fontSize(PANEL_TITLE_SIZE)
        .fontWeight(PANEL_TITLE_WEIGHT)
        .fontColor(PANEL_TEXT)
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 4 })
        .textAlign(TextAlign.Start);

      // 内容区（按类型）
      if (this.panelType === 'speed') {
        this.SpeedContent();
      } else if (this.panelType === 'audio') {
        this.TrackContent(this.audioTracks(), this.state().selectedAudioId, false);
      } else if (this.panelType === 'subtitle') {
        this.SubtitleContent();
      } else if (this.panelType === 'episode') {
        this.EpisodeContent();
      } else if (this.panelType === 'version') {
        this.VersionContent();
      } else if (this.panelType === 'kernel') {
        this.KernelContent();
      } else if (this.panelType === 'display') {
        this.DisplayContent();
      } else if (this.panelType === 'decode') {
        this.DecodeContent();
      }
    }
    // 宽 42%（钳 260~320）与上下避让移到外层容器（见 build()）：面板容器
    // 不铺满全屏，遮罩才收得到「点外关闭」。
    .width('100%')
    .layoutWeight(1)
    // 深色磨砂（587）：竖向渐变（顶部提亮 → 基色 → 底部略透）+ 亮描边定界。
    // 【保留 backgroundEffect】鸿蒙的 backgroundEffect 是**节点级实时**
    // backdrop blur（GPU 合成阶段做，60fps、零回读、零跳帧），与 Flutter
    // 的 BackdropFilter / MDK 弹层同源能力 → 深色半透之下仍能看到视频
    // 流动，观感最佳。安卓侧无对应 API（只能回读采样，会一帧一帧跳），
    // 故安卓为纯深色渐变；两端在 65% 深底上观感接近。
    .backgroundEffect({ radius: GLASS_BLUR_RADIUS, saturation: GLASS_SATURATION })
    .linearGradient({
      angle: 180,
      colors: [[PANEL_GLASS_TOP, 0], [PANEL_GLASS_BASE, 0.5], [PANEL_GLASS_BOTTOM, 1]],
    })
    .border({ width: 1, color: PANEL_GLASS_RIM })
    // 选集面板贴边（右侧圆角放平，与 Flutter BorderRadius.horizontal(left) 一致）。
    .borderRadius(this.panelType === 'episode' ? FULLBLEED_RADIUS : PANEL_RADIUS)
    .clip(true)
    .animation({ duration: 180, curve: Curve.EaseOut })
    // 【空点击吸收】点面板自身空白（标题/行间隙）不透传到遮罩关面板——
    // 只有点面板**外面**才关闭（对齐安卓 panelScrim 语义）。选项行等
    // 子控件的 onClick 优先，空 onClick 只兜住面板背景。
    .onClick((): void => {
    });
  }

  /**
   * 片头片尾居中玻璃卡（360 宽、圆角 18）。
   *
   * 已有标记时点行进入**原生**二次确认（更新当前位置 / 清除 / 取消）——
   * Flutter `showDialog` 在原生双窗之上不可见，必须在原生层实现。
   * 确认态由 @State 驱动，确认后回落。
   */
  @Builder
  SegmentCard() {
    Column() {
      Text(this.confirmKind.length > 0
        ? (this.confirmKind === 'intro' ? '片头已设置' : '片尾已设置')
        : '片头片尾')
        .fontSize(PANEL_TITLE_SIZE)
        .fontWeight(PANEL_TITLE_WEIGHT)
        .fontColor(PANEL_TEXT)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 6 });

      if (this.confirmKind.length > 0) {
        Text(`当前标记：${this.existingMarkText(this.confirmKind)}\n要用当前位置更新，还是清除？`)
          .fontSize(PANEL_CAPTION_SIZE)
          .fontWeight(PANEL_CAPTION_WEIGHT)
          .fontColor(PANEL_TEXT_DIM)
          .width('100%')
          .padding({ left: 16, right: 16, top: 0, bottom: 10 });

        Row() {
          Blank();
          Text('取消')
            .fontSize(PANEL_BODY_SIZE)
            .fontWeight(PANEL_BODY_WEIGHT)
            .fontColor(SEL_COLOR)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => {
              this.finishConfirm();
            });
          Text('清除')
            .fontSize(PANEL_BODY_SIZE)
            .fontWeight(PANEL_BODY_WEIGHT)
            .fontColor(SEL_COLOR)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => {
              this.host.optimisticClearSegmentMark(this.confirmKind);
              this.finishConfirm();
            });
          Text('更新')
            .fontSize(PANEL_BODY_SIZE)
            .fontWeight(PANEL_BODY_WEIGHT)
            .fontColor(SEL_COLOR)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => {
              // 二次确认「更新」也走范围校验（588）：不关卡片，提示原因。
              const kind: string = this.confirmKind;
              const reject = segmentMarkReject(
                kind, this.host.positionNowMs(), this.state().durationMs);
              if (reject !== null) {
                // 子窗口内必须走当前 UIContext 的 PromptAction，
                // 否则 toast 会落到主窗口（原生播放 UI 在子窗口）。
                this.getUIContext().getPromptAction().showToast({
                  message: reject,
                  duration: 1500,
                });
                return;
              }
              this.host.optimisticSetSegmentMark(kind);
              this.finishConfirm();
            });
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 0, bottom: 12 })
        .justifyContent(FlexAlign.End);
      } else {
        this.SegmentRow(0xE5BD, '片头', this.markHint('intro'), 'intro');
        this.SegmentRow(0xE5BE, '片尾', this.markHint('outro'), 'outro');
      }
    }
    .width(360)
    // 深色磨砂（与侧栏同款）：实时 backdrop blur + 深色竖向渐变 + 亮描边。
    .backgroundEffect({ radius: GLASS_BLUR_RADIUS, saturation: GLASS_SATURATION })
    .linearGradient({
      angle: 180,
      colors: [[PANEL_GLASS_TOP, 0], [PANEL_GLASS_BASE, 0.5], [PANEL_GLASS_BOTTOM, 1]],
    })
    .border({ width: 1, color: PANEL_GLASS_RIM })
    .borderRadius(18)
    .clip(true)
    .alignItems(HorizontalAlign.Start)
    // 【空点击吸收】点卡片自身空白不透传到遮罩关面板（同 SidePanel）。
    .onClick((): void => {
    });
  }

  /** 片头片尾单行（icon 22 / 标题 14 / 提示 11 / chevron 18）。 */
  @Builder
  SegmentRow(icon: number, title: string, hint: string, kind: string) {
    Row() {
      Text(String.fromCodePoint(icon))
        .fontFamily(NativePlayerIcons.FONT_FAMILY)
        .fontSize(22)
        .fontColor(PANEL_TEXT)
        .width(22);

      Column() {
        Text(title)
          .fontSize(PANEL_BODY_SIZE)
          .fontWeight(PANEL_BODY_WEIGHT)
          .fontColor(PANEL_TEXT)
          .width('100%');
        Text(hint)
          .fontSize(PANEL_CAPTION_SIZE)
          .fontWeight(PANEL_CAPTION_WEIGHT)
          .fontColor(PANEL_TEXT_DIM)
          .width('100%');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 });

      Text(String.fromCodePoint(0xE15F))
        .fontFamily(NativePlayerIcons.FONT_FAMILY)
        .fontSize(18)
        .fontColor(PANEL_TEXT_DIM)
        .width(18);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      // 无标记：直接以当前位置标记；有标记：进入二次确认。
      if (this.hasMark(kind)) {
        this.confirmKind = kind;
      } else {
        this.host.optimisticSetSegmentMark(kind);
      }
    });
  }

  /** 已有标记文本（无则「无」）。 */
  private existingMarkText(kind: string): string {
    const s = this.state();
    const ms: number | null = kind === 'intro' ? s.segmentIntroEndMs : s.segmentOutroStartMs;
    return ms === null ? '无' : formatPlayerTime(ms);
  }

  /** 是否已有该类标记。 */
  private hasMark(kind: string): boolean {
    const s = this.state();
    return kind === 'intro' ? s.segmentIntroEndMs !== null : s.segmentOutroStartMs !== null;
  }

  /** 行提示文本：已标记显示时间，否则提示可标记。 */
  private markHint(kind: string): string {
    return this.hasMark(kind)
      ? `已标记 ${this.existingMarkText(kind)}`
      : '点击以当前位置标记';
  }

  private titleText(): string {
    if (this.panelType === 'speed') {
      return '倍速';
    } else if (this.panelType === 'audio') {
      return '音轨';
    } else if (this.panelType === 'subtitle') {
      return '字幕';
    } else if (this.panelType === 'episode') {
      return '选集';
    } else if (this.panelType === 'version') {
      return '线路';
    } else if (this.panelType === 'kernel') {
      return '播放内核';
    } else if (this.panelType === 'display') {
      return '显示调节';
    } else if (this.panelType === 'decode') {
      return '解码模式';
    }
    return '设置';
  }

  /** 倍速：纵向列表（照抄 Flutter SpeedMenuPanel 的 ListView，非网格）。 */
  @Builder
  SpeedContent() {
    List() {
      ForEach(SPEED_STEPS, (v: number) => {
        ListItem() {
          Row() {
            this.OptionLabel(`${v}x`, Math.abs(this.state().speed - v) < 0.01);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.host.optimisticSetSpeed(v);
            this.close();
          });
        }
      }, (v: number): string => `${v}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: PANEL_DIVIDER });
  }

  /** 轨道列表（音轨/字幕共用）。 */
  @Builder
  TrackContent(tracks: NativeTrackUi[], selectedId: number, allowOff: boolean) {
    List() {
      if (allowOff) {
        ListItem() {
          Row() {
            // 对齐 Flutter SubtitleMenuPanel：「关闭字幕」。
            this.OptionLabel('关闭字幕', selectedId === 0);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.host.optimisticSelectSubtitle(0);
            this.close();
          });
        }
      }
      ForEach(tracks, (t: NativeTrackUi) => {
        ListItem() {
          Row() {
            this.OptionLabel(this.trackLabel(t), t.selected);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            if (this.panelType === 'audio') {
              this.host.optimisticSelectAudio(t.id);
              this.close();
            } else {
              this.host.optimisticSelectSubtitle(t.id);
              this.close();
            }
          });
        }
      }, (t: NativeTrackUi): string => `${t.type}-${t.id}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: PANEL_DIVIDER });
  }

  /** 字幕面板：字幕轨列表 + 关闭项。 */
  @Builder
  SubtitleContent() {
    this.TrackContent(this.subtitleTracks(), this.state().selectedSubtitleId, true);
  }

  /**
   * 播放内核面板（587 完全对齐 Flutter `PlayerKernelPanel`）。
   *
   * 行内容：单行「短名 · 说明」14/w500 + 右侧 accent 对勾；列表底部
   * 分隔线 + 一行说明「切换仅影响当前播放，不改变默认引擎；下一集沿用
   * 当前内核」。
   *
   * 旧实现是双行堆叠（短名一行、说明一行）且没有底部说明——与 Flutter
   * 行高/内容都不一致，切内核时观感突变。
   */
  @Builder
  KernelContent() {
    List() {
      ForEach(this.state().engineOptions, (opt: NativeEngineOptionUi) => {
        ListItem() {
          Row() {
            Text(opt.description.length > 0
              ? `${opt.label} · ${opt.description}`
              : opt.label)
              .fontSize(PANEL_BODY_SIZE)
              .fontWeight(PANEL_BODY_WEIGHT)
              .fontColor(PANEL_TEXT)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(opt.label === this.state().engineLabel ? '✓' : '')
              .fontSize(18)
              .fontColor(SEL_COLOR)
              .width(18)
              .textAlign(TextAlign.Center);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.host.optimisticSwitchEngine(opt.id);
            this.close();
          });
        }
      }, (opt: NativeEngineOptionUi): string => opt.id);

      // 底部说明（对齐 Flutter PlayerKernelPanel：行后 1px 分隔线 + 说明）。
      // 不放进 Column 尾部固定：Flutter 里它是列表最后一项，随内容滚动。
      ListItem() {
        Text('切换仅影响当前播放，不改变默认引擎；下一集沿用当前内核')
          .fontSize(PANEL_CAPTION_SIZE)
          .fontWeight(PANEL_CAPTION_WEIGHT)
          .fontColor(PANEL_TEXT_DIM)
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 });
      }
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: PANEL_DIVIDER });
  }

  /** 显示调节面板：字幕 3 行 + 弹幕 3 行（与 Flutter DisplayAdjustPanel 一致）。 */
  @Builder
  DisplayContent() {
    // 整段外包 ForEach(key=resetEpoch)：点「恢复默认」→ key 变 → 节点重建
    // → 滑杆全部回位。拖动不改 epoch → 不打断拖动（数值文本走自驱子组件）。
    ForEach([this.resetEpoch], (epoch: number): void => {
      List() {
        ForEach(DISPLAY_SLIDERS, (spec: DisplaySliderSpec, idx: number) => {
          ListItem() {
            Column() {
              if (idx === 0 || idx === 3) {
                Text(idx === 0 ? '字幕' : '弹幕')
                  .fontSize(PANEL_CAPTION_SIZE)
                  .fontWeight(PANEL_CAPTION_WEIGHT)
                  .fontColor(PANEL_TEXT)
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 4 });
              }
              Row() {
                Text(spec.label)
                  .fontSize(PANEL_BODY_SIZE)
                  .fontWeight(PANEL_BODY_WEIGHT)
                  .fontColor(PANEL_TEXT)
                  .width(44);
                // 玻璃滑杆（完全复刻 Flutter glassSliderTheme，见 GlassSlider.ets）。
                GlassSlider({
                  value: this.sliderValue(spec.key),
                  min: spec.min,
                  max: spec.max,
                  step: spec.step,
                  // 587 面板改深色磨砂：滑杆走深色档（白系轨道），浅色档
                  // 的黑系轨道在深底上几乎不可见。
                  onChange: (v: number): void => {
                    this.host.adjustDisplay(spec.key, v);
                  },
                })
                  .layoutWeight(1);
                DisplayValueText({ keyName: spec.key });
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center);
              // 段末「恢复默认」：字幕段（idx 2 后）/ 弹幕段（idx 5 后），与
              // Flutter DisplayAdjustPanel 的两段 reset 行一致。
              if (idx === 2 || idx === 5) {
                this.DisplayResetRow(idx === 2 ? 'subtitle' : 'danmaku');
              }
            }
            .width('100%');
          }
        }, (spec: DisplaySliderSpec, idx: number): string => `${spec.key}-${idx}`);
      }
      .width('100%')
      .layoutWeight(1);
    }, (epoch: number): string => `display-${epoch}`);
  }

  /** 当前滑杆值（按 key 从宿主状态读取）。 */
  private sliderValue(key: string): number {
    const s = this.state();
    if (key === 'subtitleScale') {
      return s.subtitleScale;
    }
    if (key === 'subtitleMarginY') {
      return s.subtitleMarginY;
    }
    if (key === 'subtitleDelayMs') {
      return s.subtitleDelayMs;
    }
    if (key === 'danmakuSpeed') {
      return s.danmakuSpeed;
    }
    if (key === 'danmakuFontSize') {
      return s.danmakuFontSize;
    }
    if (key === 'danmakuOpacity') {
      return s.danmakuOpacity;
    }
    return 0;
  }

  /**
   * 显示调节「恢复默认」行（对齐 Flutter DisplayAdjustPanel：字幕段/
   * 弹幕段各一行，全部处于默认值时高亮选中态）。
   *
   * 点击经 `adjustDisplay` 逐键回写——Dart 侧 `_applyNativeAdjustDisplay`
   * 与滑杆同一处理路径（含落盘），与安卓恢复默认同语义。
   */
  @Builder
  DisplayResetRow(kind: string) {
    Text('恢复默认')
      .fontSize(PANEL_BODY_SIZE)
      .fontWeight(PANEL_BODY_WEIGHT)
      .fontColor(this.displayAtDefaults(kind) ? SEL_COLOR : PANEL_TEXT)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      .onClick((): void => {
        if (kind === 'subtitle') {
          this.host.adjustDisplay('subtitleScale', DEFAULT_SUBTITLE_SCALE);
          this.host.adjustDisplay('subtitleMarginY', DEFAULT_SUBTITLE_MARGIN_Y);
          this.host.adjustDisplay('subtitleDelayMs', DEFAULT_SUBTITLE_DELAY_MS);
        } else {
          this.host.adjustDisplay('danmakuSpeed', DEFAULT_DANMAKU_SPEED);
          this.host.adjustDisplay('danmakuFontSize', DEFAULT_DANMAKU_FONT_SIZE);
          this.host.adjustDisplay('danmakuOpacity', DEFAULT_DANMAKU_OPACITY);
        }
        // 节点重建 → 滑杆回位（key=resetEpoch，见 DisplayContent）。
        this.resetEpoch = this.resetEpoch + 1;
      });
  }

  /** 该段是否全部处于默认值（「恢复默认」行高亮条件，与 Flutter selected 同语义）。 */
  private displayAtDefaults(kind: string): boolean {
    const s = this.state();
    if (kind === 'subtitle') {
      return Math.abs(s.subtitleScale - DEFAULT_SUBTITLE_SCALE) < 0.001
        && s.subtitleMarginY === DEFAULT_SUBTITLE_MARGIN_Y
        && s.subtitleDelayMs === DEFAULT_SUBTITLE_DELAY_MS;
    }
    return Math.abs(s.danmakuSpeed - DEFAULT_DANMAKU_SPEED) < 0.001
      && Math.abs(s.danmakuFontSize - DEFAULT_DANMAKU_FONT_SIZE) < 0.001
      && Math.abs(s.danmakuOpacity - DEFAULT_DANMAKU_OPACITY) < 0.001;
  }

  /**
   * 解码模式面板（587 完全对齐 Flutter `DecodeModePanel`）。
   *
   * 结构：标题行（`解码模式` 15/w600 + 当前档位 14/w500）→ 0.5 分隔线 →
   * 三档单选（单选圈 16 + 档位名 14/w500 + 说明 12/w500 白 70%），选中行
   * 铺 accent 20% 底。
   *
   * 旧实现差异：档位名 auto 写作「自动」（Flutter 是「智能」）、**没有
   * 说明文字**、且把当前档位另起一行「当前：xxx」——切 MDK↔MPV 时面板
   * 观感突变。现与 Flutter / 安卓三端逐字一致。
   *
   * 588：单选圈由「●/○」文本改为图标字体（`radio_button_checked/
   * unchecked`），行底 0.5vp 分隔线含末行（List.divider 画不到末行）。
   */
  @Builder
  DecodeContent() {
    Column() {
      // 标题行：`解码模式` 15/w600 + 当前档位 14/w500（正文一律纯白，
      // 档位不用强调色——强调只由单选圈/行底表达）。
      Row() {
        Text('解码模式')
          .fontSize(PANEL_TITLE_SIZE)
          .fontWeight(PANEL_TITLE_WEIGHT)
          .fontColor(PANEL_TEXT);
        Text(decodeModeLabel(this.state().decodeMode))
          .fontSize(PANEL_BODY_SIZE)
          .fontWeight(PANEL_BODY_WEIGHT)
          .fontColor(PANEL_TEXT)
          .margin({ left: 8 });
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })
      .alignItems(VerticalAlign.Center);

      Divider()
        .strokeWidth(0.5)
        .color(PANEL_DIVIDER)
        .width('100%');

      List() {
        ForEach(DECODE_MODES, (mode: string) => {
          ListItem() {
            Row() {
              // 单选圈用图标字体（0xE503/0xE504），不再用「●/○」文本：
              // 文本字形随系统字体变化、与 Flutter/安卓的 Material 单选圈
              // 观感不同（真机对比「复选框要和 MDK 一样」）。
              Text(String.fromCodePoint(this.state().decodeMode === mode
                ? NativePlayerIcons.ICON_RADIO_BUTTON_CHECKED
                : NativePlayerIcons.ICON_RADIO_BUTTON_UNCHECKED))
                .fontFamily(NativePlayerIcons.FONT_FAMILY)
                .fontSize(16)
                .fontColor(this.state().decodeMode === mode ? SEL_COLOR : PANEL_TEXT_DIM)
                // 只锁宽（16vp，与 Flutter Icon(size:16) 同）：锁高会把
                // 16sp 字形的行盒（≈22vp）裁掉上下边（单选圈变缺口）。
                .width(16)
                .textAlign(TextAlign.Center);
              Column() {
                Text(decodeModeLabel(mode))
                  .fontSize(PANEL_BODY_SIZE)
                  .fontWeight(PANEL_BODY_WEIGHT)
                  .fontColor(PANEL_TEXT)
                  .width('100%');
                Text(decodeModeDesc(mode))
                  .fontSize(PANEL_CAPTION_SIZE)
                  .fontWeight(PANEL_CAPTION_WEIGHT)
                  .fontColor(PANEL_TEXT_DIM)
                  .width('100%');
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 8 });
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor(this.state().decodeMode === mode ? SEL_BG : Color.Transparent)
            // 每行底边通栏 0.5vp（含末行，与 Flutter Border bottom 一致；
            // List.divider 只在行之间画、末行没有）。
            .border({ width: { bottom: 0.5 }, color: PANEL_DIVIDER })
            .onClick((): void => {
              this.host.optimisticSetDecodeMode(mode);
              this.close();
            });
          }
        }, (mode: string): string => mode);
      }
      .width('100%')
      .layoutWeight(1);
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start);
  }

  /** 选集列表。 */
  @Builder
  EpisodeContent() {
    List({ scroller: this.episodeScroller }) {
      ForEach(this.state().episodes, (e: NativeEpisodeUi) => {
        ListItem() {
          Column() {
            // 封面：16:9 + 选中主色 2dp 描边 + 右上对勾徽标
            //（对齐 Flutter EpisodeSelectPanel 卡片）。
            Stack({ alignContent: Alignment.TopEnd }) {
              if (e.poster.length > 0) {
                Image(e.poster)
                  .width('100%')
                  .aspectRatio(16 / 9)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
              } else {
                Column()
                  .width('100%')
                  .aspectRatio(16 / 9)
                  .backgroundColor('#1A1D23')
                  .borderRadius(8);
              }
              if (e.index === this.state().currentEpisodeIndex) {
                Text(String.fromCodePoint(NativePlayerIcons.ICON_CHECK))
                  .fontFamily(NativePlayerIcons.FONT_FAMILY)
                  .fontSize(14)
                  .fontColor('#6366F1')
                  .width(22)
                  .height(22)
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#8C000000')
                  .borderRadius(11)
                  .margin({ top: 6, right: 6 });
              }
            }
            .width('100%')
            .border({
              width: e.index === this.state().currentEpisodeIndex ? 2 : 0,
              color: e.index === this.state().currentEpisodeIndex ? '#6366F1' : Color.Transparent,
              radius: 10,
            });

            // 586 统一排版：正文一律纯白 + w500（选中只靠封面描边与
            // 对勾表达；旧实现未选中行用次色、选中行 Medium，同面板两种灰度）。
            Text(e.cardTitle())
              .fontSize(PANEL_BODY_SIZE)
              .fontColor(PANEL_TEXT)
              .fontWeight(PANEL_BODY_WEIGHT)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 6 });
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 10 })
          .onClick((): void => {
            this.host.optimisticSelectEpisode(e.index);
            this.close();
          });
        }
      }, (e: NativeEpisodeUi): string => `${e.index}`);
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: 8 })
    // 打开时把当前集滚进视口（与 Flutter EpisodeSelectPanel initState 一致）。
    .onAppear((): void => {
      const idx = this.state().currentEpisodeIndex;
      if (idx > 0) {
        this.episodeScroller.scrollToIndex(Math.min(idx, this.state().episodes.length - 1));
      }
    });
  }

  /** 版本/线路列表。 */
  @Builder
  VersionContent() {
    List() {
      ForEach(this.state().versions, (s: NativeVersionUi) => {
        ListItem() {
          Row() {
            this.OptionLabel(s.title.length > 0 ? s.title : `线路 ${s.index + 1}`,
              s.index === this.state().currentVersionIndex);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.host.optimisticSelectVersion(s.index);
            this.close();
          });
        }
      }, (s: NativeVersionUi): string => `${s.index}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: PANEL_DIVIDER });
  }

  /**
   * 选项行内容（对齐 Flutter SideOptionRow）：文字左对齐、右侧对勾占
   * 18px 槽位（未选中也占位，保证各行对齐）。
   *
   * 586 统一排版：正文一律纯白 + w500，选中态只靠行底强调色与对勾表达
   * ——旧实现选中行改强调色 + Medium，同一面板出现两种字色/字重。
   */
  @Builder
  OptionLabel(label: string, selected: boolean) {
    Text(label)
      .fontSize(PANEL_BODY_SIZE)
      .fontWeight(PANEL_BODY_WEIGHT)
      .fontColor(PANEL_TEXT)
      .layoutWeight(1)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis });
    Text(selected ? '✓' : '')
      .fontSize(18)
      .fontColor(SEL_COLOR)
      .width(18)
      .textAlign(TextAlign.Center);
  }
}
