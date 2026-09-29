package com.himi.syncwatch

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dolby Vision 硬件解码能力探测。
 *
 * 关键点：DV 硬解不一定以 [MIME_DOLBY_VISION] 声明。
 * 骁龙平台通常由 video/hevc 解码器声明，其 profileLevels 里含
 * DolbyVisionProfileDvhe*（0x0100 段）常量；部分厂商还使用
 * video/hevcdv、video/dv_hevc 等私有 MIME。
 * ExoPlayer 的 MediaCodecUtil.getCodecMimeType 对此有专门兜底。
 *
 * 只探测 video/dolby-vision 会漏判，导致上层误以为设备不支持而
 * 强制走软件解码，进而在 4K 10bit 场景下解码不及而卡顿。
 */
class DolbyVisionPlugin : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.himi/dolby_vision"
        private const val MIME_DOLBY_VISION = "video/dolby-vision"
        private const val MIME_HEVC = "video/hevc"
        private const val MIME_AVC = "video/avc"

        /**
         * 已知声明 DV 但使用非标准 MIME 的厂商私有类型。
         * 参考 ExoPlayer MediaCodecUtil.getCodecMimeType：
         * OMX.MS.HEVCDV.Decoder -> video/hevcdv
         * OMX.RTK.video.decoder* -> video/dv_hevc
         */
        private val DV_ALT_MIMES = arrayOf("video/hevcdv", "video/dv_hevc")

        /**
         * Dolby Vision profile 常量落在 0x0100 段。
         * AOSP 中为 DolbyVisionProfileDvheDer=0x0103 ... DolbyVisionProfileDvheSt=0x0109
         * 等编译期常量，此处用区间判定以兼容厂商自定义值。
         */
        private const val DV_PROFILE_MIN = 0x0100
        private const val DV_PROFILE_MAX = 0x01FF

        private fun isDvProfile(profile: Int): Boolean =
            profile in DV_PROFILE_MIN..DV_PROFILE_MAX
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDolbyVisionSupported" -> result.success(probe().supported)
            "getDolbyVisionInfo" -> result.success(probe().toMap())
            "selectDecoder" -> result.success(
                selectDecoder(
                    mime = call.argument<String>("mime"),
                    width = call.argument<Int>("width"),
                    height = call.argument<Int>("height"),
                    dolbyVision = call.argument<Boolean>("dolbyVision") ?: false
                ).toMap()
            )
            else -> result.notImplemented()
        }
    }

    /**
     * 平台预选解码器。
     *
     * [MediaCodecList.findDecoderForFormat] 给出的是「Android 会为该格式选谁」，
     * 属于推断而非「mdk 实际已选谁」的实证；上层据此标注置信度。
     * 该 API 自 API 21 起可用，故此处不做 DV 能力（API 29）门控。
     */
    data class DecoderSelection(
        val picked: String?,
        val mime: String?,
        val isSoftware: Boolean?,
        val supported: List<String>,
        val dvProfiles: List<Int>,
        val error: String?
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "picked" to picked,
            "mime" to mime,
            "isSoftware" to isSoftware,
            "supported" to supported,
            "dvProfiles" to dvProfiles,
            "error" to error
        )
    }

    data class DvDecoder(
        val name: String,
        val mime: String,
        val dvProfiles: List<Int>,
        val isSoftware: Boolean
    )

    data class DvProbe(
        val supported: Boolean,
        val hardware: Boolean,
        val decoders: List<DvDecoder>,
        val error: String?
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "supported" to supported,
            "hardware" to hardware,
            "error" to error,
            "decoders" to decoders.map {
                mapOf(
                    "name" to it.name,
                    "mime" to it.mime,
                    "dvProfiles" to it.dvProfiles,
                    "isSoftware" to it.isSoftware
                )
            }
        )
    }

    private fun probe(): DvProbe {
        if (!isDvCapableOs()) {
            return DvProbe(false, false, emptyList(), "非 Android 或 API 过低")
        }
        return try {
            val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            val found = mutableListOf<DvDecoder>()

            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                val software = isSoftwareName(info.name)
                val hits = mutableListOf<Pair<String, List<Int>>>()

                // 1) 标准 video/dolby-vision：声明了即为 DV 解码器
                queryProfileLevels(info, MIME_DOLBY_VISION)?.let { pl ->
                    if (pl.isNotEmpty()) {
                        // 只保留 0x01xx 的 DV profile；软解实现常在此 MIME 下
                        // 填 HEVC 原生 profile（0x0001 等），展示出来会误导
                        val dv = pl.filter { isDvProfile(it) }
                        hits += Pair(MIME_DOLBY_VISION, dv)
                    }
                }
                // 2) video/hevc / video/avc 的 profileLevels 中含 DV profile。
                //    骁龙平台走这条路径——这是旧实现漏判导致误强制软解的根因。
                for (base in listOf(MIME_HEVC, MIME_AVC)) {
                    queryProfileLevels(info, base)?.let { pl ->
                        val dv = pl.filter { isDvProfile(it) }
                        if (dv.isNotEmpty()) hits += Pair(base, dv)
                    }
                }
                // 3) 厂商私有 DV MIME
                for (alt in DV_ALT_MIMES) {
                    queryProfileLevels(info, alt)?.let { pl ->
                        if (pl.isNotEmpty()) hits += Pair(alt, pl)
                    }
                }

                if (hits.isNotEmpty()) {
                    // 同一解码器可能多 MIME 命中，取 DV profile 最全的一条
                    val best = hits.maxByOrNull { it.second.size }!!
                    found += DvDecoder(info.name, best.first, best.second, software)
                }
            }

            val hardware = found.any { !it.isSoftware }
            DvProbe(
                supported = found.isNotEmpty(),
                hardware = hardware,
                decoders = found,
                error = null
            )
        } catch (e: Throwable) {
            DvProbe(false, false, emptyList(), e.toString())
        }
    }

    private fun selectDecoder(
        mime: String?,
        width: Int?,
        height: Int?,
        dolbyVision: Boolean
    ): DecoderSelection {
        if (mime.isNullOrEmpty()) {
            return DecoderSelection(null, null, null, emptyList(), emptyList(), "缺少 mime")
        }
        // DV 内容优先用标准 MIME；骁龙等平台由 video/hevc 声明，再退到 avc 与厂商私有类型
        val mimes = if (dolbyVision) {
            listOf(MIME_DOLBY_VISION, MIME_HEVC, MIME_AVC) + DV_ALT_MIMES.toList()
        } else {
            listOf(mime)
        }
        return try {
            val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)

            var picked: String? = null
            var pickedMime: String? = null
            var format: MediaFormat? = null
            for (m in mimes) {
                val f = buildFormat(m, width, height) ?: continue
                val name = try {
                    codecList.findDecoderForFormat(f)
                } catch (_: Throwable) {
                    null
                }
                if (name != null) {
                    picked = name
                    pickedMime = m
                    format = f
                    break
                }
            }

            if (picked == null || format == null) {
                return DecoderSelection(
                    null, null, null, emptyList(), emptyList(), "无匹配解码器"
                )
            }
            val chosen = picked
            val fmt = format

            // 逐个校验候选，给出「哪些 codec 真能吃下这个格式」的完整对照
            val supported = mutableListOf<String>()
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                if (mimes.any { supportsFormat(info, it, fmt) }) supported += info.name
            }

            val pickedInfo = codecList.codecInfos.firstOrNull { it.name == chosen }
            val dvProfiles = pickedInfo?.let { info ->
                mimes.flatMap { queryProfileLevels(info, it) ?: emptyList() }
                    .filter { isDvProfile(it) }
                    .distinct()
            } ?: emptyList()

            DecoderSelection(
                picked = chosen,
                mime = pickedMime,
                isSoftware = isSoftwareName(chosen),
                supported = supported,
                dvProfiles = dvProfiles,
                error = null
            )
        } catch (e: Throwable) {
            DecoderSelection(null, null, null, emptyList(), emptyList(), e.toString())
        }
    }

    /**
     * 构造最小 MediaFormat。只在尺寸有效时写入 width/height，
     * 避免用 0 或虚假尺寸把平台筛选范围限死。
     */
    private fun buildFormat(mime: String, width: Int?, height: Int?): MediaFormat? = try {
        MediaFormat().apply {
            setString(MediaFormat.KEY_MIME, mime)
            val w = width ?: 0
            val h = height ?: 0
            if (w > 0 && h > 0) {
                setInteger(MediaFormat.KEY_WIDTH, w)
                setInteger(MediaFormat.KEY_HEIGHT, h)
            }
        }
    } catch (_: Throwable) {
        null
    }

    private fun supportsFormat(
        info: MediaCodecInfo,
        mime: String,
        format: MediaFormat
    ): Boolean = try {
        info.getCapabilitiesForType(mime).isFormatSupported(format)
    } catch (_: Throwable) {
        false
    }

    private fun isDvCapableOs(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    private fun queryProfileLevels(
        info: MediaCodecInfo,
        mime: String
    ): List<Int>? = try {
        val caps = info.getCapabilitiesForType(mime) ?: return null
        caps.profileLevels.map { it.profile }.distinct()
    } catch (_: Throwable) {
        // 该解码器不支持此 MIME type
        null
    }

    /**
     * 粗略识别软件解码器名。系统软解实现名为
     * c2.android.hevc.decoder / c2.android.avc.decoder 等。
     */
    private fun isSoftwareName(name: String): Boolean {
        val n = name.lowercase()
        return n.contains("c2.android") ||
            n.contains("omx.google") ||
            n.contains("ffmpeg") ||
            n.contains("sw.")
    }
}
