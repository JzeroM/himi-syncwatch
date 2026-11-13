/**
 * 697：播放调试面板（HarmonyOS 原生 UI）。
 *
 * ## 为什么必须在原生侧重写
 *
 * 鸿蒙原生播放器 UI 是**独立全屏宿主**，Flutter 播放页在其下方已卸载——
 * Flutter 的 `PlaybackDebugPanel` 在这里根本看不到。而 HDR/DV 排查必须
 * 能在真机上直接看参数。
 *
 * ## 与 Flutter / Android / Windows Qt 的关系
 *
 * 四端消费**同一份** `NativePlayerUiState`（Dart 侧 1s 轮询 mpv 属性后
 * 经 MethodChannel 下发），因此显示的数字必然一致。
 *
 * ## 设计
 *
 * - 半透明（alpha 0.72）+ 圆角 + 绿色描边，与 Flutter/Qt 面板同观感
 * - 标题栏可拖动（`PanGesture`，鸿蒙禁止 position 百分比定位，用
 *   `translate` 叠加位移）
 * - 分组可折叠（点击组标题切换）
 * - 状态色：绿=正常、琥珀=可疑、红=异常
 */

import { HimiMpvNativeHost, NativePlayerUiState } from './HimiMpvNativeHost';
import {
  DebugSeverity,
  backendSupportsDv,
  dropSeverity,
  dvToneMappingOk,
  dvProfileText,
  fmtMs,
  isHdrOutput,
  orDash,
} from './DebugPanelFormat';

/** 分组折叠键（用常量而非标题反查：标题是展示文案）。 */
const KEY_PLAYBACK = 'playback';
const KEY_INPUT = 'input';
const KEY_OUTPUT = 'output';
const KEY_DV = 'dv';
const KEY_PIPELINE = 'pipeline';

/** 面板主色（与 Flutter/Qt 的 greenAccent 一致）。 */
const ACCENT_GREEN = '#66FF99';
const LABEL_COLOR = '#61FFFFFF';
const NORMAL_COLOR = '#B3FFFFFF';

/** 单行指标。 */
interface DebugRowSpec {
  label: string;
  value: string;
  severity: string;
}

/** 一个分组（标题 + 行列表 + 是否高亮 + 折叠键）。 */
interface DebugGroupSpec {
  key: string;
  title: string;
  highlighted: boolean;
  rows: DebugRowSpec[];
}

@Component
export struct DebugPanel {
  /**
   * 状态刷新纪元（宿主每次推送快照必变）。
   *
   * 【为什么不用 `@Prop state: NativePlayerUiState`】ArkTS 的 `@Prop`
   * 只支持 string/number/boolean 等基础类型与简单对象，自定义类不做
   * 深观察 → 状态变化不触发重绘（`NativePlayerPanel` 同样用 revision）。
   */
  @Prop revision: number = 0;

  /** 关闭回调（等价于在设置里关掉「播放调试面板」）。 */
  onClose: () => void = () => {};

  /** 宿主单例（状态权威源）。 */
  private host: HimiMpvNativeHost = HimiMpvNativeHost.getInstance();

  private state(): NativePlayerUiState {
    return this.host.state;
  }

  /** 各分组折叠状态。 */
  @State private collapsed: string[] = [];

  /** 拖动位移（鸿蒙禁止 position 百分比定位，用 translate 叠加）。 */
  @State private offsetX: number = 0;
  @State private offsetY: number = 0;

  private isCollapsed(key: string): boolean {
    return this.collapsed.indexOf(key) >= 0;
  }

  private toggle(key: string): void {
    const idx: number = this.collapsed.indexOf(key);
    if (idx >= 0) {
      this.collapsed.splice(idx, 1);
    } else {
      this.collapsed.push(key);
    }
    // ArkTS 需要整体替换数组才触发刷新
    this.collapsed = this.collapsed.slice();
  }

  private severityColor(sev: string): string {
    if (sev === DebugSeverity.GOOD) return '#6EE7A0';
    if (sev === DebugSeverity.WARN) return '#FBBF24';
    if (sev === DebugSeverity.ERROR) return '#F87171';
    return NORMAL_COLOR;
  }

  /** 构建分组规格（数据驱动，UI 只负责渲染）。 */
  private buildGroups(): DebugGroupSpec[] {
    const s: NativePlayerUiState = this.state();
    const groups: DebugGroupSpec[] = [];

    // ── 播放 ──
    const playback: DebugRowSpec[] = [
      {
        label: '状态',
        value: s.paused ? 'PAUSED' : 'PLAYING',
        severity: s.paused ? DebugSeverity.WARN : DebugSeverity.GOOD,
      },
      {
        label: '位置',
        value: `${fmtMs(s.positionMs)} / ${fmtMs(s.durationMs)}`,
        severity: DebugSeverity.NORMAL,
      },
      {
        label: '缓冲',
        value: `${s.bufferedMs}ms`,
        severity: DebugSeverity.NORMAL,
      },
      {
        label: '倍速',
        value: s.speed.toFixed(2),
        severity: DebugSeverity.NORMAL,
      },
      {
        label: '实际帧率',
        value: s.estimatedVfFps > 0 ? s.estimatedVfFps.toFixed(2) : '-',
        severity: DebugSeverity.NORMAL,
      },
      {
        label: '丢帧',
        value: `渲染 ${s.frameDropCount} / 解码 ${s.decoderFrameDropCount}`,
        severity: dropSeverity(s.frameDropCount, s.decoderFrameDropCount),
      },
    ];
    groups.push({
      key: KEY_PLAYBACK,
      title: '播放',
      highlighted: false,
      rows: playback,
    });

    // ── HDR 输入 ──
    const gamma: string = s.videoParamsGamma;
    const hwdec: string = s.hwdecCurrent;
    groups.push({
      key: KEY_INPUT,
      title: 'HDR 输入',
      highlighted: true,
      rows: [
        {
          label: '色彩',
          value: `${orDash(s.videoParamsPrimaries)} / ${orDash(gamma)}`,
          severity: isHdrOutput(gamma) ? DebugSeverity.GOOD : DebugSeverity.NORMAL,
        },
        {
          label: '位深',
          value: `${s.videoParamsBitDepth}bit · ${orDash(s.videoParamsPixelFormat)}`,
          severity: DebugSeverity.NORMAL,
        },
        {
          // mpv 的 sig-peak 是 max_luma/100 的倍数，必须 ×100 才是 nits
          label: '峰值',
          value: s.videoParamsSigPeak > 0
            ? `${Math.round(s.videoParamsSigPeak * 100)} nits`
            : '-',
          severity: DebugSeverity.NORMAL,
        },
        {
          label: '编码',
          value: orDash(s.videoFormat),
          severity: DebugSeverity.NORMAL,
        },
        {
          label: '硬解',
          value: orDash(hwdec),
          severity: (!hwdec || hwdec === 'no')
            ? DebugSeverity.WARN
            : DebugSeverity.GOOD,
        },
      ],
    });

    // ── HDR 输出 ──
    // 【697 真机回归：P5 显示「非 DV 内容」】鸿蒙读不到
    // `current-tracks/video/dolby-vision-profile`（mpv 封装不支持 NODE
    // 子属性访问的部分构建），必须用 Emby 元数据兜底。
    const isDv: boolean = s.doviProfile > 0 || s.dvContent;
    const mappingMode: string =
      s.toneMappingMode.length > 0 ? ` (${s.toneMappingMode})` : '';
    groups.push({
      key: KEY_OUTPUT,
      title: 'HDR 输出',
      highlighted: true,
      rows: [
        {
          label: '路径',
          value: s.hdrOutput ? 'Surface · HDR 直出' : 'Surface · SDR（tone map）',
          severity: s.hdrOutput ? DebugSeverity.GOOD : DebugSeverity.NORMAL,
        },
        {
          label: '目标',
          value: `${orDash(s.targetPrim)} / ${orDash(s.targetTrc)}`,
          severity: isHdrOutput(s.targetTrc)
            ? DebugSeverity.GOOD
            : DebugSeverity.NORMAL,
        },
        {
          label: '映射',
          value: orDash(s.toneMapping) + mappingMode,
          severity: dvToneMappingOk(isDv, s.toneMapping)
            ? DebugSeverity.GOOD
            : DebugSeverity.ERROR,
        },
        {
          label: '峰值计算',
          value: orDash(s.hdrComputePeak),
          severity: DebugSeverity.NORMAL,
        },
      ],
    });

    // ── 杜比视界 ──
    const dvRows: DebugRowSpec[] = [
      {
        label: 'Profile',
        value: s.doviProfile > 0
          ? dvProfileText(s.doviProfile, s.doviLevel)
          : (s.dvContent ? 'DV（Profile 未知 · Emby 元数据）' : dvProfileText(0, 0)),
        severity: DebugSeverity.NORMAL,
      },
    ];
    if (isDv) {
      const supports: boolean = backendSupportsDv(s.gpuContext);
      dvRows.push({
        label: '识别',
        value: s.dvContent ? '已识别为 DV' : '未识别（按普通 HDR 处理）',
        severity: s.dvContent ? DebugSeverity.GOOD : DebugSeverity.ERROR,
      });
      dvRows.push({
        label: '后端',
        value: orDash(s.gpuContext) + (supports ? ' · 支持 DV' : ' · 不支持 DV'),
        severity: supports ? DebugSeverity.GOOD : DebugSeverity.WARN,
      });
      // P5 单层 IPT + 后端不支持 → 画面必偏色
      if (s.doviProfile === 5 && !supports) {
        dvRows.push({
          label: 'P5 风险',
          value: '后端不支持 DV，画面会偏色',
          severity: DebugSeverity.ERROR,
        });
      }
    }
    groups.push({
      key: KEY_DV,
      title: '杜比视界',
      highlighted: true,
      rows: dvRows,
    });

    // ── 渲染管线 ──
    const pipelineRows: DebugRowSpec[] = [
      {
        label: 'vo',
        value: orDash(s.currentVo, s.voConfigured),
        severity: DebugSeverity.NORMAL,
      },
      { label: 'gpu-api', value: orDash(s.gpuApi), severity: DebugSeverity.NORMAL },
      {
        label: 'gpu-context',
        value: orDash(s.gpuContext),
        severity: DebugSeverity.NORMAL,
      },
      {
        label: '输出',
        value: orDash(s.videoOutputActual),
        severity: DebugSeverity.NORMAL,
      },
    ];
    const cw: number = this.host.canvasWidth;
    const ch: number = this.host.canvasHeight;
    if (cw > 0 && ch > 0) {
      pipelineRows.push({
        label: '画布',
        value: `${cw}x${ch}`,
        severity: DebugSeverity.NORMAL,
      });
    }
    if (!s.surfaceAttached) {
      pipelineRows.push({
        label: 'Surface',
        value: '未附着',
        severity: DebugSeverity.ERROR,
      });
    }
    if (s.surfaceError.length > 0) {
      pipelineRows.push({
        label: 'Surface 错误',
        value: s.surfaceError,
        severity: DebugSeverity.ERROR,
      });
    }
    groups.push({
      key: KEY_PIPELINE,
      title: '渲染管线',
      highlighted: false,
      rows: pipelineRows,
    });

    return groups;
  }

  build() {
    // 锁定态隐藏（与顶栏/进度条一致：锁定后只留锁钮）。
    // 必须在 build 里判——宿主每次推送都会重建，单独在锁定分支设隐藏
    // 会被下一次重建覆盖（安卓侧同类 bug 已修）。
    if (!this.state().showDebug || this.state().locked) {
      // 空节点：鸿蒙条件渲染不支持直接返回 null
      Column() {
      }
      .width(0)
      .height(0);
    } else {
      Column() {
        // ── 标题栏（可拖动）──
        Row() {
          Text('☰')
            .fontSize(12)
            .fontColor(ACCENT_GREEN);
          Text('播放调试')
            .fontSize(12)
            .fontColor(ACCENT_GREEN)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 4 });
          Blank();
          Text('✕')
            .fontSize(13)
            .fontColor('#8AFFFFFF')
            .padding({ left: 8, right: 2, top: 2, bottom: 2 })
            .onClick(() => {
              this.onClose();
            });
        }
        .width('100%')
        .height(28)
        .padding({ left: 8, right: 6 })
        .backgroundColor('#1F66FF99')
        .borderRadius({ topLeft: 10, topRight: 10 })
        .gesture(
          PanGesture()
            .onActionUpdate((event: GestureEvent) => {
              this.offsetX += event.offsetX;
              this.offsetY += event.offsetY;
            }),
        );

        // ── 内容区 ──
        Scroll() {
          Column() {
            ForEach(this.buildGroups(), (group: DebugGroupSpec) => {
              // 【必须单一根节点】ArkTS 的 ForEach builder 只允许一个根组件，
              // 兄弟节点会编译报错或静默丢弃 → 用 Column 包住「标题 + 行」。
              Column() {
                // 分组标题（可折叠）
                Row() {
                  Text(this.isCollapsed(group.key) ? '›' : '⌄')
                    .fontSize(11)
                    .fontColor(group.highlighted ? ACCENT_GREEN : LABEL_COLOR);
                  Text(group.title)
                    .fontSize(11)
                    .fontColor(group.highlighted ? ACCENT_GREEN : NORMAL_COLOR)
                    .fontWeight(FontWeight.Bold)
                    .margin({ left: 2 });
                }
                .width('100%')
                .height(22)
                .onClick(() => {
                  this.toggle(group.key);
                });

                // 行（折叠时跳过）
                if (!this.isCollapsed(group.key)) {
                  ForEach(group.rows, (row: DebugRowSpec) => {
                    Row() {
                      Text(row.label)
                        .fontSize(10.5)
                        .fontColor(LABEL_COLOR)
                        .width(66)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis });
                      Text(row.value)
                        .fontSize(10.5)
                        .fontColor(this.severityColor(row.severity))
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis });
                    }
                    .width('100%')
                    .padding({ left: 14, top: 1, bottom: 1 });
                  }, (row: DebugRowSpec) => `${row.label}=${row.value}`);
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start);
            }, (group: DebugGroupSpec) =>
              `${group.key}-${this.isCollapsed(group.key)}-${this.revision}`);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart);
      }
      .width(300)
      .constraintSize({ maxHeight: '78%' })
      .padding({ left: 8, right: 8, bottom: 8 })
      .backgroundColor('#B8000000') // 0.72 半透明
      .borderRadius(10)
      .border({ width: 1, color: '#7366FF99' })
      // 【只用一个定位属性】597 真机回归：`position` + `translate` 叠加会
      // 跑位（两者都改位置，基准互相污染）。拖动位移直接累加进 position。
      .position({ x: 16 + this.offsetX, y: 80 + this.offsetY })
      .zIndex(100);
    }
  }
}
