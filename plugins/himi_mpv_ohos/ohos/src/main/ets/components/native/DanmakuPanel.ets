/**
 * 694 M3e：弹幕弹窗（鸿蒙 ArkTS 壳）。
 *
 * 全平台「点击弹幕开关按钮 → 弹窗」的鸿蒙实现，内容规格与 Flutter
 * `DanmakuControlSheet` / Qt `DanmakuPanel.qml` / 安卓 Kotlin
 * `PANEL_DANMAKU` 同构：胶囊动效开关（视觉主角）+ 绑定状态行 +
 * 搜索/换绑（关键词输入框 + TV 快捷行）+ 结果选绑 + 解除绑定。
 *
 * 搜索/绑定/记忆全在 Dart `DanmakuSearchController`，本壳只发命令
 * （searchDanmaku/bindDanmaku/unbindDanmaku）并渲染宿主状态回流。
 *
 * 【鸿蒙刷新机制——真机回归教训】
 * 宿主 `state().X` 是普通字段，**不在 ArkUI 观察链上**；`revision++`
 * 间接触发重建实测不可靠（view 注释 315：点锁图标不实时变）。可靠
 * 机制是「**自驱签名轮询 → epoch 自增 → ForEach key 变化 → 子树
 * 重建**」（view `refreshControlsEpoch` / DanmakuLayer 自驱 timer
 * 同款）。此前只靠 @Prop revision → 点开关形态不变、搜索结果要重开
 * 面板才出现（真机回归），即本机制缺失。
 *
 * 输入框关键词存组件级 `@State keyword`：子树重建（ForEach key 变）
 * 不丢用户已输入文本；关键词**不进签名**（否则打字触发重建丢焦点）。
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
/** 开关开启色（四壳同款：橙渐变滑轨）。 */
const DANMAKU_TINT = '#FF8A3D';
const DANMAKU_TINT_DARK = '#E06A1B';
const DANMAKU_TRACK_OFF = '#4A4F57';

@Component
export struct DanmakuPanelContent {
  /** 重建纪元（父面板传入；实际刷新由自驱签名驱动，见文件头注释）。 */
  @Prop revision: number = 0;
  /** 自驱重建纪元（签名变化 → ForEach key 变化 → 子树重建）。 */
  @State epoch: number = 0;
  /** 搜索关键词（组件级 @State：子树重建不丢输入；不进签名防打字重建）。 */
  @State keyword: string = '';

  private lastSig: string = '';
  private timer: number = -1;
  private host: HimiMpvNativeHost = HimiMpvNativeHost.getInstance();

  aboutToAppear(): void {
    if (this.keyword === '') {
      this.keyword = this.host.state.danmakuSearchKeyword;
    }
    this.lastSig = this.stateSig();
    // 200ms 签名轮询（DanmakuLayer 自驱 timer 同款已验证机制）。
    this.timer = setInterval((): void => {
      const sig = this.stateSig();
      if (sig !== this.lastSig) {
        this.lastSig = sig;
        this.epoch = this.epoch + 1;
      }
    }, 200);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** 影响弹窗形态/内容的状态签名（关键词除外，见文件头注释）。 */
  private stateSig(): string {
    const s: NativePlayerUiState = this.host.state;
    let hits: string = '';
    for (let i = 0; i < s.danmakuSearchResults.length; i++) {
      hits += `${s.danmakuSearchResults[i].episodeId},`;
    }
    return `${s.danmakuEnabled}|${s.danmakuBinding}|${s.danmakuSearching}`
      + `|${s.danmakuSearchError}|${hits}`;
  }

  private state(): NativePlayerUiState {
    return this.host.state;
  }

  private on(): boolean {
    return this.state().danmakuEnabled;
  }

  build() {
    // 结果多时可滚动（侧栏容器已下避控制条/进度条）。
    // Scroll 只允许一个子组件：ForEach 生成器包一层 Column。
    Scroll() {
      Column() {
        ForEach([this.epoch], (e: number) => {
          this.Content();
        }, (e: number): string => `dm-panel-${e}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .width('100%')
    .layoutWeight(1);
  }

  @Builder
  Content() {
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

      // ── ③ 搜索/换绑：关键词输入框（草稿保持）+ 搜索 + TV 快捷行 ──
      Row() {
        TextInput({ text: this.keyword, placeholder: '输入剧名搜索…' })
          .layoutWeight(1)
          .height(38)
          .fontSize(PANEL_BODY_SIZE)
          .fontColor(PANEL_TEXT)
          .placeholderColor('#59FFFFFF')
          .backgroundColor('#1AFFFFFF')
          .borderRadius(8)
          .margin({ right: 8 })
          .onChange((value: string): void => {
            this.keyword = value;
          })
        Text('搜索')
          .fontSize(PANEL_BODY_SIZE)
          .fontWeight(PANEL_BODY_WEIGHT)
          .fontColor(DANMAKU_TINT)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onClick((): void => {
            this.host.searchDanmaku(this.keyword);
          });
      }
      .width('100%')
      .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, top: 10, bottom: 4 });

      Row() {
        Text('按当前标题搜索')
          .fontSize(PANEL_CAPTION_SIZE)
          .fontColor(PANEL_TEXT_DIM)
        Blank()
        Text('›')
          .fontSize(PANEL_CAPTION_SIZE)
          .fontColor(PANEL_TEXT_DIM);
      }
      .width('100%')
      .padding({ left: PANEL_PAD_H, right: PANEL_PAD_H, top: 6, bottom: 8 })
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

  /**
   * 胶囊动效开关（四壳同款：橙渐变滑轨 + 白滑钮 180ms 缓动右移）。
   *
   * 开 = 橙渐变滑轨；关 = 中性灰。滑钮为纯图形（图标字形依赖子窗口
   * 字体注册时机，规避 589 类风险）。
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
