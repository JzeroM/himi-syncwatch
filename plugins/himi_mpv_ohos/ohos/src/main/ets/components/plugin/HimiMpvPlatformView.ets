/**
 * MPV 平台视图：把 XComponent 作为 PlatformView 嵌入 Flutter。
 *
 * 与 ydplayer 的 MpvSurface 同构：Flutter 侧用 OhosView 挂载，
 * ArkTS 侧返回一个包着 XComponent 的 WrappedBuilder。
 * mpv 直接渲染到 XComponent 的 OHNativeWindow。
 *
 * 渲染链路（鸿蒙 Flutter 引擎实现）：
 *   OhosView → PlatformViewsController.createForTextureLayerComposition
 *   → BuilderNode(surfaceId=<flutter texture>) → @Builder 执行
 *   → XComponent 创建自己的 surface（onSurfaceCreated 回调给出 surfaceId）
 *   → mpv attachSurface(该 surfaceId) 直接渲染
 *   → XComponent 内容作为 texture 被 Flutter 合成（弹幕/控件可叠加）
 */

import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MpvXComponentController, MpvSurfaceCallbacks, HimiMpvSurface } from './HimiMpvSurface';

const TAG = 'HimiMpvPlatformView';
const DOMAIN = 0x0001;

/** 平台视图类型名（Dart 侧 OhosView 用它）。 */
export const MPV_VIEW_TYPE = 'himi_mpv_surface';

/**
 * @Builder 函数：引擎通过 `builderNode.build(wrappedBuilder, params)` 调用，
 * `params.platformView` 就是本次要渲染的 PlatformView 实例。
 *
 * 这是引擎给的**唯一可靠**的实例传递方式——不能用模块级全局变量，
 * 因为 BuilderNode 的构建时机与工厂 create 时机不同，全局变量会错配。
 */
@Builder
function buildMpvSurface(params: Params) {
  HimiMpvSurface({
    controller: (params.platformView as HimiMpvPlatformView).getController(),
  });
}

/**
 * 单个 MPV 平台视图实例。
 *
 * `getView()` 返回 XComponent 的 WrappedBuilder；controller 的 surface
 * 生命周期回调转发给 Plugin 注入的 [MpvSurfaceCallbacks]，由 Plugin 负责
 * 调用 mpv 的 attachSurface / detachSurface。
 */
export class HimiMpvPlatformView extends PlatformView {
  private readonly viewId: number;
  private controller: MpvXComponentController;
  private readonly builder: WrappedBuilder<[Params]>;

  constructor(viewId: number, callbacks: MpvSurfaceCallbacks) {
    super();
    this.viewId = viewId;
    this.controller = new MpvXComponentController();
    // 构造时立刻绑定回调：此时还没渲染，回调只会在 surface 真正创建时触发。
    this.controller.setCallbacks(callbacks);
    this.builder = wrapBuilder(buildMpvSurface);
    hilog.info(DOMAIN, TAG, 'platform view %{public}d created (controller ready)', viewId);
  }

  getViewId(): number {
    return this.viewId;
  }

  getController(): MpvXComponentController {
    return this.controller;
  }

  getView(): WrappedBuilder<[Params]> {
    return this.builder;
  }

  dispose(): void {
    hilog.info(DOMAIN, TAG, 'platform view %{public}d disposed', this.viewId);
    this.controller.setCallbacks(null);
  }
}

/** 平台视图工厂：Flutter 请求创建时返回 [HimiMpvPlatformView]。 */
export class HimiMpvPlatformViewFactory extends PlatformViewFactory {
  private readonly callbacks: MpvSurfaceCallbacks;

  constructor(callbacks: MpvSurfaceCallbacks) {
    super(StandardMessageCodec.INSTANCE);
    this.callbacks = callbacks;
  }

  create(_context: common.Context, viewId: number, _args: Object): PlatformView {
    hilog.info(DOMAIN, TAG, 'creating platform view %{public}d', viewId);
    return new HimiMpvPlatformView(viewId, this.callbacks);
  }
}
