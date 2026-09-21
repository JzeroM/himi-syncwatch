package com.himi.syncwatch

import android.media.MediaCodecList
import android.media.MediaFormat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DolbyVisionPlugin : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.himi/dolby_vision"
        private const val MIME_DOLBY_VISION = "video/dolby-vision"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDolbyVisionSupported" -> {
                result.success(isDolbyVisionSupported())
            }
            "isProfileSupported" -> {
                val profile = call.argument<Int>("profile") ?: 0
                result.success(isProfileSupported(profile))
            }
            else -> result.notImplemented()
        }
    }

    private fun isDolbyVisionSupported(): Boolean {
        return try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                try {
                    val caps = info.getCapabilitiesForType(MIME_DOLBY_VISION)
                    if (caps != null && caps.profileLevels.isNotEmpty()) {
                        return true
                    }
                } catch (_: Exception) {
                    // 该解码器不支持此 MIME type，跳过
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun isProfileSupported(targetProfile: Int): Boolean {
        return try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                try {
                    val caps = info.getCapabilitiesForType(MIME_DOLBY_VISION)
                    if (caps != null) {
                        for (pl in caps.profileLevels) {
                            if (pl.profile == targetProfile) {
                                return true
                            }
                        }
                    }
                } catch (_: Exception) {
                    // 跳过
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }
}
