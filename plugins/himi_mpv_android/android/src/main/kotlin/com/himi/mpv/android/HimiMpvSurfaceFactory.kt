package com.himi.mpv.android

import android.content.Context
import android.view.SurfaceView
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class HimiMpvSurfaceFactory(private val codec: MessageCodec<Any>) : PlatformViewFactory(codec) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        HimiMpvSurfaceView(context, viewId)
}
