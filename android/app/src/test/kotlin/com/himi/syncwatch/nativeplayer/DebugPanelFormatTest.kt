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

    @Test
    fun `backendSupportsDv rejects opengl es`() {
        // 安卓 libmpv 构建 HAVE_VULKAN=0 → libplacebo 无 compute
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
