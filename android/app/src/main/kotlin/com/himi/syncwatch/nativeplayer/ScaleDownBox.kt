package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Rect
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 测量级「只缩不放」容器（等价 Flutter `FittedBox(fit: BoxFit.scaleDown)`）。
 *
 * 【为什么不能直接 `view.scaleX/Y`】
 * `scaleX/Y` 只改**绘制**、不改**测量宽**：父级（LinearLayout / FrameLayout）
 * 仍按自然宽排布兄弟控件 → 竖屏时右侧簇把传输组挤出屏外（真机截图回归）。
 * Flutter 的 `FittedBox(scaleDown)` 会把**缩小后的尺寸**作为自己的测量尺寸，
 * 本类做同一件事：
 *
 * - 测量：`scale = min(1, 可用宽 / 自然宽)`，`measuredWidth = 自然宽 × scale`；
 * - 布局：子项按自然尺寸铺开，再以 `scaleX/Y + pivot(右缘, 垂直中)` 收缩，
 *   缩小后的内容**右缘对齐**容器右缘（Flutter `alignment: Alignment.centerRight`）；
 * - 容器本身**撑满父级给的槽位**（`Expanded` 语义），缩放后左侧空出的区域
 *   仍属于本容器 → 用来扩展触摸热区。
 *
 * 【热区补偿】
 * 缩放会同比缩小子项热区（0.54× 时 24dp 图标只剩 ~13dp）。框架会按变换
 * 矩阵正确反算触摸坐标（命中不错位），但热区物理变小。本类在缩放态下给
 * 每个可点击后代补到 ≥ [HIT_SLOP]dp（左右由空槽补、上下由容器高补），
 * 只扩大热区、不改变任何视觉。
 *
 * 转发链路：本容器坐标 → 逆变换回子项自然坐标 → `child.dispatchTouchEvent`
 * （用 dispatch 而非 handle，保留 `applyPressFeedback` 的 OnTouchListener
 * 按下反馈）。
 */
internal class ScaleDownBox(
    context: Context,
    /**
     * 可用宽需再扣除的预留量（顶栏给标题保底宽用）。
     * 底栏传 0：可用宽由外层 `Expanded` 直接给到 `(行宽-传输组)/2`。
     */
    private val reservedPx: Int = 0,
) : FrameLayout(context) {

    /** 当前生效的缩放比（1 = 未缩放）。诊断与测试用。 */
    var scale: Float = 1f
        private set

    private val slopPx = (HIT_SLOP * resources.displayMetrics.density).roundToInt()
    private val hitSlopRect = Rect()
    private var hitTarget: View? = null

    init {
        // 缩放后的内容右缘对齐、左缘可能伸出子项原始布局框，不能被裁。
        clipChildren = false
        clipToPadding = false
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val child = getChildAt(0)
        if (child == null || child.visibility == GONE) {
            setMeasuredDimension(0, 0)
            return
        }
        // 先测自然尺寸（不带宽度约束）。
        child.measure(
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
        )
        val naturalW = child.measuredWidth
        val naturalH = child.measuredHeight
        if (naturalW <= 0 || naturalH <= 0) {
            setMeasuredDimension(naturalW.coerceAtLeast(0), naturalH.coerceAtLeast(0))
            return
        }
        val wMode = MeasureSpec.getMode(widthMeasureSpec)
        val wSize = MeasureSpec.getSize(widthMeasureSpec)
        scale = if (wMode == MeasureSpec.UNSPECIFIED) {
            1f
        } else {
            val avail = (wSize - reservedPx).coerceAtLeast(0)
            if (avail <= 0) 1f else min(1f, avail.toFloat() / naturalW)
        }
        val scaledW = (naturalW * scale).roundToInt()
        val scaledH = (naturalH * scale).roundToInt()
        // EXACTLY 时必须给足父级要求的宽度，否则 Expanded 槽位会塌。
        val finalW = if (wMode == MeasureSpec.EXACTLY) wSize else scaledW
        val finalH = when (MeasureSpec.getMode(heightMeasureSpec)) {
            MeasureSpec.EXACTLY -> MeasureSpec.getSize(heightMeasureSpec)
            else -> scaledH
        }
        setMeasuredDimension(finalW, finalH)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val child = getChildAt(0) ?: return
        if (child.visibility == GONE) return
        val naturalW = child.measuredWidth
        val naturalH = child.measuredHeight
        if (naturalW <= 0 || naturalH <= 0) return
        // 右缘对齐 + 垂直居中；pivot 取 (自然宽, 自然高/2) 让缩放朝右缘收。
        val left = measuredWidth - naturalW
        val top = (measuredHeight - naturalH) / 2
        child.pivotX = naturalW.toFloat()
        child.pivotY = naturalH / 2f
        child.scaleX = scale
        child.scaleY = scale
        child.layout(left, top, left + naturalW, top + naturalH)
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (scale >= 0.999f) return super.dispatchTouchEvent(ev)
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            hitTarget = findHitChild(ev.x, ev.y)
            if (hitTarget != null) buildHitRect(hitTarget!!)
        }
        val target = hitTarget ?: return super.dispatchTouchEvent(ev)
        if (ev.actionMasked == MotionEvent.ACTION_DOWN &&
            !hitSlopRect.contains(ev.x.toInt(), ev.y.toInt())
        ) {
            hitTarget = null
            return super.dispatchTouchEvent(ev)
        }
        val child = getChildAt(0) ?: return false
        // 绘制映射：c = child.left + pivot + (p - pivot) * scale
        // 逆变换：  p = pivot + (c - child.left - pivot) / scale
        val inv = 1f / scale
        val px = child.pivotX + (ev.x - child.left - child.pivotX) * inv
        val py = child.pivotY + (ev.y - child.top - child.pivotY) * inv
        val mapped = MotionEvent.obtain(ev)
        mapped.setLocation(px, py)
        val handled = target.dispatchTouchEvent(mapped)
        mapped.recycle()
        if (ev.actionMasked == MotionEvent.ACTION_UP ||
            ev.actionMasked == MotionEvent.ACTION_CANCEL
        ) {
            hitTarget = null
        }
        return handled
    }

    /**
     * 缩放态下命中的可点击后代。
     *
     * [x]/[y] 为本容器坐标；逐层逆变换到各子项局部坐标后做命中判定。
     */
    private fun findHitChild(x: Float, y: Float): View? {
        val child = getChildAt(0) ?: return null
        val inv = 1f / scale
        val px = child.pivotX + (x - child.left - child.pivotX) * inv
        val py = child.pivotY + (y - child.top - child.pivotY) * inv
        return findClickableAt(child, px, py)
    }

    /**
     * 在 [view] 的子树里找包含点 `(x, y)` 的可点击后代；坐标为 [view] 的
     * **局部坐标**（每次递归减去子项 left/top）。
     */
    private fun findClickableAt(view: View, x: Float, y: Float): View? {
        if (view.visibility != VISIBLE) return null
        if (view is ViewGroup) {
            for (i in view.childCount - 1 downTo 0) {
                val c = view.getChildAt(i)
                val found = findClickableAt(c, x - c.left, y - c.top)
                if (found != null) return found
            }
        }
        // 叶子或子树未命中：自身可点击且点落在其矩形内。
        if (view !== getChildAt(0) &&
            view.isClickable &&
            x >= 0 && y >= 0 && x < view.width && y < view.height
        ) {
            return view
        }
        return null
    }

    /** 以目标可点击后代的**绘制矩形**为基准向外扩到 ≥44dp（容器坐标）。 */
    private fun buildHitRect(target: View) {
        val loc = IntArray(2)
        target.getLocationInWindow(loc)
        val self = IntArray(2)
        getLocationInWindow(self)
        val w = (target.width * scale).roundToInt()
        val h = (target.height * scale).roundToInt()
        val cx = loc[0] - self[0] + w / 2
        val cy = loc[1] - self[1] + h / 2
        hitSlopRect.set(
            cx - max(w, slopPx) / 2,
            cy - max(h, slopPx) / 2,
            cx + max(w, slopPx) / 2,
            cy + max(h, slopPx) / 2,
        )
        // 不超出容器自身，避免吃到相邻槽位。
        hitSlopRect.intersect(0, 0, measuredWidth, measuredHeight)
    }

    /** 重排前复位（手机 ↔ TV 切换等）。 */
    fun reset() {
        scale = 1f
        hitTarget = null
    }

    companion object {
        /** 缩放态下补足的最小触摸热区（dp）。Android 官方推荐值。 */
        const val HIT_SLOP = 44
    }
}
