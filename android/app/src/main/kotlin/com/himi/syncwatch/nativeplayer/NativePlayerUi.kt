package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 原生控制层视觉规格（Android 侧）：与 Dart
 * `lib/services/player/native/native_player_theme.dart` 的 `NativePlayerTheme`
 * 逐项同值（`test/native_player_theme_test.dart` 做跨语言一致性校验）。
 *
 * 颜色均为 `0xAARRGGBB` Int，尺寸单位 dp / sp（与 Flutter 逻辑像素 1:1）。
 */
internal object NPTheme {
    // ── 基础色 ──
    const val ACCENT = 0xFF6366F1.toInt()
    const val ACCENT_SOFT = 0x4D6366F1
    const val WHITE = 0xFFFFFFFF.toInt()
    const val WHITE_70 = 0xB3FFFFFF.toInt()
    const val WHITE_54 = 0x8AFFFFFF.toInt()
    const val WHITE_38 = 0x62FFFFFF.toInt()
    const val WHITE_24 = 0x3DFFFFFF.toInt()

    // ── 玻璃 / 浮层 ──
    const val PANEL_TINT = 0x1F1A1D23
    const val FALLBACK_TINT = 0x1A1A1D23
    const val RIM = 0x4DFFFFFF
    const val DECODE_PANEL = 0xFF1E1E2E.toInt()
    const val DECODE_CURRENT_TEXT = 0xFFA5B4FC.toInt()
    const val FOCUS_RING = 0xFFC1C2FE.toInt()
    const val SHADOW = 0x4A000000

    /** 顶/底栏渐变（Flutter 侧 `0xCC000000` → transparent）。 */
    const val BAR_GRADIENT_SOLID = 0xCC000000.toInt()
    const val BAR_GRADIENT_CLEAR = 0x00000000

    // ── 圆角 ──
    const val RADIUS_PANEL = 16
    const val RADIUS_CHIP = 10
    const val RADIUS_CARD = 18
    const val RADIUS_DECODE = 8
    const val RADIUS_BADGE = 9

    // ── 液态玻璃（对齐 Dart NativePlayerTheme / Flutter GlassConfig）──
    const val GLASS_BLUR_RADIUS = 20f
    const val GLASS_SATURATION = 1.6f
    const val GLASS_HIGHLIGHT_TOP = 0xB3FFFFFF.toInt()
    const val GLASS_HIGHLIGHT_BOTTOM = 0x00FFFFFF
    const val GLASS_INNER_RIM = 0x33000000.toInt()
    const val GLASS_REFRACTION_BAND = 10
    const val GLASS_REFRACTION_ZOOM = 1.12f
    const val GLASS_BLUR_DOWNSAMPLE = 4

    // ── 顶栏 ──
    const val TOP_BAR_HEIGHT = 48
    const val TOP_ICON_SIZE = 22
    const val TOP_CHIP_ICON_SIZE = 18
    const val TITLE_SIZE = 16f
    const val CAPTION_SIZE = 12f

    /** 胶囊内边距（内核/字幕样式/解码）。 */
    const val CHIP_PAD_H = 9
    const val CHIP_PAD_V = 6

    /** TV 时钟 100×48，右距 12，13sp white70。 */
    const val CLOCK_WIDTH = 100
    const val CLOCK_HEIGHT = 48
    const val CLOCK_RIGHT = 12
    const val CLOCK_FONT_SIZE = 13f

    // ── 底栏 ──
    const val LOGO_WIDTH = 240
    const val LOGO_HEIGHT = 44

    /** 控制条内容左右内边距（Flutter `padding: fromLTRB(16, 10, 16, 12)`）。 */
    const val BAR_PAD_H = 16

    const val BAR_PAD_TOP = 10
    const val BAR_PAD_BOTTOM = 12

    /** 时间数显列宽：`56/78`（≥1h 用 78）。 */
    const val TIME_CELL = 56
    const val TIME_CELL_WIDE = 78

    /** 进度条 track 6 / thumb 8。 */
    const val SEEK_TRACK = 6
    const val SEEK_THUMB = 8

    /** TV 进度条焦点环 3px + blur14/spread1.5。 */
    const val SEEK_FOCUS_RING = 3
    const val SEEK_FOCUS_BLUR = 14f
    const val SEEK_FOCUS_SPREAD = 1.5f

    /** 播放组 28 / 36 / 28，间距 8。 */
    const val TRANSPORT_SIDE = 28
    const val TRANSPORT_PLAY = 36
    const val TRANSPORT_GAP = 8

    /** 右侧图标 24、间距 20。 */
    const val CONTROL_ICON = 24
    const val CONTROL_GAP = 20

    /** 角标 9sp，圆形，最小 14dp。 */
    const val BADGE_FONT = 9f
    const val BADGE_MIN = 14

    /** 锁钮 22。 */
    const val LOCK_ICON = 22

    // ── 面板 ──
    const val PANEL_WIDTH_RATIO = 0.42f
    const val PANEL_MIN_WIDTH = 260f
    const val PANEL_MAX_WIDTH = 320f
    const val PANEL_RIGHT = 12
    const val PANEL_TOP_OFFSET = 48
    const val PANEL_BOTTOM_OFFSET = 116

    const val PANEL_PAD_H = 16
    const val PANEL_PAD_V = 12

    const val PANEL_TITLE_SIZE = 15f
    const val PANEL_OPTION_SIZE = 14f
    const val PANEL_CHECK_SLOT = 18

    // ── 显示调节 ──
    const val ADJUST_LABEL_WIDTH = 44
    const val ADJUST_VALUE_WIDTH = 48
    const val ADJUST_ROW_PAD_H = 16
    const val ADJUST_ROW_PAD_V = 10
    const val SECTION_TITLE_SIZE = 11f

    // ── 解码模式 ──
    const val DECODE_PANEL_WIDTH = 180
    const val DECODE_TITLE_SIZE = 13f
    const val DECODE_VALUE_SIZE = 12f
    const val DECODE_DESC_SIZE = 10f
    const val DECODE_RADIO = 16

    // ── 片头片尾卡 ──
    const val SEGMENT_CARD_WIDTH = 360
    const val SEGMENT_TITLE_SIZE = 16f
    const val SEGMENT_ROW_ICON = 22
    const val SEGMENT_ROW_TITLE_SIZE = 14f
    const val SEGMENT_ROW_HINT_SIZE = 11f
    const val SEGMENT_CHEVRON = 18

    // ── 动效 ──
    const val CONTROLS_FADE_MS = 200
    const val AUTO_HIDE_MS = 5000
}
