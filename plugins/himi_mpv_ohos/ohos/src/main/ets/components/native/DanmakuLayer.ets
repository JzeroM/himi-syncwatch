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
 * 实现：ArkUI Canvas 无每帧重绘接口，用 30fps @State 帧排布数组驱动
 * Text.position 位移（状态驱动重排，弹幕为小节点树，开销可控）。
 *
 * 【关键】排布必须落进 **@State items** 并在 build() 里**直接**读取——
 * 旧实现在 build() 里现算排布（把帧状态藏进方法调用），不进 ArkUI
 * 细粒度依赖集，帧计数再怎么翻 build() 也不重跑 → 弹幕永远停在首帧
 * （真机回归：弹幕不显示）。滚动项 key 带量化 x，保证两种 ForEach
 * 复用语义下都逐帧重排。
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
  /** 当前帧的活跃弹幕排布（30fps 重写；build() 直读本数组 = 逐帧刷新）。 */
  @State items: DanmakuFrameItem[] = [];

  /** 容器实际尺寸（onAreaChange 喂入，排布按真实宽高）。 */
  @State areaW: number = 1200;
  @State areaH: number = 700;

  private timer: number = -1;
  /**
   * 当前播放位置 = 宿主插值时钟 `positionNowMs()`（快照 + 墙钟×倍速）——
   * 与 Flutter `DanmakuOverlay._nowPosition`（`_lastPosition + (_elapsed -
   * _alignElapsed)`）同构：两次快照之间**严格按墙钟匀速线性外推**。
   *
   * 【非匀速根因】旧实现在外推上叠了「漂移 10%/帧牵引」——每帧注入额外
   * 位移、速度随漂移量变化 → 弹幕忽快忽慢（真机回归）。修复 = 删除一切
   * 速度修正项：seek 由快照突变自然重对齐（同 Flutter 重锚），暂停由
   * positionNowMs 冻结（同 Flutter playing=false 停 Ticker）。
   */
  private posOf(): number {
    return HimiMpvNativeHost.getInstance().positionNowMs();
  }
  /**
   * 行号绑定表（`timeMs:text` → lane）——**一旦分配不再变**。
   *
   * 【弹幕往上移动根因】旧实现对集合全量重分配行号：最老条目穿屏移除后
   * 重算，后续条目全部拿到更小行号 → 整屏上移一行。行号必须绑定条目
   * 生命周期（与 Flutter DanmakuTimeline 的 item.row 同语义）。
   * -1 = 轨道满被丢弃（不渲染，同 Flutter `if (row < 0) continue`）。
   */
  private laneOf: Map<string, number> = new Map<string, number>();
  /** 各行「轨道空闲起始时刻」（滚动/顶部/底部三组独立，冲突模型同 Flutter）。 */
  private scrollRowAvail: number[] = [];
  private topRowAvail: number[] = [];
  private bottomRowAvail: number[] = [];

  aboutToAppear(): void {
    // 60fps 帧驱动（16ms ≈ vsync，对齐 Flutter Ticker）：重写 @State 排布
    // 数组 → build() 直读 → Text 逐帧位移。
    this.timer = setInterval((): void => {
      this.items = this.frameItems();
    }, 16);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** 飞行中弹幕缓存：窗口滑出后仍画到穿屏结束（防"滚到一半消失"）。 */
  private flying: NativeDanmakuUi[] = [];

  /** CJK≈1em / ASCII≈0.55em 宽度近似（与 DanmakuTimeline 估算一致）。 */
  private estimateWidth(text: string, fontSize: number): number {
    let w = 0;
    for (const ch of text) {
      w += (ch.codePointAt(0) ?? 0) > 0x2E80 ? fontSize : fontSize * 0.55;
    }
    return w;
  }

  /**
   * 增量行分配：只给**新条目**分配行号，laneOf 绑定生命周期不再变
   *（模型完全复刻 Flutter DanmakuTimeline._pickRow）：
   * - 滚动：占行到「完全入屏」+150ms（同速不追尾，textW/(W+textW) 为
   *   完全入屏进度）；顶/底：占行 FIXED_MS+150ms；
   * - **轨道满 → 丢弃（lane=-1，不渲染）**——旧实现溢出回 0 行叠加，
   *   多条挤同一行 = 弹幕重叠（真机回归）。
   *
   * 行数取弹幕设置（真机回归：旧实现硬编码 16/6，设置页行数改动失效）：
   * 滚动 = 用户值为上限、按屏高自适应铺满（同 Flutter
   * `autoRows.clamp(1, config.scrollRows)`）；顶/底 = 用户值（夹到屏高
   * 容量内）。
   */
  private assignLanes(items: NativeDanmakuUi[], speed: number, screenWidth: number,
    screenH: number, fontSize: number): void {
    const s = HimiMpvNativeHost.getInstance().state;
    const rowH = fontSize + ROW_GAP;
    const autoRows = Math.floor((screenH - 2 * EDGE_PAD) / rowH);
    const maxScrollRows = Math.max(1, Math.min(s.danmakuScrollRows, autoRows));
    const topRows = Math.max(1, Math.min(s.danmakuTopRows, autoRows));
    const bottomRows = Math.max(1, Math.min(s.danmakuBottomRows, autoRows));
    if (this.scrollRowAvail.length !== maxScrollRows) {
      this.scrollRowAvail = new Array<number>(maxScrollRows).fill(0);
      // 589：行容量变化（转屏/改行数设置）→ 旧行号可能越界，整表重排。
      this.laneOf.clear();
    }
    if (this.topRowAvail.length !== topRows) {
      this.topRowAvail = new Array<number>(topRows).fill(0);
      this.laneOf.clear();
    }
    if (this.bottomRowAvail.length !== bottomRows) {
      this.bottomRowAvail = new Array<number>(bottomRows).fill(0);
      this.laneOf.clear();
    }
    const travelMs = SCROLL_BASE_MS / speed;
    for (const item of items) {
      const key = `${item.timeMs}:${item.text}`;
      if (this.laneOf.has(key)) {
        continue; // 已分配（含 -1 丢弃）：不重分配（防上移/跳行）。
      }
      const textW = this.estimateWidth(item.text, fontSize);
      const isFixed = item.mode === 'top' || item.mode === 'bottom';
      const occupancy = isFixed
        ? FIXED_MS + 150
        : travelMs * (textW <= 0 ? 0 : textW / (screenWidth + textW)) + 150;
      const avail = item.mode === 'top' ? this.topRowAvail
        : item.mode === 'bottom' ? this.bottomRowAvail
        : this.scrollRowAvail;
      let lane = -1;
      for (let r = 0; r < avail.length; r++) {
        if (avail[r] <= item.timeMs) {
          avail[r] = item.timeMs + occupancy;
          lane = r;
          break;
        }
      }
      // lane = -1 → 轨道满丢弃（对齐 Flutter `if (row < 0) continue`）。
      this.laneOf.set(key, lane);
    }
  }

  /**
   * 飞行中缓存维护：窗口新条目并入（timeMs+text 去重），穿屏结束才移除。
   *
   * 【防"莫名消失"】数据源窗口随播放滑动，旧实现窗口一移出就不再渲染——
   * 滚动弹幕滚到一半被拦腰斩断。缓存保证已入屏的弹幕一定画到穿屏结束；
   * 窗口抖动（推送延迟）也不影响在飞条目。
   */
  private syncFlying(all: NativeDanmakuUi[], pos: number, travelMs: number): NativeDanmakuUi[] {
    for (const item of all) {
      let seen = false;
      for (const f of this.flying) {
        if (f.timeMs === item.timeMs && f.text === item.text) {
          seen = true;
          break;
        }
      }
      if (!seen) {
        this.flying.push(item);
      }
    }
    const alive: NativeDanmakuUi[] = [];
    for (const f of this.flying) {
      const elapsed = pos - f.timeMs;
      const life = (f.mode === 'top' || f.mode === 'bottom') ? FIXED_MS : travelMs;
      // 穿屏结束 +500ms 余量才移除（elapsed 边界抖动不误剔）。
      if (elapsed > life + 500) {
        // 生命周期结束：释放行号绑定（防 laneOf 无限增长）。
        this.laneOf.delete(`${f.timeMs}:${f.text}`);
        continue;
      }
      alive.push(f);
    }
    this.flying = alive;
    return alive;
  }

  /** 当前帧的活跃弹幕排布。 */
  private frameItems(): DanmakuFrameItem[] {
    const s = HimiMpvNativeHost.getInstance().state;
    const out: DanmakuFrameItem[] = [];
    if (!s.danmakuEnabled || s.isRoom) {
      this.flying = [];
      return out;
    }
    const pos = this.posOf();
    const speed = Math.min(4, Math.max(0.25, s.danmakuSpeed));
    const fontSize = BASE_FONT_SIZE * Math.min(4, Math.max(0.25, s.danmakuFontSize));
    const rowH = fontSize + ROW_GAP;
    const screenWidth = this.areaW;
    const screenH = this.areaH;
    const travelMs = SCROLL_BASE_MS / speed;
    // 飞行缓存 ∪ 当前窗口，按 timeMs 排序（新条目按时间序增量分配行号）。
    const all = this.syncFlying(s.danmakuItems, pos, travelMs);
    all.sort((a: NativeDanmakuUi, b: NativeDanmakuUi): number => a.timeMs - b.timeMs);
    this.assignLanes(all, speed, screenWidth, screenH, fontSize);
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      const elapsed = pos - item.timeMs;
      const lane = this.laneOf.get(`${item.timeMs}:${item.text}`);
      if (lane === undefined || lane < 0) {
        continue; // 轨道满丢弃（lane=-1）/尚未分配。
      }
      if (item.mode === 'top' || item.mode === 'bottom') {
        if (elapsed < 0 || elapsed > FIXED_MS) {
          continue;
        }
        const textW = this.estimateWidth(item.text, fontSize);
        const x = (screenWidth - textW) / 2;
        const y = item.mode === 'top'
          ? EDGE_PAD + lane * rowH
          : screenH - EDGE_PAD - (lane + 1) * rowH;
        // 驻留弹幕位置固定：key 不含坐标。
        out.push(new DanmakuFrameItem(`${i}:${item.timeMs}:f`, item.text, x, y, item.color, fontSize));
      } else {
        if (elapsed < 0 || elapsed > travelMs) {
          continue;
        }
        const progress = Math.min(1, Math.max(0, elapsed / travelMs));
        const textW = this.estimateWidth(item.text, fontSize);
        const x = screenWidth - progress * (screenWidth + textW);
        const y = EDGE_PAD + lane * rowH;
        // key 带量化 x（1vp 档）：滚动弹幕逐帧位移，key 不变的复用语义下
        // 位置属性不会刷新——key 随位置变保证两种 ForEach 语义都重排。
        // 1vp 粒度 ≈ 每帧都有位移（100vp/s ≫ 60fps），消除台阶感。
        out.push(new DanmakuFrameItem(
          `${i}:${item.timeMs}:${Math.round(x)}`, item.text, x, y, item.color, fontSize));
      }
    }
    return out;
  }

  build() {
    Stack() {
      ForEach(this.items, (it: DanmakuFrameItem) => {
        Text(it.text)
          .fontSize(it.fontSize)
          // 观感照抄 Flutter DanmakuOverlay 的 TextStyle：w500 + 黑 54%
          // blur3 描影（深色背景下可读性一致）。
          .fontWeight(500)
          .shadow({ radius: 3, color: '#8A000000', offsetX: 0, offsetY: 0 })
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
