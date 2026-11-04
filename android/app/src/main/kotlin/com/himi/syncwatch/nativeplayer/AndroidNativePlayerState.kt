package com.himi.syncwatch.nativeplayer

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

/** 面板轨道项（与 Dart `NativeTrack.toJson` 字段一致）。 */
data class AndroidTrack(
    val id: Int = 0,
    val type: String = "audio",
    val title: String = "",
    val lang: String = "",
    /** Emby 显示名（displayInfo）；空 = 回退 title/lang。 */
    val label: String = "",
    val selected: Boolean = false,
) {
    val displayLabel: String
        get() = when {
            label.isNotBlank() -> label
            title.isNotBlank() -> title
            lang.isNotBlank() -> lang
            else -> "轨 $id"
        }

    companion object {
        fun fromJson(o: JSONObject): AndroidTrack = AndroidTrack(
            id = o.optInt("id", 0),
            type = o.optString("type", "audio"),
            title = o.optString("title", ""),
            lang = o.optString("lang", ""),
            label = o.optString("label", ""),
            selected = o.optBoolean("selected", false),
        )
    }
}

/** 面板选集项（与 Dart `NativeEpisode.toJson` 一致）。 */
/** 原生弹幕项（与 Dart `NativeDanmakuItem.toJson` 字段一致）。 */
data class AndroidDanmakuItem(
    val timeMs: Int = 0,
    val text: String = "",
    val mode: String = "scroll",
    val color: String = "#FFFFFF",
) {
    companion object {
        fun fromJson(o: JSONObject): AndroidDanmakuItem = AndroidDanmakuItem(
            timeMs = o.optInt("timeMs", 0),
            text = o.optString("text", ""),
            mode = o.optString("mode", "scroll"),
            color = o.optString("color", "#FFFFFF"),
        )
    }
}

/** 房间资源面板：一条可播放资源（590）。 */
data class AndroidResourceItem(
    val index: Int = 0,
    val name: String = "",
    val season: Int = 0,
    val number: Int = 0,
    val poster: String = "",
    val isPlaying: Boolean = false,
) {
    val isMovie: Boolean get() = season == 0 && number == 0

    /** 集码 `S01E03`；电影返回空串。 */
    val episodeCode: String
        get() {
            if (isMovie) return ""
            val s = if (season > 0) season.toString().padStart(2, '0') else "01"
            val e = if (number > 0) number.toString().padStart(2, '0') else "01"
            return "S${s}E$e"
        }

    companion object {
        fun fromJson(o: JSONObject): AndroidResourceItem = AndroidResourceItem(
            index = o.optInt("index", 0),
            name = o.optString("name", ""),
            season = o.optInt("season", 0),
            number = o.optInt("number", 0),
            poster = o.optString("poster", ""),
            isPlaying = o.optBoolean("isPlaying", false),
        )
    }
}

/** 房间资源面板：一个季分组。 */
data class AndroidSeasonGroup(
    val seasonNumber: Int = 0,
    val collapsed: Boolean = true,
    val episodes: List<AndroidResourceItem> = emptyList(),
) {
    companion object {
        fun fromJson(o: JSONObject): AndroidSeasonGroup = AndroidSeasonGroup(
            seasonNumber = o.optInt("seasonNumber", 0),
            collapsed = o.optBoolean("collapsed", true),
            episodes = o.optJSONArray("episodes")?.let { arr ->
                (0 until arr.length()).map {
                    AndroidResourceItem.fromJson(arr.getJSONObject(it))
                }
            } ?: emptyList(),
        )
    }
}

/** 房间资源面板：一个资源分组（电影单条 / 剧集多季）。 */
data class AndroidResourceGroup(
    val name: String = "",
    val isMovie: Boolean = false,
    val collapsed: Boolean = true,
    val seasons: List<AndroidSeasonGroup> = emptyList(),
) {
    val totalCount: Int get() = seasons.sumOf { it.episodes.size }

    /**
     * 分组标题右侧计数（电影 `(N)`、剧集 `(N集)`）。
     *
     * 【必须用 `${}` 包裹】Kotlin 的简单模板 `"$totalCount集"` 会把
     * `totalCount集` 整体当成一个标识符（中文字符是合法标识符字符）→
     * `Unresolved reference 'totalCount集'`（CI 编译失败）。
     */
    val countLabel: String get() = if (isMovie) "($totalCount)" else "(${totalCount}集)"

    companion object {
        fun fromJson(o: JSONObject): AndroidResourceGroup = AndroidResourceGroup(
            name = o.optString("name", ""),
            isMovie = o.optBoolean("isMovie", false),
            collapsed = o.optBoolean("collapsed", true),
            seasons = o.optJSONArray("seasons")?.let { arr ->
                (0 until arr.length()).map {
                    AndroidSeasonGroup.fromJson(arr.getJSONObject(it))
                }
            } ?: emptyList(),
        )
    }
}

data class AndroidEpisode(
    val index: Int = 0,
    val title: String = "",
    /** 剧集封面图 URL（选集卡片 16:9 缩略图；空 = 占位底色）。 */
    val poster: String = "",
    /** 集号（>0 时卡片标题 `1.集名`，与 Flutter cardTitle 一致）。 */
    val number: Int = 0,
) {
    val displayLabel: String
        get() = if (title.isNotBlank()) title else "第 ${index + 1} 集"

    /** 卡片标题：`1.集名`（number>0），否则原名。 */
    val cardTitle: String
        get() = if (number > 0) "$number.$title" else title
}

/** 面板版本/线路项（与 Dart `NativeVersion.toJson` 一致）。 */
data class AndroidVersion(val index: Int = 0, val title: String = "") {
    val displayLabel: String
        get() = if (title.isNotBlank()) title else "线路 ${index + 1}"
}

/** 内核面板选项（与 Dart `NativeEngineOption.toJson` 一致）。 */
data class AndroidEngineOption(
    val id: String = "",
    val label: String = "",
    val description: String = "",
) {
    companion object {
        fun fromJson(o: JSONObject): AndroidEngineOption = AndroidEngineOption(
            id = o.optString("id", ""),
            label = o.optString("label", ""),
            description = o.optString("description", ""),
        )
    }
}

/**
 * 原生播放器 UI 的权威状态模型（Dart → 原生）。
 *
 * 【为什么与 Compose/Android 类型解耦】
 * `lib/services/player/native/native_player_state.dart` 是唯一权威状态源，
 * 原生侧只做「覆盖本地状态 + 插值外推进度」。把状态模型做成不依赖 Android
 * 框架的普通 Kotlin 类，就能在 CI 和本机用纯 JVM 单测验证解析与插值，
 * Compose 层只读它、不写它。
 *
 * 字段名与 Dart 侧 `toJson()` **逐字一致**；改动任一键名必须同步改 Dart
 * 侧并跑 `AndroidNativePlayerStateTest`。
 */
data class AndroidNativePlayerState(
    // 输出与 HDR 诊断
    val engine: String = "mpv",
    val videoOutputRequested: String = "surface",
    val videoOutputActual: String = "surface",
    val nativeSurface: Boolean = true,
    val textureId: Int = 0,
    val hdrOutput: Boolean = false,
    val displayHdr: Boolean = false,
    val targetTrc: String = "auto",
    val voConfigured: String? = null,
    val currentVo: String? = null,
    val hwdecCurrent: String? = null,
    // Surface 诊断
    val surfaceAttached: Boolean = false,
    val surfaceId: String? = null,
    val surfaceError: String? = null,
    val surfaceWidth: Int = 0,
    val surfaceHeight: Int = 0,
    // 播放
    val positionMs: Int = 0,
    val durationMs: Int = 0,
    val bufferedMs: Int = 0,
    val paused: Boolean = true,
    val buffering: Boolean = false,
    /**
     * 加载指示器是否显示（586，三端统一）。
     *
     * Dart 侧按 `PlayerScreen.shouldShowLoadingSpinner`（首帧未出 **或**
     * 缓冲中）算好后随快照下发；宿主只读这一位，不再自己判 [buffering]。
     */
    val showLoading: Boolean = false,
    val ended: Boolean = false,
    val volume: Double = 1.0,
    val speed: Double = 1.0,
    // 媒体
    val title: String? = null,
    val mediaTitle: String? = null,
    val videoParams: String? = null,
    val audioParams: String? = null,
    // 其他
    val locked: Boolean = false,
    val tvMode: Boolean = false,
    val canControl: Boolean = true,
    val debugLines: List<String> = emptyList(),
    // ── Phase 2 面板数据 ──
    val tracks: List<AndroidTrack> = emptyList(),
    val episodes: List<AndroidEpisode> = emptyList(),
    val versions: List<AndroidVersion> = emptyList(),
    val selectedAudioId: Int = 0,
    val selectedSubtitleId: Int = 0,
    val subtitleDelayMs: Double = 0.0,
    val currentEpisodeIndex: Int = 0,
    val currentVersionIndex: Int = 0,
    // ── Phase 2.5 控制层布局/样式 ──
    val logoUrl: String? = null,
    val networkSpeedText: String? = null,
    val clockFormat: String = "off",
    val glassUi: Boolean = true,
    val engineLabel: String = "MPV",
    val engineOptions: List<AndroidEngineOption> = emptyList(),
    val videoFit: String = "contain",
    val decodeMode: String = "auto",
    val subtitleScale: Double = 1.0,
    val subtitleMarginY: Int = 22,
    val subtitleDelayEnabled: Boolean = false,
    val subtitleStyleDisabled: Boolean = false,
    val danmakuEnabled: Boolean = false,
    val danmakuSpeed: Double = 1.0,
    val danmakuFontSize: Double = 0.5,
    val danmakuOpacity: Double = 0.6,
    /** 弹幕行数（滚动 = 上限按屏高自适应；顶/底 = 行数）与数量上限（null = 不限）。 */
    val danmakuScrollRows: Int = 30,
    val danmakuTopRows: Int = 4,
    val danmakuBottomRows: Int = 4,
    val danmakuMaxCount: Int? = null,
    /** 弹幕时间窗（原生渲染；Dart 按 [当前位置-2s,+30s] 切窗推送）。 */
    val danmakuItems: List<AndroidDanmakuItem> = emptyList(),
    // ── 房间资源面板（590）──
    val roomCode: String? = null,
    val isHost: Boolean = false,
    val onlineUserCount: Int = 0,
    val audienceName: String? = null,
    val resourceGroups: List<AndroidResourceGroup> = emptyList(),
    val broadcasts: List<String> = emptyList(),
    val resourcePanelOpen: Boolean = true,
    val segmentEnabled: Boolean = false,
    val segmentIntroEndMs: Int? = null,
    val segmentOutroStartMs: Int? = null,
    /** 跳过片头/片尾提示（'' = 隐藏，'intro' / 'outro'；Dart `_skipPromptSegment` 驱动）。 */
    val skipPrompt: String = "",
    val showDebug: Boolean = false,
    val isRoom: Boolean = false,
    val canScreenshot: Boolean = false,
    val audioStreamCount: Int = 0,
    val subtitleStreamCount: Int = 0,
) {
    /** 最该展示的标题：显式标题 > 媒体标题 > 空串。 */
    val displayTitle: String
        get() = title?.takeIf { it.isNotBlank() }
            ?: mediaTitle?.takeIf { it.isNotBlank() }
            ?: ""

    /**
     * 快照生成时刻 [snapshotAtMs] 起外推到 [nowMs] 的进度（毫秒）。
     *
     * 暂停 / 缓冲 / 播放结束 / 倍速 <= 0 时保持 [positionMs] 不动；外推
     * 不越过 [durationMs]（时长未知 <= 0 时不封顶），也不为负。与 Dart 侧
     * `NativePlayerState.interpolatedPositionMs` 语义一致。
     */
    fun positionAt(nowMs: Long, snapshotAtMs: Long): Long {
        if (paused || buffering || ended || speed <= 0) return positionMs.toLong()
        val delta = ((nowMs - snapshotAtMs) * speed).toLong()
        val projected = positionMs + delta
        val capped = if (durationMs > 0 && projected > durationMs) {
            durationMs.toLong()
        } else {
            projected
        }
        return if (capped < 0) 0 else capped
    }

    /** 进度比例 0..1；时长未知时为 0。 */
    fun progress(nowMs: Long, snapshotAtMs: Long): Double {
        if (durationMs <= 0) return 0.0
        return (positionAt(nowMs, snapshotAtMs).toDouble() / durationMs).coerceIn(0.0, 1.0)
    }

    /** 时长未知（直播 / 转码 HLS / 仍在解析）。 */
    val isLiveLike: Boolean get() = durationMs <= 0

    companion object {
        /** 时长/进度文本（`mm:ss` 或 `h:mm:ss`），toast 与进度条共用。 */
        fun formatTime(ms: Long): String {
            val total = if (ms < 0) 0L else ms / 1000
            val h = total / 3600
            val m = (total % 3600) / 60
            val s = total % 60
            return if (h > 0) {
                "$h:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}"
            } else {
                "$m:${s.toString().padStart(2, '0')}"
            }
        }

        /**
         * 显示调节命令（adjustDisplay）→ 状态字段乐观更新。
         *
         * 键名与 Dart `NativePlayerCommand.adjustDisplay` 的 key 一一对应；
         * 范围夹取与 Dart `_applyNativeAdjustDisplay` 的 clamp 保持一致。
         * 未知 key 原样返回（不改状态，协议向前兼容）。
         */
        fun applyAdjustDisplay(
            state: AndroidNativePlayerState,
            key: String,
            value: Double,
        ): AndroidNativePlayerState = when (key) {
            "subtitleScale" -> state.copy(subtitleScale = value.coerceIn(0.5, 3.0))
            "subtitleMarginY" -> state.copy(subtitleMarginY = value.roundToInt().coerceIn(0, 200))
            "subtitleDelayMs" -> state.copy(subtitleDelayMs = value.roundToInt().coerceIn(-5000, 5000).toDouble())
            "danmakuSpeed" -> state.copy(danmakuSpeed = value.coerceIn(0.5, 2.0))
            "danmakuFontSize" -> state.copy(danmakuFontSize = value.coerceIn(0.5, 2.0))
            "danmakuOpacity" -> state.copy(danmakuOpacity = value.coerceIn(0.1, 1.0))
            else -> state
        }

        /**
         * 进度条两侧数显（对齐 Flutter `formatPlayerDuration`）：
         * 有小时 `HH:MM:SS`（全补零），否则 `MM:SS`（分钟补零）。
         */
        fun formatPlayerTime(ms: Long): String {
            val total = if (ms < 0) 0L else ms / 1000
            val h = total / 3600
            val m = (total % 3600) / 60
            val s = total % 60
            val mm = m.toString().padStart(2, '0')
            val ss = s.toString().padStart(2, '0')
            return if (h > 0) {
                "${h.toString().padStart(2, '0')}:$mm:$ss"
            } else {
                "$mm:$ss"
            }
        }

        /**
         * Dart 推送 JSON（`NativePlayerState.toJson()`）→ 原生状态。
         * 缺字段一律回落到默认值（不用 getString 抛异常），保证协议向前
         * 兼容：Dart 后续加字段不会让旧原生壳崩。
         */
        fun fromJson(json: JSONObject): AndroidNativePlayerState = AndroidNativePlayerState(
            engine = json.optString("engine", "mpv"),
            videoOutputRequested = json.optString("videoOutputRequested", "surface"),
            videoOutputActual = json.optString("videoOutputActual", "surface"),
            nativeSurface = json.optBoolean("nativeSurface", true),
            textureId = json.optInt("textureId", 0),
            hdrOutput = json.optBoolean("hdrOutput", false),
            displayHdr = json.optBoolean("displayHdr", false),
            targetTrc = json.optString("targetTrc", "auto"),
            voConfigured = json.optNullableString("voConfigured"),
            currentVo = json.optNullableString("currentVo"),
            hwdecCurrent = json.optNullableString("hwdecCurrent"),
            surfaceAttached = json.optBoolean("surfaceAttached", false),
            surfaceId = json.optNullableString("surfaceId"),
            surfaceError = json.optNullableString("surfaceError"),
            surfaceWidth = json.optInt("surfaceWidth", 0),
            surfaceHeight = json.optInt("surfaceHeight", 0),
            positionMs = json.optInt("positionMs", 0),
            durationMs = json.optInt("durationMs", 0),
            bufferedMs = json.optInt("bufferedMs", 0),
            paused = json.optBoolean("paused", true),
            buffering = json.optBoolean("buffering", false),
            showLoading = json.optBoolean("showLoading", false),
            ended = json.optBoolean("ended", false),
            volume = json.optDouble("volume", 1.0),
            speed = json.optDouble("speed", 1.0),
            title = json.optNullableString("title"),
            mediaTitle = json.optNullableString("mediaTitle"),
            videoParams = json.optNullableString("videoParams"),
            audioParams = json.optNullableString("audioParams"),
            locked = json.optBoolean("locked", false),
            tvMode = json.optBoolean("tvMode", false),
            canControl = json.optBoolean("canControl", true),
            debugLines = json.optStringList("debugLines"),
            tracks = json.optTrackList("tracks"),
            episodes = json.optEpisodeList("episodes"),
            versions = json.optVersionList("versions"),
            selectedAudioId = json.optInt("selectedAudioId", 0),
            selectedSubtitleId = json.optInt("selectedSubtitleId", 0),
            subtitleDelayMs = json.optDouble("subtitleDelayMs", 0.0),
            currentEpisodeIndex = json.optInt("currentEpisodeIndex", 0),
            currentVersionIndex = json.optInt("currentVersionIndex", 0),
            logoUrl = json.optNullableString("logoUrl"),
            networkSpeedText = json.optNullableString("networkSpeedText"),
            clockFormat = json.optString("clockFormat", "off"),
            glassUi = json.optBoolean("glassUi", true),
            engineLabel = json.optString("engineLabel", "MPV"),
            engineOptions = json.optEngineList("engineOptions"),
            videoFit = json.optString("videoFit", "contain"),
            decodeMode = json.optString("decodeMode", "auto"),
            subtitleScale = json.optDouble("subtitleScale", 1.0),
            subtitleMarginY = json.optInt("subtitleMarginY", 22),
            subtitleDelayEnabled = json.optBoolean("subtitleDelayEnabled", false),
            subtitleStyleDisabled = json.optBoolean("subtitleStyleDisabled", false),
            danmakuEnabled = json.optBoolean("danmakuEnabled", false),
            danmakuSpeed = json.optDouble("danmakuSpeed", 1.0),
            danmakuFontSize = json.optDouble("danmakuFontSize", 0.5),
            danmakuOpacity = json.optDouble("danmakuOpacity", 0.6),
            danmakuScrollRows = json.optInt("danmakuScrollRows", 30),
            danmakuTopRows = json.optInt("danmakuTopRows", 4),
            danmakuBottomRows = json.optInt("danmakuBottomRows", 4),
            danmakuMaxCount = if (json.has("danmakuMaxCount") && !json.isNull("danmakuMaxCount")) {
                json.optInt("danmakuMaxCount", 0)
            } else {
                null
            },
            danmakuItems = json.optJSONArray("danmakuItems")?.let { arr ->
                (0 until arr.length()).map { AndroidDanmakuItem.fromJson(arr.getJSONObject(it)) }
            } ?: emptyList(),
            roomCode = if (json.has("roomCode") && !json.isNull("roomCode")) {
                json.optString("roomCode", "")
            } else {
                null
            },
            isHost = json.optBoolean("isHost", false),
            onlineUserCount = json.optInt("onlineUserCount", 0),
            audienceName = if (json.has("audienceName") && !json.isNull("audienceName")) {
                json.optString("audienceName", "")
            } else {
                null
            },
            resourceGroups = json.optJSONArray("resourceGroups")?.let { arr ->
                (0 until arr.length()).map {
                    AndroidResourceGroup.fromJson(arr.getJSONObject(it))
                }
            } ?: emptyList(),
            broadcasts = json.optJSONArray("broadcasts")?.let { arr ->
                (0 until arr.length()).map { arr.optString(it, "") }
            } ?: emptyList(),
            resourcePanelOpen = json.optBoolean("resourcePanelOpen", true),
            segmentEnabled = json.optBoolean("segmentEnabled", false),
            segmentIntroEndMs = json.optNullableInt("segmentIntroEndMs"),
            segmentOutroStartMs = json.optNullableInt("segmentOutroStartMs"),
            skipPrompt = json.optString("skipPrompt", ""),
            showDebug = json.optBoolean("showDebug", false),
            isRoom = json.optBoolean("isRoom", false),
            canScreenshot = json.optBoolean("canScreenshot", false),
            audioStreamCount = json.optInt("audioStreamCount", 0),
            subtitleStreamCount = json.optInt("subtitleStreamCount", 0),
        )

        /** org.json 没有 isNull 判断的便捷方法：null / JSONObject.NULL → null。 */
        fun JSONObject.optNullableString(key: String): String? =
            if (!has(key) || isNull(key)) null else optString(key, "")

        /** 可空整数（片头片尾标记）：缺省 / null → null。 */
        fun JSONObject.optNullableInt(key: String): Int? =
            if (!has(key) || isNull(key)) null else optInt(key, 0)

        /** 内核选项数组；非数组或元素非对象时跳过该项。 */
        fun JSONObject.optEngineList(key: String): List<AndroidEngineOption> {
            val arr = optJSONArray(key) ?: return emptyList()
            val out = ArrayList<AndroidEngineOption>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.opt(i) as? JSONObject ?: continue
                out.add(AndroidEngineOption.fromJson(o))
            }
            return out
        }

        /** 字符串数组；非数组或元素非字符串时跳过该项。 */
        fun JSONObject.optStringList(key: String): List<String> {
            val arr = optJSONArray(key) ?: return emptyList()
            val out = ArrayList<String>(arr.length())
            for (i in 0 until arr.length()) {
                val v = arr.opt(i)
                if (v is String) out.add(v)
            }
            return out
        }

        /** 轨道数组；非数组或元素非对象时跳过该项。 */
        fun JSONObject.optTrackList(key: String): List<AndroidTrack> {
            val arr = optJSONArray(key) ?: return emptyList()
            return arr.toTrackList()
        }

        /** 选集数组。 */
        fun JSONObject.optEpisodeList(key: String): List<AndroidEpisode> {
            val arr = optJSONArray(key) ?: return emptyList()
            val out = ArrayList<AndroidEpisode>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.opt(i) as? JSONObject ?: continue
                out.add(
                    AndroidEpisode(
                        index = o.optInt("index", 0),
                        title = o.optString("title", ""),
                        poster = o.optString("poster", ""),
                        number = o.optInt("number", 0),
                    ),
                )
            }
            return out
        }

        /** 版本/线路数组。 */
        fun JSONObject.optVersionList(key: String): List<AndroidVersion> {
            val arr = optJSONArray(key) ?: return emptyList()
            val out = ArrayList<AndroidVersion>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.opt(i) as? JSONObject ?: continue
                out.add(
                    AndroidVersion(
                        index = o.optInt("index", 0),
                        title = o.optString("title", ""),
                    ),
                )
            }
            return out
        }

        private fun JSONArray.toTrackList(): List<AndroidTrack> {
            val out = ArrayList<AndroidTrack>(length())
            for (i in 0 until length()) {
                val o = opt(i) as? JSONObject ?: continue
                out.add(AndroidTrack.fromJson(o))
            }
            return out
        }
    }
}
