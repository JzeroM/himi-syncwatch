package com.himi.syncwatch.nativeplayer

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Android 原生播放器状态层单测（纯 JVM，无需 Android SDK）。
 *
 * 覆盖三条契约：
 * 1. Dart `NativePlayerState.toJson()` 全字段解析（键名逐字对齐）；
 * 2. 缺字段/显式 null 一律回落默认值（协议向前兼容）；
 * 3. 进度插值边界：暂停/缓冲/结束/倍速 0 不动、封顶、不为负、时长未知不封顶。
 */
class AndroidNativePlayerStateTest {

    @Test
    fun `解析 Dart 推送的完整快照`() {
        val json = JSONObject(
            """
            {
              "engine":"mpv","videoOutputRequested":"surface","videoOutputActual":"surface",
              "nativeSurface":true,"textureId":0,"hdrOutput":true,"displayHdr":true,
              "targetTrc":"pq","voConfigured":"gpu-next","currentVo":"gpu-next",
              "hwdecCurrent":"ohcodec","surfaceAttached":true,"surfaceId":"surf-1",
              "surfaceWidth":1920,"surfaceHeight":1080,
              "positionMs":65000,"durationMs":3600000,"bufferedMs":120000,
              "paused":false,"buffering":false,"ended":false,"volume":0.8,"speed":1.5,
              "title":"第 3 集","mediaTitle":"Show.S01E03.mkv",
              "debugLines":["vo=gpu-next | hwdec=ohcodec","HDR"]
            }
            """.trimIndent(),
        )

        val state = AndroidNativePlayerState.fromJson(json)

        assertEquals("mpv", state.engine)
        assertEquals("surface", state.videoOutputActual)
        assertTrue(state.nativeSurface)
        assertTrue(state.hdrOutput)
        assertEquals("pq", state.targetTrc)
        assertEquals("gpu-next", state.currentVo)
        assertEquals("ohcodec", state.hwdecCurrent)
        assertTrue(state.surfaceAttached)
        assertEquals("surf-1", state.surfaceId)
        assertEquals(1920, state.surfaceWidth)
        assertEquals(65000, state.positionMs)
        assertEquals(3600000, state.durationMs)
        assertFalse(state.paused)
        assertEquals(1.5, state.speed, 1e-9)
        assertEquals("第 3 集", state.title)
        assertEquals(listOf("vo=gpu-next | hwdec=ohcodec", "HDR"), state.debugLines)
        // 显式标题优先于媒体标题
        assertEquals("第 3 集", state.displayTitle)
    }

    @Test
    fun `缺字段与显式 null 回落默认值`() {
        val state = AndroidNativePlayerState.fromJson(JSONObject("""{"positionMs":10}"""))

        assertEquals("mpv", state.engine)
        assertEquals("surface", state.videoOutputActual)
        assertTrue(state.nativeSurface)
        assertEquals(0, state.durationMs)
        assertEquals(10, state.positionMs)
        assertTrue("缺省应视为暂停", state.paused)
        assertTrue(state.canControl)
        assertNull(state.title)
        assertNull(state.voConfigured)
        assertTrue(state.debugLines.isEmpty())
        assertEquals("", state.displayTitle)
    }

    @Test
    fun `mediaTitle 在无 title 时兜底展示`() {
        val state = AndroidNativePlayerState.fromJson(
            JSONObject("""{"title":"","mediaTitle":"Episode 7"}"""),
        )
        assertEquals("Episode 7", state.displayTitle)
    }

    @Test
    fun `播放中外推进度`() {
        val state = AndroidNativePlayerState(
            positionMs = 10_000,
            durationMs = 60_000,
            paused = false,
            speed = 1.0,
        )
        assertEquals(11_500L, state.positionAt(nowMs = 1_500L, snapshotAtMs = 0L))
    }

    @Test
    fun `倍速影响外推速率`() {
        val state = AndroidNativePlayerState(
            positionMs = 0,
            durationMs = 0,
            paused = false,
            speed = 2.0,
        )
        assertEquals(4_000L, state.positionAt(nowMs = 2_000L, snapshotAtMs = 0L))
    }

    @Test
    fun `暂停 缓冲 结束 倍速为零时进度不动`() {
        val base = AndroidNativePlayerState(positionMs = 5_000, durationMs = 60_000, paused = false)
        assertEquals(5_000L, base.copy(paused = true).positionAt(9_999, 0))
        assertEquals(5_000L, base.copy(buffering = true).positionAt(9_999, 0))
        assertEquals(5_000L, base.copy(ended = true).positionAt(9_999, 0))
        assertEquals(5_000L, base.copy(speed = 0.0).positionAt(9_999, 0))
    }

    @Test
    fun `外推封顶于时长`() {
        val state = AndroidNativePlayerState(
            positionMs = 59_900,
            durationMs = 60_000,
            paused = false,
        )
        assertEquals(60_000L, state.positionAt(nowMs = 50_000, snapshotAtMs = 0))
        assertEquals(1.0, state.progress(nowMs = 50_000, snapshotAtMs = 0), 1e-9)
    }

    @Test
    fun `时长未知时不封顶且进度为 0`() {
        val state = AndroidNativePlayerState(
            positionMs = 1_000,
            durationMs = 0,
            paused = false,
        )
        assertEquals(11_000L, state.positionAt(nowMs = 10_000, snapshotAtMs = 0))
        assertEquals(0.0, state.progress(nowMs = 10_000, snapshotAtMs = 0), 1e-9)
        assertTrue(state.isLiveLike)
    }

    @Test
    fun `时钟回拨不产生负进度`() {
        val state = AndroidNativePlayerState(
            positionMs = 500,
            durationMs = 60_000,
            paused = false,
        )
        assertEquals(0L, state.positionAt(nowMs = 0, snapshotAtMs = 10_000))
    }

    @Test
    fun `时间文本格式化`() {
        assertEquals("0:00", AndroidNativePlayerState.formatTime(-5))
        assertEquals("0:09", AndroidNativePlayerState.formatTime(9_800))
        assertEquals("1:05", AndroidNativePlayerState.formatTime(65_000))
        assertEquals("1:00:00", AndroidNativePlayerState.formatTime(3_600_000))
        assertEquals("2:03:04", AndroidNativePlayerState.formatTime(7_384_000))
    }

    @Test
    fun `debugLines 里的非字符串项被跳过`() {
        val state = AndroidNativePlayerState.fromJson(
            JSONObject("""{"debugLines":["a",1,null,{"b":2},"c"]}"""),
        )
        assertEquals(listOf("a", "c"), state.debugLines)
    }

    @Test
    fun `解析面板轨道选集版本数据`() {
        val json = JSONObject(
            """
            {
              "tracks":[
                {"id":1,"type":"audio","title":"国语","lang":"zh","selected":true},
                {"id":2,"type":"audio","title":"","lang":"ja","selected":false},
                {"id":1,"type":"sub","title":"中字","lang":"zh","selected":false}
              ],
              "episodes":[{"index":0,"title":"第 1 集"},{"index":1,"title":""}],
              "versions":[{"index":0,"title":"蓝光"},{"index":1,"title":""}],
              "selectedAudioId":1,"selectedSubtitleId":0,
              "subtitleDelayMs":200.0,
              "currentEpisodeIndex":1,"currentVersionIndex":0
            }
            """.trimIndent(),
        )

        val state = AndroidNativePlayerState.fromJson(json)

        assertEquals(3, state.tracks.size)
        assertEquals(2, state.tracks.count { it.type == "audio" })
        assertEquals(1, state.tracks.count { it.type == "sub" })
        // 轨道显示名：title 优先，兜底 lang，再兜底「轨 N」
        assertEquals("国语", state.tracks[0].displayLabel)
        assertEquals("ja", state.tracks[1].displayLabel)
        assertEquals("轨 2", AndroidTrack(id = 2).displayLabel)
        assertTrue(state.tracks[0].selected)

        assertEquals(2, state.episodes.size)
        assertEquals("第 1 集", state.episodes[0].displayLabel)
        assertEquals("第 2 集", state.episodes[1].displayLabel)

        assertEquals(2, state.versions.size)
        assertEquals("蓝光", state.versions[0].displayLabel)
        assertEquals("线路 2", state.versions[1].displayLabel)

        assertEquals(1, state.selectedAudioId)
        assertEquals(0, state.selectedSubtitleId)
        assertEquals(200.0, state.subtitleDelayMs, 1e-9)
        assertEquals(1, state.currentEpisodeIndex)
        assertEquals(0, state.currentVersionIndex)
    }

    @Test
    fun `面板数据缺字段回落默认值`() {
        val state = AndroidNativePlayerState.fromJson(JSONObject("""{"positionMs":10}"""))
        assertTrue(state.tracks.isEmpty())
        assertTrue(state.episodes.isEmpty())
        assertTrue(state.versions.isEmpty())
        assertEquals(0, state.selectedAudioId)
        assertEquals(0, state.selectedSubtitleId)
        assertEquals(0.0, state.subtitleDelayMs, 1e-9)
    }

    @Test
    fun `轨道列表里非对象元素被跳过`() {
        val state = AndroidNativePlayerState.fromJson(
            JSONObject("""{"tracks":[{"id":1,"type":"audio"},2,null]}"""),
        )
        assertEquals(1, state.tracks.size)
        assertEquals(1, state.tracks[0].id)
    }
}
