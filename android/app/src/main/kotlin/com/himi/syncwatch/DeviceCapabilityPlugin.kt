package com.himi.syncwatch

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.opengl.GLES30
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * 启动设备能力评估探针（只读，无副作用）：启动时一次调用，供 HDR
 * 自动路由 / 输出决策 / 「播放器配置」页能力卡片共用。
 *
 * 探测项：
 * 1. 显示 HDR：Display#getHdrCapabilities（HDR10/HLG/DV/HDR10+）+
 *    Display#isHdr 当前模式 + 峰值亮度；
 * 2. GL/EGL：自建 pbuffer EGL 上下文实测（eglChooseConfig → context →
 *    surface → glTexImage2D 10-bit 纹理上传 R16/RGBA16F/RGB10A2 →
 *    glGetError），复刻 mdk 渲染前置链路。过程全部 try/catch，任何
 *    失败都作为探测结果返回，不影响应用运行；
 * 3. Vulkan 硬件版本（android.hardware.vulkan.version 打包号）；
 * 4. HEVC Main10 HDR10(_Plus) 解码 profile（MediaCodecList 扫描）；
 * 5. SoC 标识（Build.SOC_MODEL，API 31+ 回退 HARDWARE/BOARD）。
 *
 * 线程模型：探针在单线程 executor 执行（EGL 建/毁上下文避免占用主
 * 线程帧预算），结果 post 回主线程返回 MethodChannel.Result。
 * Dart 侧仍带超时兜底（怪驱动卡死时降级为「EGL 不可用」）。
 */
class DeviceCapabilityPlugin(private val context: Context?) :
    MethodChannel.MethodCallHandler {

    /** 无 Context 的构造：仅用于测试。 */
    constructor() : this(null)

    companion object {
        const val CHANNEL = "himi/device_capability"
    }

    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "himi-device-probe").apply { isDaemon = true }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> executor.execute {
                val map = probe()
                Handler(Looper.getMainLooper()).post { result.success(map) }
            }
            else -> result.notImplemented()
        }
    }

    private fun probe(): Map<String, Any?> {
        val map = HashMap<String, Any?>()
        return try {
            map["sdkInt"] = Build.VERSION.SDK_INT
            map["soc"] = socModel()
            map.putAll(displayCaps())
            map["vulkanVersion"] = vulkanVersion()
            map["hevcHdr10"] = hevcHdr10()
            map["gl"] = glProbe()
            map
        } catch (t: Throwable) {
            map["probeError"] = t.message ?: t.javaClass.simpleName
            map
        }
    }

    /** 显示 HDR 能力（API 24+ 才真正返回类型；失败给 displayError）。 */
    private fun displayCaps(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        val ctx = context ?: return out
        try {
            val dm = ctx.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return out
            val display: Display = dm.getDisplay(Display.DEFAULT_DISPLAY) ?: return out
            val types = ArrayList<String>()
            val caps = display.hdrCapabilities
            caps?.supportedHdrTypes?.forEach { t ->
                when (t) {
                    Display.HDR_TYPE_DOLBY_VISION -> types.add("dolbyVision")
                    Display.HDR_TYPE_HDR10 -> types.add("hdr10")
                    Display.HDR_TYPE_HLG -> types.add("hlg")
                    Display.HDR_TYPE_HDR10_PLUS -> types.add("hdr10Plus")
                }
            }
            out["hdrTypes"] = types
            out["hdr"] = display.isHdr
            out["maxLuminance"] = caps?.desiredMaxLuminance?.toDouble()
            out["avgLuminance"] = caps?.desiredMaxAverageLuminance?.toDouble()
        } catch (t: Throwable) {
            out["displayError"] = t.message ?: t.javaClass.simpleName
        }
        return out
    }

    /** Vulkan 硬件版本打包号（major<<22 | minor<<12 | patch）；无 → null。 */
    private fun vulkanVersion(): Int? {
        val ctx = context ?: return null
        return try {
            ctx.packageManager.systemAvailableFeatures
                ?.firstOrNull { it.name == "android.hardware.vulkan.version" }
                ?.version
        } catch (_: Throwable) {
            null
        }
    }

    /** 是否存在声明 HEVC Main10 HDR10/HDR10+ 的硬件解码器。 */
    private fun hevcHdr10(): Boolean {
        return try {
            val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            list.codecInfos.any { info ->
                !info.isEncoder &&
                    info.supportedTypes.any { it.equals("video/hevc", ignoreCase = true) } &&
                    info.profileLevels.any {
                        it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                            it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus
                    }
            }
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 自建 EGL/GL 探针：pbuffer（不依赖窗口 surface），ES2 上下文，
     * 逐格式上传 16x16 纹理测 glGetError。等价于 mdk 渲染前的 EGL
     * config/context 创建 + 10-bit 纹理路径探测。
     */
    private fun glProbe(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
        var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        var surface: EGLSurface = EGL14.EGL_NO_SURFACE
        try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) {
                out["eglOk"] = false
                out["error"] = "eglGetDisplay 失败"
                return out
            }
            val ver = IntArray(2)
            if (!EGL14.eglInitialize(display, ver, 0, ver, 1)) {
                out["eglOk"] = false
                out["error"] = "eglInitialize 0x" +
                    Integer.toHexString(EGL14.eglGetError())
                return out
            }
            out["eglVersion"] = "${ver[0]}.${ver[1]}"

            val attribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_NONE
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val num = IntArray(1)
            val chooseOk = EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0)
            val cfg = configs[0]
            out["chooseConfigOk"] = chooseOk && cfg != null
            if (!chooseOk || cfg == null) {
                out["eglOk"] = false
                out["error"] = "eglChooseConfig 0x" +
                    Integer.toHexString(EGL14.eglGetError())
                return out
            }

            eglContext = EGL14.eglCreateContext(
                display, cfg, EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0
            )
            surface = EGL14.eglCreatePbufferSurface(
                display, cfg,
                intArrayOf(
                    EGL14.EGL_WIDTH, 16,
                    EGL14.EGL_HEIGHT, 16,
                    EGL14.EGL_NONE
                ), 0
            )
            val current = eglContext != EGL14.EGL_NO_CONTEXT &&
                surface != EGL14.EGL_NO_SURFACE &&
                EGL14.eglMakeCurrent(display, surface, surface, eglContext)
            if (!current) {
                out["eglOk"] = false
                out["error"] = "eglMakeCurrent 0x" +
                    Integer.toHexString(EGL14.eglGetError())
                return out
            }

            out["eglOk"] = true
            out["renderer"] = GLES20.glGetString(GLES20.GL_RENDERER)
            out["glVersion"] = GLES20.glGetString(GLES20.GL_VERSION)
            out["textureR16Ok"] =
                tryTexture(GLES30.GL_R16, GLES30.GL_RED, GLES30.GL_UNSIGNED_SHORT)
            out["textureRgba16fOk"] =
                tryTexture(GLES30.GL_RGBA16F, GLES20.GL_RGBA, GLES30.GL_HALF_FLOAT)
            out["textureRgb10a2Ok"] = tryTexture(
                GLES30.GL_RGB10_A2, GLES20.GL_RGBA,
                GLES30.GL_UNSIGNED_INT_2_10_10_10_REV
            )
            return out
        } catch (t: Throwable) {
            out["eglOk"] = false
            out["error"] = t.message ?: t.javaClass.simpleName
            return out
        } finally {
            try {
                EGL14.eglMakeCurrent(
                    display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT
                )
                if (surface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(display, surface)
                }
                if (eglContext != EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglDestroyContext(display, eglContext)
                }
                if (display != EGL14.EGL_NO_DISPLAY) {
                    EGL14.eglTerminate(display)
                }
            } catch (_: Throwable) {
                // 清理失败不影响探测结果
            }
        }
    }

    /** 空纹理上传测试：glGetError == GL_NO_ERROR 即该格式可用。 */
    private fun tryTexture(internalFormat: Int, format: Int, type: Int): Boolean {
        var ok = false
        try {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            val id = ids[0]
            if (id == 0) return false
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
            while (GLES20.glGetError() != GLES20.GL_NO_ERROR) {
                // 清空历史错误，保证本次结果归因准确
            }
            GLES20.glTexImage2D(
                GLES20.GL_TEXTURE_2D, 0, internalFormat,
                16, 16, 0, format, type, null
            )
            ok = GLES20.glGetError() == GLES20.GL_NO_ERROR
            GLES20.glDeleteTextures(1, ids, 0)
        } catch (_: Throwable) {
            ok = false
        }
        return ok
    }

    private fun socModel(): String {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Build.SOC_MODEL
            } else {
                "${Build.HARDWARE}/${Build.BOARD}"
            }
        } catch (_: Throwable) {
            "unknown"
        }
    }
}
