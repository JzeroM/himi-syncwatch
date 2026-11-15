/**
 * 694 M3e：弹幕弹窗（鸿蒙 ArkTS 壳）。
 *
 * 全平台「点击弹幕开关按钮 → 弹窗」的鸿蒙实现，内容规格与 Flutter
 * `DanmakuControlSheet` / Qt `DanmakuPanel.qml` / 安卓 Kotlin
 * `PANEL_DANMAKU` 同构：胶囊动效开关（视觉主角）+ 绑定状态行 +
 * 搜索/换绑（空关键词 = Dart 用预填标题，TV 无输入法可直搜）+ 结果
 * 选绑 + 解除绑定。
 *
 * 搜索/绑定/记忆全在 Dart `DanmakuSearchController`，本壳只发命令
 * （searchDanmaku/bindDanmaku/unbindDanmaku）并渲染宿主状态回流
 * （danmakuBinding / danmakuSearchResults / danmakuSearching /
 * danmakuSearchError，随 200ms `_pushNativeUiState` 快照到达）。
 *
 * 【鸿蒙特有坑】@State 必须被 build 显式读取才触发刷新（589 教训）；
 * 本壳全部经 `state()` 读宿主权威快照 + @Prop revision 驱动重建
 * （与 NativePlayerPanel 同机制）。
 */
import {
  HimiMpvNativeHost,
  NativeDanmakuSearchHitUi,
  NativePlayerUiState,
} from './HimiMpvNativeHost';

// ── 弹层调色板（与 NativePlayerPanel.ets 同值；不跨文件导出，故本地复刻）──
const PANEL_TEXT = '#FFFFFF';
const PANEL_TEXT_DIM = '#B3FFFFFF';
const PANEL_DIVIDER = '#1FFFFFFF';
const PANEL_BODY_SIZE = 14;
const PANEL_BODY_WEIGHT = 500;
const PANEL_CAPTION_SIZE = 12;
const PANEL_PAD_H = 16;
/** 开关开启色（三壳同款：橙渐变滑轨）。 */
const DANMAKU_TINT = '#FF8A3D';
const DANMAKU_TINT_DARK = '#E06A1B';
const DANMAKU_TRACK_OFF = '#4A4F57';

@Component
export struct DanmakuPanelContent {
  /** 重建纪元（宿主状态快照到达 → 父面板重建 → 本组件同步）。 */
  @Prop revision: number = 0;

  private host: HimiMpvNativeHost = HimiMpvNativeHost.getInstance();

  private state(): NativePlayerUiState {
    return this.host.state;
  }

  /** 开关状态（弹窗主角）。 */
  private on(): boolean {
    return this.state().danmakuEnabled;
  }

  build() {
    // 694：结果多时可滚动（用户反馈换绑搜索结果很长）；侧栏容器
    // 已下避控制条/进度条（PANEL_PAD_BOTTOM，与其它面板同几何）。
    Scroll() {
    Column() {
      // ── ① 动效开关行（弹窗视觉主角）──
      Row() {
        Text('弹幕')
          .fontSize(PANEL_BODY_SIZE)
          .fontWeight(PANEL_BODY_WEIGHT)
          .fontColor(PANEL_TEXT)
        Blank()
        this.SwitchCapsule()
      }
      .width('100%')
      .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, top: 12, bottom: 6 })
      .onClick((): void => {
        this.host.optimisticToggleDanmaku();
      });

      // ── ② 状态行（开关联动 + 绑定文案）──
      Text(this.on()
        ? `已开启 · ${this.state().danmakuBinding}`
        : '已关闭')
        .fontSize(PANEL_CAPTION_SIZE)
        .fontColor(PANEL_TEXT_DIM)
        .width('100%')
        .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, bottom: 10 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Divider().color(PANEL_DIVIDER).margin({ left: PANEL_PAD_H, right: PANEL_PAD_H });

      // ── ③ 搜索 / 换绑（空关键词 = Dart 用预填标题）──
      Row() {
        Text('搜索 / 换绑')
          .fontSize(PANEL_BODY_SIZE)
          .fontWeight(PANEL_BODY_WEIGHT)
          .fontColor(PANEL_TEXT)
        Blank()
        Text('›')
          .fontSize(PANEL_BODY_SIZE)
          .fontColor(PANEL_TEXT_DIM);
      }
      .width('100%')
      .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, top: 10, bottom: 8 })
      .onClick((): void => {
        this.host.searchDanmaku('');
      });

      if (this.state().danmakuSearching) {
        Text('搜索中…')
          .fontSize(PANEL_CAPTION_SIZE)
          .fontColor(PANEL_TEXT_DIM)
          .width('100%')
          .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, bottom: 6 });
      }
      if (this.state().danmakuSearchError !== '') {
        Text(this.state().danmakuSearchError)
          .fontSize(PANEL_CAPTION_SIZE)
          .fontColor('#FFA040')
          .width('100%')
          .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, bottom: 6 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }

      // ── ④ 搜索结果（点行绑定，manual 记忆 + 立即重载）──
      ForEach(this.state().danmakuSearchResults,
        (hit: NativeDanmakuSearchHitUi) => {
          Row() {
            Column() {
              Text(hit.animeTitle !== '' ? hit.animeTitle : `episodeId ${hit.episodeId}`)
                .fontSize(PANEL_BODY_SIZE)
                .fontColor(PANEL_TEXT)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(hit.episodeTitle)
                .fontSize(PANEL_CAPTION_SIZE)
                .fontColor(PANEL_TEXT_DIM)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('绑定')
              .fontSize(PANEL_BODY_SIZE)
              .fontWeight(PANEL_BODY_WEIGHT)
              .fontColor(DANMAKU_TINT)
          }
          .width('100%')
          .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, top: 8, bottom: 8 })
          .onClick((): void => {
            this.host.bindDanmaku(hit.episodeId);
          });
        },
        (hit: NativeDanmakuSearchHitUi): string => `hit-${hit.episodeId}`);

      // ── ⑤ 解除绑定（有绑定才显示）──
      if (this.state().danmakuBinding !== '' &&
        this.state().danmakuBinding !== '未匹配') {
        Row() {
          Text('解除绑定（回自动匹配）')
            .fontSize(PANEL_BODY_SIZE)
            .fontColor(PANEL_TEXT_DIM)
          Blank()
        }
        .width('100%')
        .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, top: 10, bottom: 10 })
        .onClick((): void => {
          this.host.unbindDanmaku();
        });
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .width('100%')
    .layoutWeight(1);
  }

  /**
   * 胶囊动效开关（三壳同款：橙渐变滑轨 + 白滑钮 180ms 缓动右移）。
   *
   * 开 = 橙渐变滑轨；关 = 中性灰。滑钮内嵌弹幕气泡色圆点（图标字形
   * 依赖子窗口字体注册时机，用纯图形规避 589 类风险）。
   */
  @Builder
  SwitchCapsule() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.on()) {
        Row() {}
          .width(56)
          .height(30)
          .borderRadius(15)
          .linearGradient({ angle: 45, colors: [[DANMAKU_TINT, 0], [DANMAKU_TINT_DARK, 1]] });
      } else {
        Row() {}
          .width(56)
          .height(30)
          .borderRadius(15)
          .backgroundColor(DANMAKU_TRACK_OFF);
      }
      Circle({ width: 24, height: 24 })
        .fill(Color.White)
        .shadow({ radius: 4, color: '#40000000', offsetY: 1 })
        .margin({ left: 3, top: 3 })
        .translate({ x: this.on() ? 26 : 0 })
        .animation({ duration: 180, curve: Curve.EaseOut })
        .onClick((): void => {
          this.host.optimisticToggleDanmaku();
        });
    }
    .width(56)
    .height(30);
  }
}
