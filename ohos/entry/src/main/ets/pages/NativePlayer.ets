/**
 * 原生播放器页面（全屏子窗口宿主页面）。
 *
 * 只渲染 HAR 导出的 HimiNativePlayerView；返回键语义
 * （关面板 → 隐藏控件 → 请求退出）由宿主统一处理。
 *
 * 图标字体注册在**本子窗口的 UIContext**：字体注册作用域是当前窗口，
 * 主窗口（EntryAbility）注册的 HimiIcons 不跨窗口生效——v1.5.5 真机回归
 * 「图标全灭」根因即此。aboutToAppear 在 build 之前执行，注册完成后
 * 控件层的 fontFamily 才能取到字形。$rawfile 只能在 entry 模块解析
 * （插件 HAR 的 rawfile 不打进 HAP），所以注册放这里而非 HAR 里。
 */

import { font } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HimiNativePlayerView, HimiMpvNativeHost } from 'himi_mpv_ohos';

const DOMAIN = 0x0001;
const TAG = 'NativePlayer';

/** 与 NativePlayerIcons.FONT_FAMILY 一致（test/native_player_icons_test.dart 锁定）。 */
const ICON_FONT_FAMILY = 'HimiIcons';
const ICON_FONT_RAWFILE = 'MaterialIcons-Regular.otf';

@Entry
@Component
struct NativePlayer {
  aboutToAppear(): void {
    // 现行 API（API 18+）：注册到子窗口自己的 UIContext。
    try {
      this.getUIContext().getFont().registerFont({
        familyName: ICON_FONT_FAMILY,
        familySrc: $rawfile(ICON_FONT_RAWFILE),
      });
      hilog.info(DOMAIN, TAG, 'HimiIcons 子窗口注册成功（UIContext.getFont）');
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, `HimiIcons 子窗口注册失败(UIContext): ${err.code} ${err.message}`);
      // 兜底：旧系统全局 API（onCreate 时机已注册过一次，这里再补子窗口链路）。
      try {
        font.registerFont({
          familyName: ICON_FONT_FAMILY,
          familySrc: $rawfile(ICON_FONT_RAWFILE),
        });
        hilog.info(DOMAIN, TAG, 'HimiIcons 子窗口注册成功（font.registerFont 兜底）');
      } catch (e2) {
        const err2 = e2 as BusinessError;
        hilog.error(DOMAIN, TAG, `HimiIcons 子窗口注册失败(兜底): ${err2.code} ${err2.message}`);
      }
    }
  }

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
