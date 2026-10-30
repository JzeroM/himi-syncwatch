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
} from './HimiMpvNativeHost';

/** 倍速档位（与 Flutter speedOptions 完全一致）。 */
const SPEED_STEPS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

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

      // ── 右侧玻璃浮层（照抄 SelectorSidePanel 定位：贴右 12 / 宽 320）──
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
    .width('100%')
    .height('100%')
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
