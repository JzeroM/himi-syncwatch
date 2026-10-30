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

/** 解码模式中文标签。 */
function decodeModeLabel(mode: string): string {
  if (mode === 'auto') {
    return '自动';
  }
  if (mode === 'hw') {
    return '硬解';
  }
  if (mode === 'sw') {
    return '软解';
  }
  return mode;
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

/** 显示调节滑杆行规格（字幕 3 行 + 弹幕 3 行，与 Flutter 显示调节一致）。 */
const DISPLAY_SLIDERS: DisplaySliderSpec[] = [
  new DisplaySliderSpec('subtitleScale', '大小', 0.5, 3.0, 0.05),
  new DisplaySliderSpec('subtitleMarginY', '位置', 0, 200, 2),
  new DisplaySliderSpec('subtitleDelayMs', '延迟', -5000, 5000, 100),
  new DisplaySliderSpec('danmakuSpeed', '速度', 0.5, 2.0, 0.05),
  new DisplaySliderSpec('danmakuFontSize', '大小', 0.5, 2.0, 0.05),
  new DisplaySliderSpec('danmakuOpacity', '透明度', 0.1, 1.0, 0.05),
];

/** 选中主色（照抄 Flutter Color(0xFF6366F1)）。 */
const SEL_COLOR = '#6366F1';
/** 面板着色（照抄 GlassConfig.panelTint = 0x1F1A1D23）。 */
const PANEL_TINT = '#1F1A1D23';
/** rim 边框（照抄 GlassConfig.rimColor 近似）。 */
const RIM_COLOR = '#33FFFFFF';

@Component
export struct NativePlayerPanel {
  @Prop panelType: string = '';
  @Prop revision: number = 0;
  /** 片头片尾二次确认上下文（'' = 无，'intro' / 'outro' = 待确认）。 */
  @State confirmKind: string = '';

  private host: HimiMpvNativeHost = HimiMpvNativeHost.getInstance();

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

  /** 轨道显示名：title 或 lang，兜底「轨 N」。 */
  private trackLabel(t: NativeTrackUi): string {
    if (t.title.length > 0) return t.title;
    if (t.lang.length > 0) return t.lang;
    return `轨 ${t.id}`;
  }

  build() {
    Stack() {
      // ── 遮罩：点外关闭（Flutter 面板不带遮罩，此处保留交互兜底）──
      Column()
        .width('100%')
        .height('100%')
        .gesture(TapGesture().onAction((): void => {
          this.close();
        }));

      // ── 片头片尾：居中玻璃卡（照抄 SegmentMarkPanel，非右侧浮层）──
      if (this.panelType === 'segment') {
        this.SegmentCard();
      } else {
        this.SidePanel();
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 右侧玻璃浮层（除片头片尾外的全部面板）。 */
  @Builder
  SidePanel() {
    Column() {
      // 标题（照抄：fontSize 15 加粗，左对齐，padding h16）
      Text(this.titleText())
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
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
    .width(320)
    .constraintSize({ maxHeight: '72%' })
    .backgroundColor(PANEL_TINT)
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: RIM_COLOR })
    .borderRadius(16)
    .clip(true)
    // 贴右；上避顶栏（48），下避控制条（116），与 Flutter selectorPanelBox 一致。
    .position({ x: '100%', y: 0 })
    .markAnchor({ x: '100%', y: '0%' })
    .margin({ right: 12, top: 48, bottom: 116 })
    .animation({ duration: 180, curve: Curve.EaseOut });
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
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 6 });

      if (this.confirmKind.length > 0) {
        Text(`当前标记：${this.existingMarkText(this.confirmKind)}\n要用当前位置更新，还是清除？`)
          .fontSize(12)
          .fontColor('#8AFFFFFF')
          .width('100%')
          .padding({ left: 16, right: 16, top: 0, bottom: 10 });

        Row() {
          Blank();
          Text('取消')
            .fontSize(13)
            .fontColor(SEL_COLOR)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => {
              this.confirmKind = '';
            });
          Text('清除')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(SEL_COLOR)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => {
              this.host.optimisticClearSegmentMark(this.confirmKind);
              this.confirmKind = '';
            });
          Text('更新')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(SEL_COLOR)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick((): void => {
              this.host.optimisticSetSegmentMark(this.confirmKind);
              this.confirmKind = '';
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
    .backgroundColor(PANEL_TINT)
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: RIM_COLOR })
    .borderRadius(18)
    .clip(true)
    .alignItems(HorizontalAlign.Start);
  }

  /** 片头片尾单行（icon 22 / 标题 14 / 提示 11 / chevron 18）。 */
  @Builder
  SegmentRow(icon: number, title: string, hint: string, kind: string) {
    Row() {
      Text(String.fromCodePoint(icon))
        .fontFamily(NativePlayerIcons.FONT_FAMILY)
        .fontSize(22)
        .fontColor(Color.White)
        .width(22);

      Column() {
        Text(title)
          .fontSize(14)
          .fontColor(Color.White)
          .width('100%');
        Text(hint)
          .fontSize(11)
          .fontColor('#8AFFFFFF')
          .width('100%');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 });

      Text(String.fromCodePoint(0xE15F))
        .fontFamily(NativePlayerIcons.FONT_FAMILY)
        .fontSize(18)
        .fontColor('#62FFFFFF')
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
          });
        }
      }, (v: number): string => `${v}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#1AFFFFFF' });
  }

  /** 轨道列表（音轨/字幕共用）。 */
  @Builder
  TrackContent(tracks: NativeTrackUi[], selectedId: number, allowOff: boolean) {
    List() {
      if (allowOff) {
        ListItem() {
          Row() {
            this.OptionLabel('关闭', selectedId === 0);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.host.optimisticSelectSubtitle(0);
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
            } else {
              this.host.optimisticSelectSubtitle(t.id);
            }
          });
        }
      }, (t: NativeTrackUi): string => `${t.type}-${t.id}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#1AFFFFFF' });
  }

  /** 字幕面板：字幕轨列表 + 关闭项。 */
  @Builder
  SubtitleContent() {
    this.TrackContent(this.subtitleTracks(), this.state().selectedSubtitleId, true);
  }

  /** 播放内核面板：短名 + 说明 + 当前项对勾。 */
  @Builder
  KernelContent() {
    List() {
      ForEach(this.state().engineOptions, (opt: NativeEngineOptionUi) => {
        ListItem() {
          Column() {
            Row() {
              Text(opt.label)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
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
            .alignItems(VerticalAlign.Center);

            if (opt.description.length > 0) {
              Text(opt.description)
                .fontSize(11)
                .fontColor('#8AFFFFFF')
                .maxLines(2)
                .margin({ top: 2 });
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .onClick((): void => {
            this.host.optimisticSwitchEngine(opt.id);
            this.close();
          });
        }
      }, (opt: NativeEngineOptionUi): string => opt.id);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#1AFFFFFF' });
  }

  /** 显示调节面板：字幕 3 行 + 弹幕 3 行（与 Flutter DisplayAdjustPanel 一致）。 */
  @Builder
  DisplayContent() {
    List() {
      ForEach(DISPLAY_SLIDERS, (spec: DisplaySliderSpec, idx: number) => {
        ListItem() {
          Column() {
            if (idx === 0 || idx === 3) {
              Text(idx === 0 ? '字幕' : '弹幕')
                .fontSize(11)
                .fontColor('#62FFFFFF')
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 4 });
            }
            Row() {
              Text(spec.label)
                .fontSize(12)
                .fontColor(Color.White)
                .width(44);
              Slider({
                value: this.sliderValue(spec.key),
                min: spec.min,
                max: spec.max,
                step: spec.step,
              })
                .layoutWeight(1)
                .selectedColor(SEL_COLOR)
                .trackColor('#33FFFFFF')
                .onChange((v: number): void => {
                  this.host.adjustDisplay(spec.key, v);
                });
              Text(this.sliderValue(spec.key).toFixed(2))
                .fontSize(12)
                .fontColor('#B3FFFFFF')
                .width(48)
                .textAlign(TextAlign.End);
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .alignItems(VerticalAlign.Center);
          }
          .width('100%');
        }
      }, (spec: DisplaySliderSpec, idx: number): string => `${spec.key}-${idx}`);
    }
    .width('100%')
    .layoutWeight(1)
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

  /** 解码模式面板：标题 + 当前值 + 3 行单选。 */
  @Builder
  DecodeContent() {
    Column() {
      Text('当前：' + decodeModeLabel(this.state().decodeMode))
        .fontSize(12)
        .fontColor('#A5B4FC')
        .width('100%')
        .padding({ left: 16, right: 16, top: 0, bottom: 6 });
      List() {
        ForEach(DECODE_MODES, (mode: string) => {
          ListItem() {
            Row() {
              Text(this.state().decodeMode === mode ? '●' : '○')
                .fontSize(16)
                .fontColor(this.state().decodeMode === mode ? SEL_COLOR : '#8AFFFFFF')
                .width(20);
              Text(decodeModeLabel(mode))
                .fontSize(13)
                .fontColor(this.state().decodeMode === mode ? SEL_COLOR : Color.White)
                .layoutWeight(1)
                .margin({ left: 8 });
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .alignItems(VerticalAlign.Center)
            .onClick((): void => {
              this.host.optimisticSetDecodeMode(mode);
              this.close();
            });
          }
        }, (mode: string): string => mode);
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: '#1AFFFFFF' });
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start);
  }

  /** 选集列表。 */
  @Builder
  EpisodeContent() {
    List() {
      ForEach(this.state().episodes, (e: NativeEpisodeUi) => {
        ListItem() {
          Row() {
            this.OptionLabel(e.title.length > 0 ? e.title : `第 ${e.index + 1} 集`,
              e.index === this.state().currentEpisodeIndex);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.host.optimisticSelectEpisode(e.index);
          });
        }
      }, (e: NativeEpisodeUi): string => `${e.index}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#1AFFFFFF' });
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
          });
        }
      }, (s: NativeVersionUi): string => `${s.index}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#1AFFFFFF' });
  }

  /**
   * 选项行内容（照抄 Flutter SideOptionRow）：文字左对齐、选中主色加粗、
   * 右侧对勾占 18px 槽位（未选中也占位，保证各行对齐）。
   */
  @Builder
  OptionLabel(label: string, selected: boolean) {
    Text(label)
      .fontSize(14)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(selected ? SEL_COLOR : Color.White)
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
