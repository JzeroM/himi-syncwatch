/**
 * MPV 视频渲染平台视图（XComponent）。
 *
 * 为什么必须用 XComponent 而不是 Flutter 纹理：
 * mpv 的 `gpu-context=ohosvk` 后端需要的是**真正的 OHNativeWindow**
 * （XComponent 提供的 surface），它自己会在这个 surface 上创建 EGL
 * 上下文并直接输出帧。Flutter 的 TextureRegistry 给的是 OH_NativeImage
 * 的 producer surfaceId，mpv 拿到后 vo 初始化不完整——能 create、能
 * loadfile，但出不了帧，且事件线程无输出。
 *
 * 注意：XComponent / XComponentController / XComponentType 是 ArkUI 的
 * **全局内置组件与类型**，不需要（也不能）从 @kit.ArkUI 导入。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'HimiMpvSurface';
const DOMAIN = 0x0001;

/** 由 Plugin 注入的回调（避免 MpvSurface 直接依赖 Plugin 的静态状态）。 */
export interface MpvSurfaceCallbacks {
  onSurfaceCreated(surfaceId: string): void;
  onSurfaceChanged(surfaceId: string, width: number, height: number): void;
  onSurfaceDestroyed(surfaceId: string): void;
}

/**
 * XComponent 的 controller 回调实现。
 *
 * XComponentController 的三个 surface 回调参数里带 surfaceId 字符串
 * （形如 "xxxSurface"），这正是 mpv `wid` 需要的值。
 */
export class MpvXComponentController extends XComponentController {
  private callbacks: MpvSurfaceCallbacks | null = null;

  setCallbacks(cb: MpvSurfaceCallbacks | null): void {
    this.callbacks = cb;
  }

  onSurfaceCreated(surfaceId: string): void {
    hilog.info(DOMAIN, TAG, 'XComponent surface created: %{public}s', surfaceId);
    const cb = this.callbacks;
    if (cb !== null) {
      cb.onSurfaceCreated(surfaceId);
    }
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    hilog.info(DOMAIN, TAG, 'XComponent surface changed: %{public}s %{public}dx%{public}d',
      surfaceId, rect.surfaceWidth, rect.surfaceHeight);
    const cb = this.callbacks;
    if (cb !== null) {
      cb.onSurfaceChanged(surfaceId, rect.surfaceWidth, rect.surfaceHeight);
    }
  }

  onSurfaceDestroyed(surfaceId: string): void {
    hilog.info(DOMAIN, TAG, 'XComponent surface destroyed: %{public}s', surfaceId);
    const cb = this.callbacks;
    if (cb !== null) {
      cb.onSurfaceDestroyed(surfaceId);
    }
  }
}

/**
 * 平台视图内容：一个填满父容器的 XComponent。
 *
 * 类型选 SURFACE（不是 TEXTURE）：要给 mpv 真实的 OHNativeWindow；
 * TEXTURE 类型给的是 OpenGL 纹理，mpv 的 ohosvk vo 不认。
 */
@Component
export struct HimiMpvSurface {
  controller: MpvXComponentController = new MpvXComponentController();

  build() {
    // 与 mpv-arkts 的 PlayerSurface 完全一致：只传 type + controller。
    // 不传 id / libraryname——空字符串的 libraryname 可能触发空命名的
    // native 库加载，SURFACE 类型根本用不到它。
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.controller,
    })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black);
  }
}
