/**
 * 原生播放器页面（全屏子窗口宿主页面）。
 *
 * 只渲染 HAR 导出的 HimiNativePlayerView；返回键语义
 * （关面板 → 隐藏控件 → 请求退出）由宿主统一处理。
 */

import { HimiNativePlayerView, HimiMpvNativeHost } from 'himi_mpv_ohos';

@Entry
@Component
struct NativePlayer {
  build() {
    // @Entry 的 build 只允许一个容器根节点，外层 Stack 撑满全屏。
    Stack({ alignContent: Alignment.Center }) {
      HimiNativePlayerView();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black);
  }

  onBackPress(): boolean {
    return HimiMpvNativeHost.getInstance().handleBack();
  }
}
