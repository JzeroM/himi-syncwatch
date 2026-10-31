/**
 * 原生弹幕渲染层（鸿蒙）。
 *
 * 原生 UI 下 Flutter 弹幕层随视频区一齐退场，弹幕改由本层渲染（真机回归
 * 「弹幕开关点了没反应」）。语义镜像 Flutter DanmakuOverlay/DanmakuTimeline：
 * - 滚动：穿屏 8s÷speed，x = width - progress×(width+textW)；
 * - 顶/底：驻留 4s，水平居中；字号 25vp×倍率、行距 6、边距 8；
 * - 行冲突：滚动弹幕占行直到「前沿越过左缘」+0.15s（同速不追尾）；
 * - 位置纯推导（elapsed = 播放位置 - timeMs），seek 自愈、暂停冻结。
 *
 * 实现：ArkUI Canvas 无每帧重绘接口，用 30fps @State 帧计数驱动
 * Text.position 位移（状态驱动重排，弹幕为小节点树，开销可控）。
 */

import {
  HimiMpvNativeHost,
  NativeDanmakuUi,
} from './HimiMpvNativeHost';

/** 单帧弹幕排布项（ArkTS 禁止对象字面量作 ForEach 泛型，用类承载）。 */
class DanmakuFrameItem {
  key: string = '';
  text: string = '';
  x: number = 0;
  y: number = 0;
  color: string = '#FFFFFF';
  fontSize: number = 20;

  constructor(key: string, text: string, x: number, y: number, color: string, fontSize: number) {
    this.key = key;
    this.text = text;
    this.x = x;
    this.y = y;
    this.color = color;
    this.fontSize = fontSize;
  }
}

/** 滚动穿屏基准时长（ms÷speed）。 */
const SCROLL_BASE_MS = 8000;
/** 顶/底驻留时长（ms）。 */
const FIXED_MS = 4000;
/** 基准字号（vp，Flutter baseFontSize=25）。 */
const BASE_FONT_SIZE = 25;
/** 行间距（vp）。 */
const ROW_GAP = 6;
/** 顶/底安全边距（vp）。 */
const EDGE_PAD = 8;

@Component
export struct DanmakuLayer {
  @Prop revision: number = 0;
  @State frame: number = 0;

  /** 容器实际尺寸（onAreaChange 喂入，排布按真实宽高）。 */
  @State areaW: number = 1200;
  @State areaH: number = 700;

  private timer: number = -1;
  /** 位置锚点（host 推送时的播放位置 + 墙钟），帧间自插值。 */
  private anchorPosMs: number = 0;
  private anchorWallMs: number = 0;
  private anchorRevision: number = -1;
  /** 弹幕窗口的行分配缓存（窗口变化时重建）。 */
  private laneKey: string = '';
  private lanes: number[] = [];

  aboutToAppear(): void {
    this.syncAnchor();
    // 30fps 帧驱动：Text 位移按帧重算（Flutter Ticker 的原生等价物）。
    this.timer = setInterval((): void => {
      this.frame++;
    }, 33);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** 同步位置锚点（host 状态推送到达时）。 */
  private syncAnchor(): void {
    const s = HimiMpvNativeHost.getInstance().state;
    this.anchorPosMs = s.positionMs;
    this.anchorWallMs = Date.now();
    this.anchorRevision = this.revision;
  }

  /** 当前播放位置（锚点 + 墙钟增量；暂停冻结）。 */
  private positionMs(): number {
    const s = HimiMpvNativeHost.getInstance().state;
    if (this.anchorRevision !== this.revision) {
      this.syncAnchor();
    }
    if (s.paused) {
      return this.anchorPosMs;
    }
    return this.anchorPosMs + (Date.now() - this.anchorWallMs);
  }

  /** CJK≈1em / ASCII≈0.55em 宽度近似（与 DanmakuTimeline 估算一致）。 */
  private estimateWidth(text: string, fontSize: number): number {
    let w = 0;
    for (const ch of text) {
      w += (ch.codePointAt(0) ?? 0) > 0x2E80 ? fontSize : fontSize * 0.55;
    }
    return w;
  }

  /** 行分配（窗口变化时重建；冲突模型同 DanmakuTimeline）。 */
  private assignLanes(items: NativeDanmakuUi[], speed: number, screenWidth: number): void {
    const key = `${items.length}:${items.length > 0 ? items[0].timeMs : 0}:${speed}:${screenWidth}`;
    if (key === this.laneKey) {
      return;
    }
    this.laneKey = key;
    this.lanes = [];
    const fontSize = BASE_FONT_SIZE;
    const rowH = fontSize + ROW_GAP;
    const maxScrollRows = Math.min(16, Math.max(4, Math.floor(screenWidth > 0 ? 900 / rowH : 12)));
    const scrollFreeAt: number[] = new Array<number>(maxScrollRows).fill(0);
    let topRow = 0;
    let bottomRow = 0;
    for (const item of items) {
      if (item.mode === 'top') {
        this.lanes.push(topRow);
        topRow = (topRow + 1) % Math.min(maxScrollRows, 6);
      } else if (item.mode === 'bottom') {
        this.lanes.push(bottomRow);
        bottomRow = (bottomRow + 1) % Math.min(maxScrollRows, 6);
      } else {
        const travelMs = SCROLL_BASE_MS / speed;
        const textW = this.estimateWidth(item.text, fontSize);
        const frontExitMs = item.timeMs + travelMs * (screenWidth / (screenWidth + textW));
        let lane = 0;
        while (lane < maxScrollRows && scrollFreeAt[lane] + 150 > item.timeMs) {
          lane++;
        }
        if (lane >= maxScrollRows) {
          lane = 0;
        }
        this.lanes.push(lane);
        scrollFreeAt[lane] = frontExitMs;
      }
    }
  }

  /** 当前帧的活跃弹幕排布。 */
  private frameItems(): DanmakuFrameItem[] {
    const s = HimiMpvNativeHost.getInstance().state;
    const out: DanmakuFrameItem[] = [];
    if (!s.danmakuEnabled || s.isRoom || s.danmakuItems.length === 0) {
      return out;
    }
    const pos = this.positionMs();
    const speed = Math.min(4, Math.max(0.25, s.danmakuSpeed));
    const fontSize = BASE_FONT_SIZE * Math.min(4, Math.max(0.25, s.danmakuFontSize));
    const rowH = fontSize + ROW_GAP;
    const screenWidth = this.areaW;
    const screenH = this.areaH;
    this.assignLanes(s.danmakuItems, speed, screenWidth);
    const travelMs = SCROLL_BASE_MS / speed;
    for (let i = 0; i < s.danmakuItems.length; i++) {
      const item = s.danmakuItems[i];
      const elapsed = pos - item.timeMs;
      const lane = this.lanes.length > i ? this.lanes[i] : 0;
      if (item.mode === 'top' || item.mode === 'bottom') {
        if (elapsed < 0 || elapsed > FIXED_MS) {
          continue;
        }
        const textW = this.estimateWidth(item.text, fontSize);
        const x = (screenWidth - textW) / 2;
        const y = item.mode === 'top'
          ? EDGE_PAD + lane * rowH
          : screenH - EDGE_PAD - (lane + 1) * rowH;
        out.push(new DanmakuFrameItem(`${i}:${item.timeMs}`, item.text, x, y, item.color, fontSize));
      } else {
        if (elapsed < 0 || elapsed > travelMs) {
          continue;
        }
        const progress = Math.min(1, Math.max(0, elapsed / travelMs));
        const textW = this.estimateWidth(item.text, fontSize);
        const x = screenWidth - progress * (screenWidth + textW);
        const y = EDGE_PAD + lane * rowH;
        out.push(new DanmakuFrameItem(`${i}:${item.timeMs}`, item.text, x, y, item.color, fontSize));
      }
    }
    return out;
  }

  build() {
    Stack() {
      ForEach(this.frameItems(), (it: DanmakuFrameItem) => {
        Text(it.text)
          .fontSize(it.fontSize)
          .fontColor(it.color)
          .opacity(Math.min(1, Math.max(0, HimiMpvNativeHost.getInstance().state.danmakuOpacity)))
          .position({ x: it.x, y: it.y })
      }, (it: DanmakuFrameItem): string => it.key);
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .enabled(false)
    .onAreaChange((_old: Area, area: Area): void => {
      this.areaW = area.width as number;
      this.areaH = area.height as number;
    });
  }
}
