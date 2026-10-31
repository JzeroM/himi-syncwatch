package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Typeface
import com.himi.syncwatch.R

/**
 * 原生控制层图标码点（Material Icons）。
 *
 * 单一来源：tool/native_icons.json；Dart 侧镜像见 NativePlayerIcons。
 * 一致性由 test/native_player_icons_test.dart 校验，禁止手改单个数字。
 */
object NativePlayerIcons {
    const val FONT_FAMILY = "MaterialIcons"

    /** arrowBack */
    const val ICON_ARROW_BACK = 0xE092

    /** speed */
    const val ICON_SPEED = 0xE5E0

    /** tune */
    const val ICON_TUNE = 0xE683

    /** memory */
    const val ICON_MEMORY = 0xE3DB

    /** rotate */
    const val ICON_ROTATE = 0xF07BF

    /** fitScreen */
    const val ICON_FIT_SCREEN = 0xE28C

    /** fullscreen */
    const val ICON_FULLSCREEN = 0xE2CB

    /** zoomOutMap */
    const val ICON_ZOOM_OUT_MAP = 0xE6FF

    /** aspectRatio */
    const val ICON_ASPECT_RATIO = 0xE0A3

    /** danmakuOn */
    const val ICON_DANMAKU_ON = 0xE17E

    /** danmakuOff */
    const val ICON_DANMAKU_OFF = 0xF04D2

    /** highQuality */
    const val ICON_HIGH_QUALITY = 0xE30F

    /** subtitles */
    const val ICON_SUBTITLES = 0xE619

    /** audioTrack */
    const val ICON_AUDIO_TRACK = 0xE0B6

    /** playlistPlay */
    const val ICON_PLAYLIST_PLAY = 0xE4D4

    /** skipPrevious */
    const val ICON_SKIP_PREVIOUS = 0xE5BE

    /** playCircle */
    const val ICON_PLAY_CIRCLE = 0xE4CD

    /** pauseCircle */
    const val ICON_PAUSE_CIRCLE = 0xE47E

    /** skipNext */
    const val ICON_SKIP_NEXT = 0xE5BD

    /** lock */
    const val ICON_LOCK = 0xE3AE

    /** lockOpen */
    const val ICON_LOCK_OPEN = 0xE3B0

    /** check */
    const val ICON_CHECK = 0xE156

    /** chevronRight */
    const val ICON_CHEVRON_RIGHT = 0xE15F

    /** expandMore */
    const val ICON_EXPAND_MORE = 0xE246

    /** close */
    const val ICON_CLOSE = 0xE16A

    /** campaign */
    const val ICON_CAMPAIGN = 0xE138

    /** people */
    const val ICON_PEOPLE = 0xE486

    /** volumeUp */
    const val ICON_VOLUME_UP = 0xE6C5

    /** volumeDown */
    const val ICON_VOLUME_DOWN = 0xE6C2

    /** volumeOff */
    const val ICON_VOLUME_OFF = 0xE6C4

    /** brightness */
    const val ICON_BRIGHTNESS = 0xE10A

    /** fastForward */
    const val ICON_FAST_FORWARD = 0xE258

    /** add */
    const val ICON_ADD = 0xE047

    /** delete */
    const val ICON_DELETE = 0xE1BB

    /** restartAlt */
    const val ICON_RESTART_ALT = 0xE531

    /** photoCamera */
    const val ICON_PHOTO_CAMERA = 0xE4B6

    /** bugReport */
    const val ICON_BUG_REPORT = 0xE115

    /** movie */
    const val ICON_MOVIE = 0xE40D

    /** search */
    const val ICON_SEARCH = 0xE567

    /** replay */
    const val ICON_REPLAY = 0xE523

    /** forward10 */
    const val ICON_FORWARD10 = 0xE2C5

    /** replay10 */
    const val ICON_REPLAY10 = 0xE524

    /** openInFull */
    const val ICON_OPEN_IN_FULL = 0xE45B

    /** closeFullscreen */
    const val ICON_CLOSE_FULLSCREEN = 0xE16B

    /** share */
    const val ICON_SHARE = 0xE593

    // ── 字体加载（内置 res/font/material_icons.otf）────────────────

    @Volatile
    private var cached: Typeface? = null

    /**
     * 内置图标字体：res/font/material_icons.otf（经资源 ID 加载）。
     *
     * 为什么走 res/font 而不是 assets：`android/app/src/main/assets/`
     * 会与 Flutter 的 `flutter_assets` 合并目录冲突，冲突时 Flutter 引擎
     * 加载不到资源 → 整个 APK 黑屏。res/font 走 Android 资源管线，
     * 与 Flutter 资源完全隔离。
     *
     * 加载失败（文件被裁剪/资源未打进 APK）时回退系统默认字体——图标
     * 显示成方框/缺字，但不崩溃（渲染层其余控件不受影响）。
     */
    fun typeface(context: Context): Typeface {
        cached?.let { return it }
        return try {
            @Suppress("DEPRECATION")
            val tf = context.resources.getFont(R.font.material_icons)
            cached = tf
            tf
        } catch (_: Throwable) {
            Typeface.DEFAULT
        }
    }
}
