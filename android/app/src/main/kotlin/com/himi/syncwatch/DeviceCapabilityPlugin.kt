package com.himi.syncwatch

import android.content.Context
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.media.ImageReader
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
 *    surface → glTexImage2D 10-bit 纹理上传 R16F/RGBA16F/RGB10A2 →
 *    glGetError），复刻 mdk 渲染前置链路。**ES3 上下文优先**（wgpu/
 *    Erika 渲染的最低要求），建不成才回退 ES2；纹理测试仅在 ES3
 *    上下文执行（ES2 上下文对 ES3 枚举恒 GL_INVALID_ENUM，会误报）。
 *    另做**窗口输出实测**（EGL_WINDOW_BIT config → ImageReader 的
 *    window surface → eglCreateWindowSurface → eglMakeCurrent）：
 *    pbuffer 能建但窗口不能建成的设备（H96_Max_RK3528 闯 eglChooseConfig
 *    3004），mdk GL presenter 必黑，输出层须直写——单靠 pbuffer 会
 *    误报「EGL 正常」。过程全部 try/catch，任何失败都作为探测结果
 *    返回，不影响应用运行；
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

        /** EGL 1.5 / EGL_KHR_create_context 的 GLES3 renderable 位。 */
        private const val EGL_OPENGL_ES3_BIT_KHR = 0x40
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
                    Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION ->
                        types.add("dolbyVision")
                    Display.HdrCapabilities.HDR_TYPE_HDR10 -> types.add("hdr10")
                    Display.HdrCapabilities.HDR_TYPE_HLG -> types.add("hlg")
                    Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS ->
                        types.add("hdr10Plus")
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
                if (info.isEncoder) return@any false
                val type = info.supportedTypes
                    .firstOrNull { it.equals("video/hevc", ignoreCase = true) }
                    ?: return@any false
                // 逐类型能力（MediaCodecInfo 自身没有 profileLevels，
                // 须经 getCapabilitiesForType；不支持的类型会抛异常）。
                val caps = try {
                    info.getCapabilitiesForType(type)
                } catch (_: Throwable) {
                    return@any false
                }
                caps.profileLevels.any { level ->
                    level.profile ==
                        MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                        level.profile ==
                        MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus
                }
            }
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 自建 EGL/GL 探针：pbuffer（不依赖窗口 surface）。ES3 上下文优先
     * （wgpu/Erika 渲染的最低要求：Vulkan 或 GLES 3.0+），ES3 renderable
     * config 与 ES2 config 上的 v3 上下文均建不成才回退 ES2；纹理测试
     * 仅在 ES3 上下文执行。等价于 mdk 渲染前的 EGL config/context 创建
     * + 10-bit 纹理路径探测。
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

            val es2Cfg = chooseConfig(display, es3 = false)
            val es3Cfg = chooseConfig(display, es3 = true)
            out["chooseConfigOk"] = es2Cfg != null || es3Cfg != null
            if (es2Cfg == null && es3Cfg == null) {
                out["eglOk"] = false
                out["error"] = "eglChooseConfig 0x" +
                    Integer.toHexString(EGL14.eglGetError())
                return out
            }

            // ES3 优先（顺序：ES3 config → ES2 config 上建 v3 → 建 v2）；
            // 老驱动不广告 ES3 renderable 时仍可能在 ES2 config 上建成 v3。
            var cfg: EGLConfig? = null
            var gles3Ok = false
            if (es3Cfg != null) {
                val ctx = createContext(display, es3Cfg, 3)
                if (ctx != EGL14.EGL_NO_CONTEXT) {
                    cfg = es3Cfg
                    eglContext = ctx
                    gles3Ok = true
                }
            }
            if (eglContext == EGL14.EGL_NO_CONTEXT && es2Cfg != null) {
                val ctx = createContext(display, es2Cfg, 3)
                if (ctx != EGL14.EGL_NO_CONTEXT) {
                    cfg = es2Cfg
                    eglContext = ctx
                    gles3Ok = true
                }
            }
            if (eglContext == EGL14.EGL_NO_CONTEXT && es2Cfg != null) {
                val ctx = createContext(display, es2Cfg, 2)
                if (ctx != EGL14.EGL_NO_CONTEXT) {
                    cfg = es2Cfg
                    eglContext = ctx
                }
            }
            out["gles3Ok"] = gles3Ok
            if (cfg == null || eglContext == EGL14.EGL_NO_CONTEXT) {
                out["eglOk"] = false
                out["error"] = "eglCreateContext 0x" +
                    Integer.toHexString(EGL14.eglGetError())
                return out
            }

            // 窗口输出实测：mdk GL presenter 把解码纹理贴到窗口 surface，
            // pbuffer 链路全过不代表窗口链路可用。失败即 GL 渲染黑屏
            // 设备（eglBroken → 直写）。
            val (winOk, winErr) = windowSurfaceProbe(display, eglContext)
            out["windowSurfaceOk"] = winOk
            if (!winOk && winErr != null) out["windowError"] = winErr

            surface = EGL14.eglCreatePbufferSurface(
                display, cfg,
                intArrayOf(
                    EGL14.EGL_WIDTH, 16,
                    EGL14.EGL_HEIGHT, 16,
                    EGL14.EGL_NONE
                ), 0
            )
            val current = surface != EGL14.EGL_NO_SURFACE &&
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
            // 纹理测试仅在 ES3 上下文执行；ES2 设备天然不支持 ES3 纹理
            // 格式（恒 false 属预期结论：GL 10-bit 渲染不可用）。
            out["textureR16Ok"] = gles3Ok && tryTexture(
                GLES30.GL_R16F, GLES30.GL_RED, GLES30.GL_HALF_FLOAT
            )
            out["textureRgba16fOk"] = gles3Ok && tryTexture(
                GLES30.GL_RGBA16F, GLES20.GL_RGBA, GLES30.GL_HALF_FLOAT
            )
            out["textureRgb10a2Ok"] = gles3Ok && tryTexture(
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

    /** 按 renderable 类型选择 pbuffer 用 EGL config（失败返回 null）。 */
    private fun chooseConfig(display: EGLDisplay, es3: Boolean): EGLConfig? {
        val attribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE,
            if (es3) EGL_OPENGL_ES3_BIT_KHR else EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val num = IntArray(1)
        val ok = EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0)
        return if (ok && num[0] > 0) configs[0] else null
    }

    /**
     * 窗口输出实测（mdk GL presenter 前置链路）：带 EGL_WINDOW_BIT 的
     * ES2 config（RGB888，失败退 RGB565）→ ImageReader 的 window
     * surface → eglCreateWindowSurface → eglMakeCurrent。任一环失败即
     * 「GL 可建但不配上窗口」，mdk 渲染必黑（eglBroken → 直写）。
     */
    private fun windowSurfaceProbe(
        display: EGLDisplay,
        ctx: EGLContext,
    ): Pair<Boolean, String?> {
        var reader: ImageReader? = null
        var win: EGLSurface = EGL14.EGL_NO_SURFACE
        val cfg = chooseWindowConfig(display) ?: return false to
        ("eglChooseConfig 0x" + Integer.toHexString(EGL14.eglGetError()))
        try {
            reader = ImageReader.newInstance(1, 1, PixelFormat.RGBA_8888, 1)
            win = EGL14.eglCreateWindowSurface(
                display, cfg, reader.surface,
                intArrayOf(EGL14.EGL_NONE), 0
            )
            if (win == EGL14.EGL_NO_SURFACE) {
                return false to ("eglCreateWindowSurface 0x" +
                    Integer.toHexString(EGL14.eglGetError()))
            }
            if (!EGL14.eglMakeCurrent(display, win, win, ctx)) {
                return false to ("eglMakeCurrent(window) 0x" +
                    Integer.toHexString(EGL14.eglGetError()))
            }
            return true to null
        } catch (t: Throwable) {
            return false to (t.message ?: t.javaClass.simpleName)
        } finally {
            try {
                if (win != EGL14.EGL_NO_SURFACE) {
                    // 先解绑再销毁：window surface 尚为 current 时直接
                    // 销毁属未定义行为，可能污染后续 pbuffer 链路。
                    EGL14.eglMakeCurrent(
                        display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE,
                        EGL14.EGL_NO_CONTEXT
                    )
                    EGL14.eglDestroySurface(display, win)
                }
            } catch (_: Throwable) {
                // 清理失败不影响探测结果
            }
            try {
                reader?.close()
            } catch (_: Throwable) {
            }
        }
    }

    /** 带 EGL_WINDOW_BIT 的 ES2 config（RGB888，失败退 RGB565）。 */
    private fun chooseWindowConfig(display: EGLDisplay): EGLConfig? {
        val variants = listOf(
            intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_NONE
            ),
            intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL14.EGL_RED_SIZE, 5,
                EGL14.EGL_GREEN_SIZE, 6,
                EGL14.EGL_BLUE_SIZE, 5,
                EGL14.EGL_NONE
            )
        )
        for (attribs in variants) {
            val configs = arrayOfNulls<EGLConfig>(1)
            val num = IntArray(1)
            val ok =
                EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0)
            if (ok && num[0] > 0) return configs[0]
        }
        return null
    }

    /** 在指定 config 上创建 GLES [version] 上下文（失败返回 NO_CONTEXT）。 */
    private fun createContext(
        display: EGLDisplay,
        cfg: EGLConfig,
        version: Int,
    ): EGLContext = EGL14.eglCreateContext(
        display, cfg, EGL14.EGL_NO_CONTEXT,
        intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, version, EGL14.EGL_NONE), 0
    )

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
