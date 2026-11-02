package com.himi.syncwatch.nativeplayer

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [GlassSeekBarView] 纯函数（值映射几何）JVM 单测。
 *
 * 触点映射与拇指定位必须同基准（真机回归「拖动进度条触摸位置不一致」），
 * snapValue / centerXOf 互为逆映射。
 */
class GlassSeekBarViewTest {

    @Test
    fun `snapValue maps touch x over inset track`() {
        // 轨道内缩 pad=14（GLOW_D/2），trackW=772（800-2×14）。
        // 左端 x=14 → min；右端 x=786 → max；中点 → 中值。
        val min = 0f
        val max = 100f
        assertEquals(0f, GlassSeekBarView.snapValue(14f, 772f, 14f, min, max, 0f), 1e-4f)
        assertEquals(100f, GlassSeekBarView.snapValue(786f, 772f, 14f, min, max, 0f), 1e-4f)
        assertEquals(50f, GlassSeekBarView.snapValue(400f, 772f, 14f, min, max, 0f), 1e-4f)
    }

    @Test
    fun `snapValue clamps out-of-range touches`() {
        val v = GlassSeekBarView.snapValue(-500f, 772f, 14f, 0f, 100f, 0f)
        assertEquals(0f, v, 1e-4f)
        val v2 = GlassSeekBarView.snapValue(5000f, 772f, 14f, 0f, 100f, 0f)
        assertEquals(100f, v2, 1e-4f)
    }

    @Test
    fun `snapValue snaps to step`() {
        // seek 用 1000ms 档：x 映射到 2600ms 附近 → 吸附 3000ms。
        val v = GlassSeekBarView.snapValue(
            14f + 772f * 0.26f, 772f, 14f, 0f, 100_000f, 1000f,
        )
        assertEquals(3000f, v, 1f)
    }

    @Test
    fun `snapValue and centerXOf are inverse`() {
        val min = 0f
        val max = 3600_000f
        for (ratio in floatArrayOf(0f, 0.25f, 0.5f, 0.9f, 1f)) {
            val x = 14f + 772f * ratio
            val v = GlassSeekBarView.snapValue(x, 772f, 14f, min, max, 0f)
            val back = GlassSeekBarView.centerXOf(v, 772f, 14f, min, max)
            assertEquals(x, back, 0.01f)
        }
    }

    @Test
    fun `centerXOf clamps value outside range`() {
        assertEquals(14f, GlassSeekBarView.centerXOf(-5f, 772f, 14f, 0f, 100f), 1e-4f)
        assertEquals(786f, GlassSeekBarView.centerXOf(500f, 772f, 14f, 0f, 100f), 1e-4f)
    }
}
