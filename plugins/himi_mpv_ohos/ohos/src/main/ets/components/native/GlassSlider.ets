/**
 * 玻璃质感滑杆——**完全复刻 Flutter `glassSliderTheme`**
 *（GlassSliderTrackShape + GlassSliderThumbShape，见
 * lib/screens/player/widgets/glass_slider_theme.dart）。
 *
 * 轨道：6dp 圆角，未播段三段垂直渐变（白 22% 提亮 → 本色 → 黑 18% 压暗），
 * 顶部高光线并入渐变首档（Flutter 独立画 h*0.18 高光，观感等价）；
 * 已播段 accent 三段渐变 + 外发光（shadow ≈ Flutter blur6 30% 光晕）。
 *
 * 拇指：28dp ACCENT_SOFT 光晕圆 + 16dp 三段玻璃渐变圆体（白 38% 提亮 →
 * accent → 黑 16% 压暗）。ArkUI Slider 的 blockColor 无法双层/渐变 →
 * 整体自绘（声明式容器 + 渐变），交互用 onTouch（touches[0].x 绝对坐标，
 * 点击定位 + 拖动，无手势竞技场冲突）。
 */

/** 未播轨（white@0.16 = #29FFFFFF，色阶 = Flutter Color.lerp 精确换算）。 */
const TRACK_TOP = '#58FFFFFF'; // lerp(white16, white, 0.22)
const TRACK_BASE = '#29FFFFFF'; // white@0.16
const TRACK_BOT = '#22D1D1D1'; // lerp(white16, black, 0.18)
/** 已播段（accent 三段）。 */
const ACTIVE_TOP = '#9294F5'; // lerp(accent, white, 0.30)
const ACTIVE_MID = '#6366F1';
const ACTIVE_BOT = '#575AD4'; // lerp(accent, black, 0.12)
/** 拇指圆体（accent 三段）。 */
const THUMB_TOP = '#9EA0F6'; // lerp(accent, white, 0.38)
const THUMB_MID = '#6366F1';
const THUMB_BOT = '#5356CA'; // lerp(accent, black, 0.16)
/** 光晕（accent 30% ≈ 安卓 ACCENT_SOFT）。 */
const GLOW = '#4D6366F1';
/** 轨道高。 */
const TRACK_H = 6;
/**
 * 浅色档（浅底容器内的滑杆）：未播轨黑系，已播 accent，拇指纯白。
 * 深色档的白色渐变在浅底上几乎不可见（真机回归「面板滑杆看不清」）。
 */
const TRACK_TOP_LIGHT = '#2E000000'; // 黑 18%
const TRACK_BASE_LIGHT = '#1F000000'; // 黑 12%
const TRACK_BOT_LIGHT = '#14000000'; // 黑 8%
const THUMB_TOP_LIGHT = '#FFFFFF';
const THUMB_MID_LIGHT = '#F5F5F7';
const THUMB_BOT_LIGHT = '#E4E4E8';
const GLOW_LIGHT = '#406366F1';
/** 拇指直径 / 光晕直径。 */
const THUMB_D = 16;
const GLOW_D = 28;

@Component
export struct GlassSlider {
  @Prop @Watch('onValueChanged') value: number = 0;
  @Prop min: number = 0;
  @Prop max: number = 1;
  @Prop step: number = 0.01;
  /** 拖动中回调（按 step 吸附后的值）。 */
  onChange: (v: number) => void = (v: number): void => {};
  /** 抬手提交回调（seek 等一次性动作用）。 */
  onCommit: (v: number) => void = (v: number): void => {};
  /** 浅色档（浅底容器内使用）：轨道黑系 + 纯白拇指。587 弹层改深色后
   *  默认走深色档；此档保留供未来的浅底场景。 */
  @Prop light: boolean = false;

  /** 当前位置（0..1；触点驱动，value 变化经 @Watch 同步）。 */
  @State ratio: number = 0;
  /**
   * 轨道宽——**必须 @State**（真机回归：旧实现是普通字段，onAreaChange
   * 写入不触发重绘，拇指 x 恒按 0 计算 = 永远贴左，既不跟随进度也不在
   * 默认值位置）。
   */
  @State trackW: number = 0;

  aboutToAppear(): void {
    this.ratio = this.toRatio(this.value);
  }

  /**
   * 未播轨三段渐变（深色档白系 / 浅色档黑系）。
   *
   * 抽成方法而非内联三元：ArkTS 对 `linearGradient.colors` 的
   * `Array<[ResourceColor, number]>` 类型推断在嵌套三元 + 数组字面量下
   * 容易报错（编译期实测），显式返回类型最稳。
   */
  private trackColors(): Array<[string, number]> {
    if (this.light) {
      return [[TRACK_TOP_LIGHT, 0.0], [TRACK_BASE_LIGHT, 0.35], [TRACK_BOT_LIGHT, 1.0]];
    }
    return [[TRACK_TOP, 0.0], [TRACK_BASE, 0.35], [TRACK_BOT, 1.0]];
  }

  /** 拇指圆体三段渐变（浅色档纯白 / 深色档 accent）。 */
  private thumbColors(): Array<[string, number]> {
    if (this.light) {
      return [[THUMB_TOP_LIGHT, 0.0], [THUMB_MID_LIGHT, 0.55], [THUMB_BOT_LIGHT, 1.0]];
    }
    return [[THUMB_TOP, 0.0], [THUMB_MID, 0.55], [THUMB_BOT, 1.0]];
  }

  /** value 变化 → 同步位置（播放推进/外部 seek/恢复默认都走这里）。 */
  onValueChanged(): void {
    this.ratio = this.toRatio(this.value);
  }

  private toRatio(v: number): number {
    const span = this.max - this.min;
    return span > 0 ? Math.max(0, Math.min(1, (v - this.min) / span)) : 0;
  }

  /** 触点 x → 吸附后的值。 */
  private valueAt(x: number): number {
    const raw = this.trackW > 0
      ? Math.max(0, Math.min(1, x / this.trackW))
      : 0;
    const v = this.min + raw * (this.max - this.min);
    const snapped = this.step > 0 ? Math.round(v / this.step) * this.step : v;
    return Math.max(this.min, Math.min(this.max, snapped));
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 层 1：未播轨（三段玻璃渐变，高光并入首档）。
      Row() {
        Row()
          .width('100%')
          .height(TRACK_H)
          .borderRadius(TRACK_H / 2)
          .linearGradient({
            angle: 180,
            colors: this.trackColors(),
          });
      }
      .width('100%')
      .height(GLOW_D)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None);

      // 层 2：已播段（accent 三段渐变 + 外发光 ≈ Flutter inflate1.5/blur6）。
      Row() {
        Row()
          .width(`${this.ratio * 100}%`)
          .height(TRACK_H)
          .borderRadius(TRACK_H / 2)
          .backgroundColor(ACTIVE_MID)
          .shadow({ radius: 6, color: GLOW, offsetX: 0, offsetY: 0 })
          .linearGradient({
            angle: 180,
            colors: [
              [ACTIVE_TOP, 0.0], [ACTIVE_MID, 0.55], [ACTIVE_BOT, 1.0],
            ],
          });
      }
      .width('100%')
      .height(GLOW_D)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None);

      // 层 3：拇指（28dp 光晕圆 + 16dp 玻璃渐变圆体 + 顶部高光**弧**）。
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(GLOW_D)
          .height(GLOW_D)
          .borderRadius(GLOW_D / 2)
          .backgroundColor(this.light ? GLOW_LIGHT : GLOW);
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width(THUMB_D)
            .height(THUMB_D)
            .borderRadius(THUMB_D / 2)
            .linearGradient({
              angle: 180,
              colors: this.thumbColors(),
            });
          // 顶部高光弧（真弧，照抄 Flutter GlassSliderThumbShape 的 drawArc：
          // 圆心=拇指中心、弧半径 6.4（r−1.6）、扫角 π·0.84、白 75% 描边
          // 1.6）。实现 = 描边圆环 + 下部裁剪：环盒 14.4²、borderRadius 7.2、
          // border 1.6 → 描边中心线恰在 r=6.4；裁剪高度 7.2 使弧端落在
          // ±75.6°（同 Flutter 扫角）+ 圆头余量。旧实现 Path SVG 弧被
          // 组件盒解析偏移（真机：弧偏了）。
          Stack({ alignContent: Alignment.TopStart }) {
            Row()
              .width(14.4)
              .height(14.4)
              .borderRadius(7.2)
              .border({ width: 1.6, color: '#B3FFFFFF' })
              .position({ x: 0.8, y: 0.8 });
          }
          .width(THUMB_D)
          .height(7.2)
          .clip(true)
          // 必须贴拇指顶部（Stack 居中会把弧压到中部）：弧可见段 y∈[0,7.2]
          // = 圆心上方 0.8 处截断，与 Flutter 扫角 π·0.84 近似等价。
          .position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None);
        }
        .width(THUMB_D)
        .height(THUMB_D);
      }
      .width(GLOW_D)
      .height(GLOW_D)
      .hitTestBehavior(HitTestMode.None)
      // 拇指中心 = ratio × trackW（同 Flutter：thumbCenter 沿轨道全宽移动）。
      .position({ x: this.ratio * this.trackW - GLOW_D / 2, y: 0 });
    }
    .width('100%')
    .height(GLOW_D)
    .onAreaChange((_old: Area, area: Area): void => {
      this.trackW = area.width as number;
    })
    .onTouch((e: TouchEvent): void => {
      if (e.type === TouchType.Down || e.type === TouchType.Move) {
        const t = e.touches.length > 0 ? e.touches[0]
          : (e.changedTouches.length > 0 ? e.changedTouches[0] : null);
        if (t === null) {
          return;
        }
        const v = this.valueAt(t.x as number);
        this.ratio = this.toRatio(v);
        this.onChange(v);
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.onCommit(this.min + this.ratio * (this.max - this.min));
      }
    });
  }
}
