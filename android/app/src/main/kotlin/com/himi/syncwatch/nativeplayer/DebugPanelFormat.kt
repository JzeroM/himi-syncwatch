package com.himi.syncwatch.nativeplayer

/**
 * 697：播放调试面板的**纯判定逻辑**（JVM 可测，不依赖 Android View）。
 *
 * ## 为什么要抽出来
 *
 * 面板的价值在于「判定」——某个组合算正常还是异常。判定错了比没有面板
 * 更糟：会把 P5 偏色标成绿色、把软解标成正常，误导排查方向。
 *
 * View 本身需要真机/模拟器才能测，但这些判定是纯函数，可以在 JVM 上
 * 直接锁定语义（见 `DebugPanelFormatTest`）。
 *
 * ## 三端一致性
 *
 * 同一套判定在 Flutter（`debug_metrics_collector.dart`）和 Windows Qt
 * （`DebugPanel.qml`）各有一份实现。改阈值/关键词时必须三端同步，
 * 否则会出现「安卓说支持、Qt 说不支持」的矛盾。
 */
internal object DebugPanelFormat {

    const val SEV_NORMAL = "normal"
    const val SEV_GOOD = "good"
    const val SEV_WARN = "warn"
    const val SEV_ERROR = "error"

    /**
     * 上下文名 → 后端族（`vulkan` / `d3d11` / `opengl` / `unknown`）。
     *
     * 【697 真机回归】不能写 `ctx.contains("vulkan")`：安卓 Vulkan 的
     * 上下文名是 **`androidvk`**，不含 `vulkan` 子串。旧判定把跑在
     * Vulkan 上的 P5 内容误报成「后端不支持 DV，画面会偏色」。
     *
     * 入参可能是逗号分隔的**优先级列表**（`androidvk,android`）——只看
     * 第一项：列表语义就是「第一个能起来的就是它」。若传的是实际值
     * （mpv `current-gpu-context`），本来就只有一项。
     */
    fun renderBackendOf(context: String?): String {
        val first = (context ?: "")
            .lowercase()
            .split(',')
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() } ?: return "unknown"
        return when {
            // `androidvk` / `ohosvk` / `vulkan` / `x11vk`……都带 `vk`
            first.contains("vk") || first.contains("vulkan") -> "vulkan"
            first.contains("d3d11") -> "d3d11"
            first.contains("android") ||
                first.contains("egl") ||
                first.contains("glx") ||
                first.contains("wayland") ||
                first.contains("opengl") ||
                first.contains("gl") -> "opengl"
            else -> "unknown"
        }
    }

    /**
     * 后端是否支持 DV 元数据（libplacebo 需要 compute shader）。
     *
     * - D3D11（Windows）/ Vulkan（安卓 androidvk、鸿蒙 ohosvk）→ 支持
     * - OpenGL / OpenGL ES → 不支持（mpv 会关掉 hdr-compute-peak）
     *
     * 未知 context 保守判为不支持：误判成「支持」会让人以为 P5 没问题。
     */
    fun backendSupportsDv(gpuContext: String?): Boolean {
        val backend = renderBackendOf(gpuContext)
        return backend == "vulkan" || backend == "d3d11"
    }

    /**
     * 面板判后端用的上下文：**实际值优先**，缺失才退回配置列表。
     *
     * 实际值来自 mpv `current-gpu-context`（`vo->context_name`）；配置列表
     * 只说明我们「允许」哪些后端，不能证明实际选中了哪个。
     */
    fun effectiveRenderContext(actual: String?, configured: String?): String {
        val a = (actual ?: "").trim()
        if (a.isNotEmpty()) return a
        return (configured ?: "").trim()
    }

    /**
     * 丢帧分级。
     *
     * 阈值与 Flutter / Qt 面板一致：>100 异常、>10 可疑、其余正常。
     * 少量丢帧（起播/seek 瞬间）是正常现象，不该报红。
     */
    fun dropSeverity(render: Int, decode: Int): String = when {
        render > 100 || decode > 100 -> SEV_ERROR
        render > 10 || decode > 10 -> SEV_WARN
        else -> SEV_GOOD
    }

    /**
     * DV 的 tone-mapping 是否正确。
     *
     * 697 修复点：DV 是动态元数据，必须 `bt.2390`（感知映射）；
     * 用 `clip` 会硬裁切 → 高光细节丢失、暗部发灰。
     * 非 DV 内容用 `clip` 是正常的（不该报错）。
     */
    fun dvToneMappingOk(isDv: Boolean, toneMapping: String): Boolean =
        !isDv || toneMapping == "bt.2390"

    /** 输出是否真的在 HDR（`target-trc` 为 pq/hlg）。 */
    fun isHdrOutput(targetTrc: String): Boolean =
        targetTrc == "pq" || targetTrc == "hlg"

    /** 毫秒 → `mm:ss` / `hh:mm:ss`。 */
    fun fmtMs(ms: Int): String {
        if (ms <= 0) return "00:00"
        val s = ms / 1000
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) {
            String.format("%02d:%02d:%02d", h, m, sec)
        } else {
            String.format("%02d:%02d", m, sec)
        }
    }

    /**
     * DV Profile 的可读文本（`P8 L6` / `P5（单层 IPT）` / `非 DV 内容`）。
     *
     * 逐段拼接而不是 `a + if(x) "y" else "" + if(z) "w" else ""`——
     * 后者的 `else` 会吞掉后半段（Kotlin/Dart/QML 都有这个优先级陷阱）。
     */
    fun dvProfileText(doviProfile: Int, doviLevel: Int): String {
        if (doviProfile <= 0) return "非 DV 内容"
        val ipt = if (doviProfile == 5) "（单层 IPT）" else ""
        val level = if (doviLevel > 0) " L$doviLevel" else ""
        return "P$doviProfile$ipt$level"
    }

    /** 空串 → "-"（面板不留空白格，一眼能看出「没取到」）。 */
    fun orDash(value: String?, fallback: String? = null): String {
        if (value != null && value.isNotEmpty()) return value
        if (fallback != null && fallback.isNotEmpty()) return fallback
        return "-"
    }
}
