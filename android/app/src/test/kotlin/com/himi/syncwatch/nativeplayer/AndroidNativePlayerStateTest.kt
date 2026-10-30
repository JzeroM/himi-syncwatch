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

    // ── Phase 2.5 控制层字段 ──────────────────────────────────────

    @Test
    fun `解析控制层字段`() {
        val json = JSONObject(
            """
            {
              "logoUrl":"https://x/logo.png",
              "networkSpeedText":"2.09 MB/s",
              "clockFormat":"24h",
              "glassUi":false,
              "engineLabel":"MDK",
              "engineOptions":[
                {"id":"mdk","label":"MDK","description":"兼容内核"},
                {"id":"mpv","label":"MPV","description":"默认内核"}
              ],
              "videoFit":"cover",
              "decodeMode":"sw",
              "subtitleScale":1.35,
              "subtitleMarginY":48,
              "subtitleDelayEnabled":true,
              "subtitleStyleDisabled":true,
              "danmakuEnabled":true,
              "danmakuSpeed":1.5,
              "danmakuFontSize":1.2,
              "danmakuOpacity":0.4,
              "segmentEnabled":true,
              "segmentIntroEndMs":90000,
              "segmentOutroStartMs":1400000,
              "showDebug":true,
              "isRoom":true,
              "canScreenshot":true,
              "audioStreamCount":3,
              "subtitleStreamCount":5
            }
            """.trimIndent(),
        )

        val state = AndroidNativePlayerState.fromJson(json)

        assertEquals("https://x/logo.png", state.logoUrl)
        assertEquals("2.09 MB/s", state.networkSpeedText)
        assertEquals("24h", state.clockFormat)
        assertFalse(state.glassUi)
        assertEquals("MDK", state.engineLabel)
        assertEquals(2, state.engineOptions.size)
        assertEquals("mdk", state.engineOptions[0].id)
        assertEquals("MDK", state.engineOptions[0].label)
        assertEquals("兼容内核", state.engineOptions[0].description)
        assertEquals("mpv", state.engineOptions[1].id)
        assertEquals("cover", state.videoFit)
        assertEquals("sw", state.decodeMode)
        assertEquals(1.35, state.subtitleScale, 1e-9)
        assertEquals(48, state.subtitleMarginY)
        assertTrue(state.subtitleDelayEnabled)
        assertTrue(state.subtitleStyleDisabled)
        assertTrue(state.danmakuEnabled)
        assertEquals(1.5, state.danmakuSpeed, 1e-9)
        assertEquals(1.2, state.danmakuFontSize, 1e-9)
        assertEquals(0.4, state.danmakuOpacity, 1e-9)
        assertTrue(state.segmentEnabled)
        assertEquals(90000, state.segmentIntroEndMs)
        assertEquals(1400000, state.segmentOutroStartMs)
        assertTrue(state.showDebug)
        assertTrue(state.isRoom)
        assertTrue(state.canScreenshot)
        assertEquals(3, state.audioStreamCount)
        assertEquals(5, state.subtitleStreamCount)
    }

    @Test
    fun `控制层字段缺省回落默认值`() {
        val state = AndroidNativePlayerState.fromJson(JSONObject("""{"positionMs":10}"""))

        assertNull(state.logoUrl)
        assertNull(state.networkSpeedText)
        assertEquals("off", state.clockFormat)
        assertTrue(state.glassUi)
        assertEquals("MPV", state.engineLabel)
        assertTrue(state.engineOptions.isEmpty())
        assertEquals("contain", state.videoFit)
        assertEquals("auto", state.decodeMode)
        assertEquals(1.0, state.subtitleScale, 1e-9)
        assertEquals(22, state.subtitleMarginY)
        assertFalse(state.subtitleDelayEnabled)
        assertFalse(state.subtitleStyleDisabled)
        assertFalse(state.danmakuEnabled)
        assertEquals(1.0, state.danmakuSpeed, 1e-9)
        assertEquals(0.5, state.danmakuFontSize, 1e-9)
        assertEquals(0.6, state.danmakuOpacity, 1e-9)
        assertFalse(state.segmentEnabled)
        assertNull(state.segmentIntroEndMs)
        assertNull(state.segmentOutroStartMs)
        assertFalse(state.showDebug)
        assertFalse(state.isRoom)
        assertFalse(state.canScreenshot)
        assertEquals(0, state.audioStreamCount)
        assertEquals(0, state.subtitleStreamCount)
    }

    @Test
    fun `片头片尾标记显式 null 回落 null`() {
        val state = AndroidNativePlayerState.fromJson(
            JSONObject("""{"segmentIntroEndMs":null,"segmentOutroStartMs":null}"""),
        )
        assertNull(state.segmentIntroEndMs)
        assertNull(state.segmentOutroStartMs)
    }

    @Test
    fun `引擎选项数组里非对象元素被跳过`() {
        val state = AndroidNativePlayerState.fromJson(
            JSONObject("""{"engineOptions":[{"id":"mpv","label":"MPV"},3,null]}"""),
        )
        assertEquals(1, state.engineOptions.size)
        assertEquals("mpv", state.engineOptions[0].id)
    }

    @Test
    fun `applyAdjustDisplay 范围夹取与 Dart clamp 一致`() {
        val base = AndroidNativePlayerState()

        // subtitleScale 0.5..3.0
        assertEquals(
            0.5,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleScale", 0.1).subtitleScale,
            1e-9,
        )
        assertEquals(
            3.0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleScale", 9.0).subtitleScale,
            1e-9,
        )
        assertEquals(
            1.35,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleScale", 1.35).subtitleScale,
            1e-9,
        )

        // subtitleMarginY 0..200（取整）
        assertEquals(
            0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleMarginY", -10.0).subtitleMarginY,
        )
        assertEquals(
            200,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleMarginY", 999.0).subtitleMarginY,
        )
        assertEquals(
            48,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleMarginY", 48.0).subtitleMarginY,
        )

        // subtitleDelayMs -5000..5000
        assertEquals(
            -5000.0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleDelayMs", -99999.0).subtitleDelayMs,
            1e-9,
        )
        assertEquals(
            5000.0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "subtitleDelayMs", 99999.0).subtitleDelayMs,
            1e-9,
        )

        // danmakuSpeed 0.5..2.0
        assertEquals(
            0.5,
            AndroidNativePlayerState.applyAdjustDisplay(base, "danmakuSpeed", 0.1).danmakuSpeed,
            1e-9,
        )
        assertEquals(
            2.0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "danmakuSpeed", 5.0).danmakuSpeed,
            1e-9,
        )

        // danmakuFontSize 0.5..2.0
        assertEquals(
            0.5,
            AndroidNativePlayerState.applyAdjustDisplay(base, "danmakuFontSize", 0.1).danmakuFontSize,
            1e-9,
        )
        assertEquals(
            2.0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "danmakuFontSize", 5.0).danmakuFontSize,
            1e-9,
        )

        // danmakuOpacity 0.1..1.0
        assertEquals(
            0.1,
            AndroidNativePlayerState.applyAdjustDisplay(base, "danmakuOpacity", 0.01).danmakuOpacity,
            1e-9,
        )
        assertEquals(
            1.0,
            AndroidNativePlayerState.applyAdjustDisplay(base, "danmakuOpacity", 9.0).danmakuOpacity,
            1e-9,
        )
    }

    @Test
    fun `applyAdjustDisplay 未知 key 返回原状态`() {
        val base = AndroidNativePlayerState(subtitleScale = 1.5)
        val next = AndroidNativePlayerState.applyAdjustDisplay(base, "brightness", 0.5)
        assertEquals(1.5, next.subtitleScale, 1e-9)
    }

    @Test
    fun `播放器时间格式化对齐 Flutter formatPlayerDuration`() {
        // 无小时：MM:SS（分钟补零）
        assertEquals("00:00", AndroidNativePlayerState.formatPlayerTime(0))
        assertEquals("00:09", AndroidNativePlayerState.formatPlayerTime(9_000))
        assertEquals("01:05", AndroidNativePlayerState.formatPlayerTime(65_000))
        assertEquals("05:03", AndroidNativePlayerState.formatPlayerTime(303_000))
        // 有小时：HH:MM:SS（全补零）
        assertEquals("01:00:00", AndroidNativePlayerState.formatPlayerTime(3_600_000))
        assertEquals("02:03:04", AndroidNativePlayerState.formatPlayerTime(7_384_000))
        // 负数按 0
        assertEquals("00:00", AndroidNativePlayerState.formatPlayerTime(-5))
    }
}
