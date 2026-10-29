/**
 * Phase 2 二级面板（计划书 §5.2）。
 *
 * 单一模态容器 + 按 [panelType] 渲染对应内容：倍速 / 音轨 / 字幕 / 选集 /
 * 版本。所有交互经 [HimiMpvNativeHost] 的 optimistic* 方法乐观更新 + 回传
 * Dart；面板数据来自宿主权威快照的 tracks/episodes/versions。
 *
 * 结构：半透明遮罩（点外关闭）+ 底部圆角面板（标题 + 列表）。
 */

import {
  HimiMpvNativeHost,
  NativePlayerUiState,
  NativeTrackUi,
  NativeEpisodeUi,
  NativeVersionUi,
} from './HimiMpvNativeHost';

/** 倍速档位（与 Flutter 侧常用档一致）。 */
const SPEED_STEPS: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];

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
      // ── 遮罩：点外关闭 ──
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .gesture(TapGesture().onAction((): void => {
          this.close();
        }));

      // ── 面板主体（底部圆角）──
      Column() {
        // 标题行：面板名 + 关闭
        Row() {
          Text(this.titleText())
            .fontSize(16)
            .fontColor(Color.White)
            .layoutWeight(1);
          Text('✕')
            .fontSize(18)
            .fontColor('#CCFFFFFF')
            .padding(8)
            .onClick((): void => {
              this.close();
            });
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 8 });

        Divider().color('#33FFFFFF').margin({ left: 16, right: 16 });

        // 内容区（按类型）
        if (this.panelType === 'speed') {
          this.SpeedContent();
        } else if (this.panelType === 'audio') {
          this.TrackContent(this.audioTracks(), this.state().selectedAudioId, true);
        } else if (this.panelType === 'subtitle') {
          this.SubtitleContent();
        } else if (this.panelType === 'episode') {
          this.EpisodeContent();
        } else if (this.panelType === 'version') {
          this.VersionContent();
        }
      }
      .width('100%')
      .backgroundColor('#E61C1C1E')
      .borderRadius({ topLeft: 16, topRight: 16 })
      .constraintSize({ maxHeight: '60%' })
      .position({ x: 0, y: '100%' })
      .markAnchor({ x: '0%', y: '100%' })
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

  /** 倍速：档位网格。 */
  @Builder
  SpeedContent() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(SPEED_STEPS, (v: number) => {
        Text(`${v}x`)
          .fontSize(15)
          .fontColor(Math.abs(this.state().speed - v) < 0.01 ? '#4C8DFF' : Color.White)
          .width('25%')
          .padding({ top: 14, bottom: 14 })
          .textAlign(TextAlign.Center)
          .backgroundColor(Math.abs(this.state().speed - v) < 0.01 ? '#334C8DFF' : '#1AFFFFFF')
          .borderRadius(8)
          .margin(4)
          .onClick((): void => {
            this.host.optimisticSetSpeed(v);
          });
      }, (v: number): string => `${v}`);
    }
    .width('100%')
    .padding(12);
  }

  /** 轨道列表（音轨/字幕共用；[allowOff] 时首项为「关闭」）。 */
  @Builder
  TrackContent(tracks: NativeTrackUi[], selectedId: number, allowOff: boolean) {
    List() {
      if (allowOff) {
        ListItem() {
          this.TrackRow('关闭', selectedId === 0, (): void => {
            this.host.optimisticSelectSubtitle(0);
          });
        }
      }
      ForEach(tracks, (t: NativeTrackUi) => {
        ListItem() {
          this.TrackRow(this.trackLabel(t), t.selected, (): void => {
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
    .divider({ strokeWidth: 0.5, color: '#22FFFFFF' });
  }

  /** 字幕面板：音轨列表 + 关闭项。 */
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
          this.TrackRow(e.title.length > 0 ? e.title : `第 ${e.index + 1} 集`,
            e.index === this.state().currentEpisodeIndex, (): void => {
              this.host.optimisticSelectEpisode(e.index);
            });
        }
      }, (e: NativeEpisodeUi): string => `${e.index}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#22FFFFFF' });
  }

  /** 版本/线路列表。 */
  @Builder
  VersionContent() {
    List() {
      ForEach(this.state().versions, (s: NativeVersionUi) => {
        ListItem() {
          this.TrackRow(s.title.length > 0 ? s.title : `线路 ${s.index + 1}`,
            s.index === this.state().currentVersionIndex, (): void => {
              this.host.optimisticSelectVersion(s.index);
            });
        }
      }, (s: NativeVersionUi): string => `${s.index}`);
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#22FFFFFF' });
  }

  /** 通用行：标签 + 选中标记 + 点击。 */
  @Builder
  TrackRow(label: string, selected: boolean, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(selected ? '#4C8DFF' : Color.White)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      if (selected) {
        Text('✓')
          .fontSize(16)
          .fontColor('#4C8DFF');
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 13, bottom: 13 })
    .onClick(onTap);
  }
}
