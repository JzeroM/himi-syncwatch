package com.himi.syncwatch.nativeplayer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 697：[DebugPanelFormat] 纯判定逻辑单测。
 *
 * ## 为什么这些判定必须测
 *
 * 面板的价值在于「这个组合算正常还是异常」。判错比没有面板更糟：
 * 把 P5 偏色标成绿、把软解标成正常，会把人引向错误的排查方向。
 *
 * ## 三端一致性
 *
 * 同一套语义在 Flutter（`debug_metrics_collector.dart`）和 Windows Qt
 * （`DebugPanel.qml`）各有一份。Dart 侧已有对应用例；这里的阈值与
 * 关键词必须与之相同。
 */
class DebugPanelFormatTest {

    // ── 后端 DV 能力 ─────────────────────────────────────────────

    @Test
    fun `backendSupportsDv accepts d3d11 and vulkan`() {
        assertTrue(DebugPanelFormat.backendSupportsDv("d3d11"))
        assertTrue(DebugPanelFormat.backendSupportsDv("D3D11"))
        assertTrue(DebugPanelFormat.backendSupportsDv("vulkan"))
        assertTrue(DebugPanelFormat.backendSupportsDv("ohosvk"))
        assertTrue(DebugPanelFormat.backendSupportsDv("OHOSVK"))
    }

    /**
     * 【697 真机回归】安卓 Vulkan 的上下文名是 `androidvk`，**不含**
     * `vulkan` 子串。旧判定 `contains("vulkan")` 把它误判为不支持 DV，
     * 于是跑在 Vulkan 上的 P5 内容被标成「画面会偏色」（真机截图）。
     */
    @Test
    fun `backendSupportsDv accepts androidvk`() {
        assertTrue(DebugPanelFormat.backendSupportsDv("androidvk"))
        assertTrue(DebugPanelFormat.backendSupportsDv("ANDROIDVK"))
    }

    /**
     * `gpu-context` 读回来可能是**优先级列表**（我们为了 Vulkan 失败能
     * 回落而下发 `androidvk,android`）。列表只看第一项——第一项能起来
     * 的就是实际用的那个。
     */
    @Test
    fun `backendSupportsDv handles priority list`() {
        assertTrue(DebugPanelFormat.backendSupportsDv("androidvk,android"))
        assertTrue(DebugPanelFormat.backendSupportsDv("vulkan,opengl"))
        assertFalse(DebugPanelFormat.backendSupportsDv("android,androidvk"))
    }

    @Test
    fun `renderBackendOf classifies families`() {
        assertEquals("vulkan", DebugPanelFormat.renderBackendOf("androidvk"))
        assertEquals("vulkan", DebugPanelFormat.renderBackendOf("ohosvk"))
        assertEquals("vulkan", DebugPanelFormat.renderBackendOf("vulkan"))
        assertEquals("d3d11", DebugPanelFormat.renderBackendOf("d3d11"))
        assertEquals("opengl", DebugPanelFormat.renderBackendOf("android"))
        assertEquals("opengl", DebugPanelFormat.renderBackendOf("opengl"))
        assertEquals("unknown", DebugPanelFormat.renderBackendOf(""))
        assertEquals("unknown", DebugPanelFormat.renderBackendOf(null))
    }

    /** 实际值优先；只有实际值缺失时才退回配置列表。 */
    @Test
    fun `effectiveRenderContext prefers actual`() {
        assertEquals(
            "androidvk",
            DebugPanelFormat.effectiveRenderContext("androidvk", "androidvk,android"),
        )
        assertEquals(
            "android",
            DebugPanelFormat.effectiveRenderContext("android", "androidvk,android"),
        )
        assertEquals(
            "androidvk,android",
            DebugPanelFormat.effectiveRenderContext("", "androidvk,android"),
        )
    }

    @Test
    fun `backendSupportsDv rejects opengl es`() {
        // 回落路径：Vulkan 初始化失败 → android（EGL/GLES），无可靠 compute
        assertFalse(DebugPanelFormat.backendSupportsDv("android"))
        assertFalse(DebugPanelFormat.backendSupportsDv("opengl"))
        assertFalse(DebugPanelFormat.backendSupportsDv("opengles"))
        assertFalse(DebugPanelFormat.backendSupportsDv("gl"))
        assertFalse(DebugPanelFormat.backendSupportsDv(""))
    }

    @Test
    fun `backendSupportsDv is conservative for unknown contexts`() {
        // 误判成「支持」会让人以为 P5 没问题 → 保守判不支持
        assertFalse(DebugPanelFormat.backendSupportsDv("metal"))
        assertFalse(DebugPanelFormat.backendSupportsDv("software"))
    }

    // ── 丢帧分级 ─────────────────────────────────────────────────

    @Test
    fun `dropSeverity grades by thresholds`() {
        assertEquals(DebugPanelFormat.SEV_GOOD, DebugPanelFormat.dropSeverity(0, 0))
        assertEquals(DebugPanelFormat.SEV_GOOD, DebugPanelFormat.dropSeverity(10, 10))
        assertEquals(DebugPanelFormat.SEV_WARN, DebugPanelFormat.dropSeverity(11, 0))
        assertEquals(DebugPanelFormat.SEV_WARN, DebugPanelFormat.dropSeverity(0, 11))
        assertEquals(DebugPanelFormat.SEV_WARN, DebugPanelFormat.dropSeverity(100, 100))
        assertEquals(DebugPanelFormat.SEV_ERROR, DebugPanelFormat.dropSeverity(101, 0))
        assertEquals(DebugPanelFormat.SEV_ERROR, DebugPanelFormat.dropSeverity(0, 101))
    }

    // ── DV tone-mapping ─────────────────────────────────────────

    @Test
    fun `dvToneMappingOk requires bt2390 only for DV`() {
        // 697 修复：DV 必须感知映射，clip 会丢高光
        assertTrue(DebugPanelFormat.dvToneMappingOk(isDv = true, toneMapping = "bt.2390"))
        assertFalse(DebugPanelFormat.dvToneMappingOk(isDv = true, toneMapping = "clip"))
        // 非 DV 用 clip 是正常的，不该报红
        assertTrue(DebugPanelFormat.dvToneMappingOk(isDv = false, toneMapping = "clip"))
    }

    // ── HDR 输出 ─────────────────────────────────────────────────

    @Test
    fun `isHdrOutput only pq or hlg`() {
        assertTrue(DebugPanelFormat.isHdrOutput("pq"))
        assertTrue(DebugPanelFormat.isHdrOutput("hlg"))
        assertFalse(DebugPanelFormat.isHdrOutput("auto"))
        assertFalse(DebugPanelFormat.isHdrOutput("bt.1886"))
    }

    // ── DV Profile 文本 ─────────────────────────────────────────

    @Test
    fun `dvProfileText renders non-DV`() {
        assertEquals("非 DV 内容", DebugPanelFormat.dvProfileText(0, 0))
        assertEquals("非 DV 内容", DebugPanelFormat.dvProfileText(-1, 0))
    }

    @Test
    fun `dvProfileText marks P5 as single-layer IPT`() {
        assertEquals("P5（单层 IPT）", DebugPanelFormat.dvProfileText(5, 0))
        assertEquals("P5（单层 IPT） L6", DebugPanelFormat.dvProfileText(5, 6))
    }

    @Test
    fun `dvProfileText appends level for P8`() {
        assertEquals("P8", DebugPanelFormat.dvProfileText(8, 0))
        assertEquals("P8 L6", DebugPanelFormat.dvProfileText(8, 6))
    }

    @Test
    fun `dvProfileText does not lose level after ipt suffix`() {
        // 回归：`a + if(x) "y" else "" + if(z) "w" else ""` 的 else
        // 会吞掉后半段 → P5 有 level 时被丢掉。
        val text = DebugPanelFormat.dvProfileText(5, 8)
        assertTrue("应包含 level，实际=$text", text.contains("L8"))
    }

    // ── 时间格式化 ───────────────────────────────────────────────

    @Test
    fun `fmtMs handles zero and negative`() {
        assertEquals("00:00", DebugPanelFormat.fmtMs(0))
        assertEquals("00:00", DebugPanelFormat.fmtMs(-5000))
    }

    @Test
    fun `fmtMs formats mmss and hhmmss`() {
        assertEquals("00:01", DebugPanelFormat.fmtMs(1000))
        assertEquals("01:05", DebugPanelFormat.fmtMs(65_000))
        assertEquals("01:01:05", DebugPanelFormat.fmtMs(3_665_000))
    }

    // ── 空值兜底 ─────────────────────────────────────────────────

    @Test
    fun `orDash falls back for empty values`() {
        assertEquals("abc", DebugPanelFormat.orDash("abc"))
        assertEquals("-", DebugPanelFormat.orDash(null))
        assertEquals("-", DebugPanelFormat.orDash(""))
        // 主值缺失时用备用值
        assertEquals("fallback", DebugPanelFormat.orDash(null, "fallback"))
        assertEquals("fallback", DebugPanelFormat.orDash("", "fallback"))
        assertEquals("-", DebugPanelFormat.orDash(null, ""))
    }

    // ── 与 Dart/Qt 阈值一致性 ─────────────────────────────────────

    @Test
    fun `severity constants match flutter and qt`() {
        // 三端同一组语义字符串，改这里必须同步改另两端
        assertEquals("good", DebugPanelFormat.SEV_GOOD)
        assertEquals("warn", DebugPanelFormat.SEV_WARN)
        assertEquals("error", DebugPanelFormat.SEV_ERROR)
        assertEquals("normal", DebugPanelFormat.SEV_NORMAL)
    }
}
