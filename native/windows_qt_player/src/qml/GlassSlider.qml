import QtQuick
import HimiPlayer

// 660：玻璃质感滑杆（照 Flutter `GlassSliderTrackShape` + `GlassSliderThumbShape`）。
//
// 【为什么不用 Qt Slider】Qt Quick Controls 的 Slider 主题是系统风格，与
// Flutter 的玻璃质感差距很大（三段渐变 + 光晕 + 高光线），观感不一致。
//
// 【绘制层（与 Flutter 逐层对应）】
//   轨道：
//     1. 已播放段外发光（accent@30%，blur 6）
//     2. 未播放段底（上亮 → 中 → 下暗 三段渐变）
//     3. 已播放段（accent 上亮 → accent → accent 下深）
//     4. 顶部 1px 高光线（白@55%，高度 = trackH×0.18）
//   拇指：
//     1. accent 光晕（r+6，blur 8）
//     2. 圆体三段渐变
//     3. 顶部高光弧
//
// 【Qt 与 Flutter 的差距】Qt 的 shadowBlur 是盒式模糊，Flutter 是高斯模糊，
// 光晕观感略有差异；但比裸 Slider 接近得多。
Item {
    id: root

    property real value: 0.0          // 0.0 ~ 1.0
    property bool dragging: false
    property color accent: Theme.accent
    property real trackHeight: Theme.fpSliderTrackHeight
    property real thumbRadius: Theme.fpSliderThumbRadius

    signal seekStarted()
    signal seekFinished(real ratio)

    implicitHeight: 24
    implicitWidth: 96

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        opacity: 1.0

        property real t: root.dragging ? 1.0 : 0.0

        onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            var th = root.trackHeight
            var cy = h / 2
            var left = thumbR + 2
            var right = w - thumbR - 2
            var trackW = right - left
            var thumbR = root.thumbRadius

            // 已播放段右端 x
            var fillRight = left + trackW * Math.max(0, Math.min(1, root.value))

            ctx.clearRect(0, 0, w, h)

            // ── 1. 已播放段外发光（accent@30%，模拟 blur）──
            if (fillRight - left > 1) {
                ctx.save()
                ctx.shadowColor = Qt.rgba(
                    accent.r, accent.g, accent.b, 0.30)
                ctx.shadowBlur = 6
                ctx.fillStyle = Qt.rgba(
                    accent.r, accent.g, accent.b, 0.30)
                roundRect(ctx, left - 1.5, cy - th / 2 - 1.5,
                          fillRight - left + 3, th + 3, (th + 3) / 2)
                ctx.fill()
                ctx.restore()
            }

            // ── 2. 未播放段底（三段渐变）──
            var grad2 = ctx.createLinearGradient(0, cy - th / 2, 0, cy + th / 2)
            grad2.addColorStop(0, Qt.rgba(
                accent.r * 0.22 + 1.0 * 0.78,
                accent.g * 0.22 + 1.0 * 0.78,
                accent.b * 0.22 + 1.0 * 0.78, 0.35))
            grad2.addColorStop(0.5, Qt.rgba(1, 1, 1, 0.16))
            grad2.addColorStop(1, Qt.rgba(0, 0, 0, 0.28))
            ctx.fillStyle = grad2
            roundRect(ctx, left, cy - th / 2, trackW, th, th / 2)
            ctx.fill()

            // ── 3. 已播放段（accent 三段渐变）──
            if (fillRight - left > 1) {
                var grad3 = ctx.createLinearGradient(0, cy - th / 2, 0, cy + th / 2)
                grad3.addColorStop(0, Qt.rgba(
                    accent.r * 0.70 + 0.30,
                    accent.g * 0.70 + 0.30,
                    accent.b * 0.70 + 0.30, 1))
                grad3.addColorStop(0.5, Qt.rgba(accent.r, accent.g, accent.b, 1))
                grad3.addColorStop(1, Qt.rgba(
                    accent.r * 0.88, accent.g * 0.88, accent.b * 0.88, 1))
                ctx.fillStyle = grad3
                roundRect(ctx, left, cy - th / 2, fillRight - left, th, th / 2)
                ctx.fill()
            }

            // ── 4. 顶部高光线 ──
            ctx.save()
            ctx.beginPath()
            roundRect(ctx, left, cy - th / 2, trackW, th, th / 2)
            ctx.clip()
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.55)
            ctx.fillRect(left, cy - th / 2, trackW,
                         Math.max(1, th * 0.18))
            ctx.restore()

            // ── 拇指 ──
            var cx = left + trackW * Math.max(0, Math.min(1, root.value))
            var r = root.thumbRadius * (1 + 0.10 * (root.dragging ? 1.0 : 0.0))

            // 1. 光晕
            ctx.save()
            ctx.shadowColor = Qt.rgba(accent.r, accent.g, accent.b, 0.50)
            ctx.shadowBlur = 8
            ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.50)
            ctx.beginPath()
            ctx.arc(cx, cy, r + 6, 0, Math.PI * 2)
            ctx.fill()
            ctx.restore()

            // 2. 圆体三段渐变
            var thumbGrad = ctx.createLinearGradient(0, cy - r, 0, cy + r)
            thumbGrad.addColorStop(0, Qt.rgba(
                accent.r * 0.62 + 0.38,
                accent.g * 0.62 + 0.38,
                accent.b * 0.62 + 0.38, 1))
            thumbGrad.addColorStop(0.5, Qt.rgba(accent.r, accent.g, accent.b, 1))
            thumbGrad.addColorStop(1, Qt.rgba(
                accent.r * 0.84, accent.g * 0.84, accent.b * 0.84, 1))
            ctx.fillStyle = thumbGrad
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fill()

            // 3. 顶部高光弧
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.75)
            ctx.lineWidth = 1.6
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(cx, cy, r - 1.6, Math.PI * 1.08, Math.PI * 1.92)
            ctx.stroke()
        }

        function roundRect(c, x, y, w, h, r) {
            c.beginPath()
            c.moveTo(x + r, y)
            c.lineTo(x + w - r, y)
            c.arcTo(x + w, y, x + w, y + r, r)
            c.lineTo(x + w, y + h - r)
            c.arcTo(x + w, y + h, x + w - r, y + h, r)
            c.lineTo(x + r, y + h)
            c.arcTo(x, y + h, x, y + h - r, r)
            c.lineTo(x, y + r)
            c.arcTo(x, y, x + r, y, r)
            c.closePath()
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function ratioAt(px) {
            var thumbR = root.thumbRadius
            var left = thumbR + 2
            var right = width - thumbR - 2
            return Math.max(0, Math.min(1, (px - left) / (right - left)))
        }

        onPressed: {
            root.dragging = true
            root.seekStarted()
            root.value = ratioAt(mouse.x)
            canvas.requestPaint()
        }
        onPositionChanged: {
            if (!root.dragging) return
            root.value = ratioAt(mouse.x)
            canvas.requestPaint()
        }
        onReleased: {
            if (!root.dragging) return
            root.dragging = false
            canvas.requestPaint()
            root.seekFinished(root.value)
        }
        onContainsMouseChanged: canvas.requestPaint()
    }

    onValueChanged: canvas.requestPaint()
}
