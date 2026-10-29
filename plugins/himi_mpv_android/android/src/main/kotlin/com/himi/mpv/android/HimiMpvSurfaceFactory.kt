package com.himi.mpv.android

import android.content.Context
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Flutter 平台视图工厂（`himi_mpv_android_surface`）。
 *
 * [useMediaOverlay] 见 [HimiMpvSurfaceView]：Flutter 内嵌平台视图为 true；
 * 全屏 Dialog 宿主（`himi_native_player`）创建 SurfaceView 时传 false。
 */
class HimiMpvSurfaceFactory(
    private val codec: MessageCodec<Any>,
    private val useMediaOverlay: Boolean = true,
    private val source: String = "platform",
) : PlatformViewFactory(codec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        HimiMpvSurfaceView(context, viewId, useMediaOverlay, source)
}
