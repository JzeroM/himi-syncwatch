package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.Drawable
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
    /** accent@0.30（Flutter 解码面板选中行底色）。 */
    const val ACCENT_30 = 0x4D6366F1
    const val WHITE = 0xFFFFFFFF.toInt()
    const val WHITE_70 = 0xB3FFFFFF.toInt()
    const val WHITE_54 = 0x8AFFFFFF.toInt()
    const val WHITE_38 = 0x62FFFFFF.toInt()
    const val WHITE_24 = 0x3DFFFFFF.toInt()
    /** white12（分隔线/次级描边；Flutter `Colors.white12`）。 */
    const val WHITE_12 = 0x1FFFFFFF.toInt()

    // ── 玻璃 / 浮层 ──
    const val PANEL_TINT = 0x1F1A1D23
    const val FALLBACK_TINT = 0x1A1A1D23
    const val RIM = 0x4DFFFFFF
    const val DECODE_PANEL = 0xFF1E1E2E.toInt()
    /** 解码当前值文字（585 起白底弹层用主色，旧 #A5B4FC 对比不足）。 */
    const val DECODE_CURRENT_TEXT = 0xFF6366F1.toInt()
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
    const val SECTION_TITLE_SIZE = 12f

    // ── 解码模式 ──
    const val DECODE_PANEL_WIDTH = 180
    const val DECODE_TITLE_SIZE = 15f
    const val DECODE_VALUE_SIZE = 14f
    const val DECODE_DESC_SIZE = 12f
    const val DECODE_RADIO = 16

    // ── 片头片尾卡 ──
    const val SEGMENT_CARD_WIDTH = 360
    const val SEGMENT_TITLE_SIZE = 15f
    const val SEGMENT_ROW_ICON = 22
    const val SEGMENT_ROW_TITLE_SIZE = 14f
    const val SEGMENT_ROW_HINT_SIZE = 12f
    const val SEGMENT_CHEVRON = 18

    // ── 播放器弹层「白底磨砂」调色板 ──
    //
    // 【范围铁律】仅用于播放器内的**弹出面板**（右侧侧栏 / 解码 popover /
    // 片头片尾卡）。顶栏、底栏、手势提示胶囊一律保持上面的深色常量
    // （浮在视频上必须是深色白字）。与 Flutter
    // `GlassConfig.playerPanel*` 逐值一致。

    /**
     * 暖白磨砂基色（90% 不透明）。
     *
     * 586 由 585 的纯白基色改暖白：纯白在暗适应状态下亮度差近 20:1，
     * 弹层一出现眼睛会本能躲闪；暖白（R>G>B 微弱偏暖）压住刺眼度，同时
     * 保证黑字在任意画面上可读。
     */
    const val PANEL_LIGHT_BASE = 0xE6F4F2EE.toInt()
    /** 竖向渐变：顶部提亮（菲涅尔近似）→ 基色 → 底部略透。 */
    const val PANEL_LIGHT_TOP = 0xF2FAF8F4.toInt()
    const val PANEL_LIGHT_BOTTOM = 0xD6EAE7E1.toInt()
    /** 暖白底定界描边（黑 15%；白描边在亮画面上会消失）。 */
    const val PANEL_LIGHT_RIM = 0x26000000
    /** 暖白面板投影（浅底靠投影浮起来）。 */
    const val PANEL_LIGHT_SHADOW = 0x40000000
    const val PANEL_LIGHT_SHADOW_BLUR = 24
    const val PANEL_LIGHT_SHADOW_DY = 8
    /** 深底不可见的内圈「玻璃厚度」暗线 → 暖白底改白 6% 微高光。 */
    const val PANEL_LIGHT_INNER = 0x0FFFFFFF

    /**
     * 面板文字（586 起**取消三色分级**，只留两级）：
     * - [TEXT_DARK]：正文一律近黑（选项行不再用强调色）；
     * - [TEXT_DARK_72]：说明/占位黑 72%。
     *
     * [TEXT_DARK_54] / [TEXT_DARK_38] 保留为别名（历史调用点仍在用），
     * 值与 72% 同级，避免同一面板出现三种灰度。
     */
    const val TEXT_DARK = 0xFF1B1B1F.toInt()
    const val TEXT_DARK_72 = 0xB8000000.toInt()
    const val TEXT_DARK_54 = TEXT_DARK_72
    const val TEXT_DARK_38 = TEXT_DARK_72
    /** 暖白底分隔线（黑 12%；纯白底下 8% 几乎看不见）。 */
    const val DIVIDER_LIGHT = 0x1F000000
    /** 暖白底选中行底（accent@12%）与滑杆未填充段（黑 12%）。 */
    const val SEL_BG_LIGHT = 0x1F6366F1
    const val TRACK_LIGHT_INACTIVE = 0x1F000000
    /** 暖白面板遮罩：黑 30%（暖白面板不需要纯白时那么重的遮罩）。 */
    const val SCRIM_LIGHT = 0x4D000000

    /**
     * 面板标题字重（w600）：`sans-serif-medium` 是 Android 唯一可靠的
     * 「中等偏粗」族（`Typeface.BOLD` = 700 过粗，`DEFAULT` = 400 过细）。
     */
    val mediumTypeface: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)

    /** 面板正文字重（w500）：同样落在 medium 族，观感与 Flutter w500 一致。 */
    val bodyTypeface: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)

    // ── 播放器弹层统一排版（586，三端逐值对齐）──
    //
    // 标题 15/w600、正文 14/w500、说明 12/w500。Flutter 侧同名常量在
    // `GlassConfig.playerPanel*Size`，鸿蒙在 `NativePlayerPanel.ets`。
    /** 标题 15 / w600。 */
    const val PANEL_TITLE_WEIGHT = 600
    /** 正文 14 / w500。 */
    const val PANEL_BODY_SIZE = 14f
    const val PANEL_BODY_WEIGHT = 500
    /** 说明/占位 12 / w500。 */
    const val PANEL_CAPTION_SIZE = 12f
    const val PANEL_CAPTION_WEIGHT = 500

    // ── 手势亮度/音量柱条（对齐 Flutter `_buildVerticalBar`）──
    /** 柱条宽 36dp、圆角 18、黑 54% 底（Flutter `width:36` / `radius:18`）。 */
    const val GAUGE_WIDTH = 36
    const val GAUGE_RADIUS = 18
    const val GAUGE_BG = 0x8A000000.toInt()
    /** 顶部图标 18dp、白 70%；左右内边距 0、上下 12/8（Flutter SizedBox）。 */
    const val GAUGE_ICON = 18
    const val GAUGE_TOP_PAD = 12
    const val GAUGE_ICON_GAP = 8
    /** 竖向轨道 4dp（Flutter `trackHeight: 4`），thumb 6、光晕 10。 */
    const val GAUGE_TRACK = 4
    const val GAUGE_THUMB = 6
    const val GAUGE_OVERLAY = 10
    /** 底部百分比 11sp 白 70%、下边距 8。 */
    const val GAUGE_PERCENT_SIZE = 11f
    const val GAUGE_BOTTOM_PAD = 8
    /** 亮度轨道色 `#FFD54F`、音量轨道色 `#6366F1`（Flutter 逐值同色）。 */
    const val GAUGE_BRIGHTNESS = 0xFFFFD54F.toInt()
    const val GAUGE_VOLUME = 0xFF6366F1.toInt()
    /** 柱条贴边距离 20dp（Flutter `Positioned(left/right: 20)`）。 */
    const val GAUGE_EDGE = 20

    // ── 动效 ──
    const val CONTROLS_FADE_MS = 200
    const val AUTO_HIDE_MS = 5000

    // ── 顶栏标题保底宽 ──
    /**
     * 顶栏标题最小宽度（dp）。
     *
     * Flutter 用 `Expanded`（权重 1，可被压到 0 宽 → 极窄屏标题彻底消失）。
     * 原生改用**保底宽**：标题至少留出这么多宽度并 ellipsize，观感与
     * Flutter 一致（同样是「剩余空间」），但不会被尾簇挤成 0。
     */
    const val TITLE_MIN_WIDTH = 56

    // ── 底栏渐变 ──
    /**
     * 底栏渐变实端 alpha（Flutter `_buildControls` = `black.withValues(alpha: 0.85)`）。
     * 顶栏实端保持 `BAR_GRADIENT_SOLID`（0xCC = 0.8）。
     */
    const val BAR_BOTTOM_SOLID = 0xD9000000.toInt()
}

/**
 * 角标圆形底（照 Flutter `BoxShape.circle`：正圆，直径 = 最短边）。
 *
 * 旧实现用 `GradientDrawable.OVAL` + 手算宽度 `14 + len*5`，"3" 变成
 * 19×14 的**椭圆**、"47" 更扁（真机截图回归）。这里画正圆，直径取
 * 视图最短边，与 Flutter 一致。
 */
internal class BadgeCircleDrawable(private val color: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.isEmpty) return
        val cx = b.exactCenterX()
        val cy = b.exactCenterY()
        val radius = minOf(b.width(), b.height()) / 2f
        canvas.drawCircle(cx, cy, radius, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
