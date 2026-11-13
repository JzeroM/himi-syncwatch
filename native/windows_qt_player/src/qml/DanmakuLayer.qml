import QtQuick
import QtQuick.Controls.Basic

/// 697：QML 自绘弹幕层（替代原 ASS 旁路方案）。
///
/// ## 为什么不用 ASS（原方案）
///
/// 原实现把弹幕生成 ASS 文件、作为**次字幕轨**交给 mpv 渲染。三个硬伤：
///
/// 1. **开关弹幕会卡视频**：`sub-remove` + `sub-add` + 切 `secondary-sid`
///    会让 mpv 重建字幕/OSD 渲染管线，视频帧短暂停住（真机反馈）。
/// 2. **HDR 下弹幕过曝**：HDR 模式整条管线是 BT.2020 + PQ
///    （`mpv_window.cpp` 的 `applyHdrOptions`），ASS 的 `#FFFFFF` 被当作
///    PQ 编码的 HDR 白（≈10000 nit），弹幕刺眼、边缘色带。玻璃控件走
///    Windows DWM 的 SDR 合成所以正常，只有弹幕受影响。
/// 3. **与字幕设置耦合**：`sub-scale`/`sub-pos`/`sub-delay` 是全局属性，
///    用户调主字幕会连带改变弹幕。
///
/// 自绘层是**独立透明浮层**，与 mpv 管线完全解耦，上述三项全部消失。
///
/// ## 算法来源
///
/// **逐条对齐安卓 `DanmakuLayerView.kt`**（用户明确要求「全部对齐安卓鸿蒙」）：
///
/// | 机制 | 安卓 | 本实现 |
/// |---|---|---|
/// | 飞行缓存 | `flying` + `syncFlying` | `flying` + `syncFlying()` |
/// | 行号绑定 | `laneOf`（**一旦分配不再变**） | `laneOf` 同构 |
/// | 冲突表重建 | 每帧从在场条目重算占用 | 同 |
/// | 轨道满 | `lane = -1` 丢弃 | 同 |
/// | 生命周期余量 | `lifeSlackMs = 500` | 同 |
/// | 超前丢弃 | `keepAheadMs = 35000` | 同 |
/// | 基准字号 | 25dp | 25 |
/// | 行距 | 6dp | 6 |
/// | 边距 | 8dp | 8 |
/// | 穿屏 | 8000ms ÷ speed | 同 |
/// | 驻留 | 4000ms | 同 |
/// | 同轨间隙 | 150ms | 同 |
/// | 淡入淡出 | 首尾各 10% | 同 |
///
/// 【为什么需要飞行缓存】Dart 侧只下发 `[pos-keepSec, pos+30s]` 的时间窗。
/// 若只渲染窗口内条目，滚动弹幕滑出窗口就被拦腰截断（安卓真机回归过）。
/// 缓存保证已入屏的弹幕一定画到生命周期结束。
///
/// 【为什么行号一旦分配不再变】若每帧全量重排，最老条目离场后后续条目
/// 会拿到更小的行号 → 整屏跳行。安卓旧实现踩过这个坑。
///
/// ## 性能设计
///
/// - **弹幕池复用**：固定 `Repeater` 数量的 `Text` 节点，只改 `visible`/
///   `x`/`y`/`text`，**不重建节点**（重建是 QML 最贵的操作）。
/// - 每帧只改 `x`/`y`（位置属性，不触发布局重算）。
/// - 30fps 帧驱动（与鸿蒙 `DanmakuLayer` 一致）。
Item {
    id: root

    /// 弹幕数据（`playerState.danmakuItems`）。
    property var danmakuItems: []
    /// 播放位置（毫秒）。
    property real positionMs: 0
    /// 是否正在播放（暂停时冻结）。
    property bool playing: false
    /// 弹幕总开关。
    ///
    /// 【为什么不叫 `enabled`】`Item.enabled` 是 FINAL 属性（控制鼠标事件
    /// 接收），重定义会报 `Cannot override FINAL property`。
    property bool danmakuEnabled: true
    /// 字号倍率（`danmakuFontSize`，Flutter 默认 0.5）。
    property real fontSizeScale: 0.5
    /// 滚动速度倍率（`danmakuSpeed`，Flutter 默认 0.7）。
    property real speed: 0.7
    /// 弹幕不透明度（0.1~1.0）。
    ///
    /// 【为什么不直接用 `Item.opacity`】父级 `opacity` 会与子项 `opacity`
    /// 相乘。若外部设父级、子项再乘一次，弹幕会过淡。这里用独立属性，
    /// 由子项统一应用（`Item.opacity` 保持默认 1.0）。
    property real danmakuOpacity: 1.0
    /// 滚动行数上限（用户设置）。
    property int scrollRows: 30
    /// 顶部行数。
    property int topRows: 4
    /// 底部行数。
    property int bottomRows: 4

    // ── 常量（逐条对齐安卓 DanmakuLayerView）──
    readonly property real baseFontSize: 25   // baseFontSizeDp
    readonly property real rowGap: 6          // rowGapDp
    readonly property real edgePadding: 8     // edgePadDp
    readonly property real scrollBaseMs: 8000 // scrollBaseMs
    readonly property real fixedMs: 4000      // fixedMs
    readonly property real trackGapMs: 150    // trackGapMs
    readonly property real lifeSlackMs: 500   // lifeSlackMs
    readonly property real keepAheadMs: 35000 // keepAheadMs
    readonly property int frameIntervalMs: 33 // 30fps
    /// 弹幕池上限（同屏最多渲染多少条）。
    readonly property int poolSize: 150

    readonly property real fontSize: baseFontSize * fontSizeScale
    readonly property real lineHeight: fontSize + rowGap

    /// 自动行数（按屏高，扣上下边距）。
    readonly property int autoRows: {
        if (height <= 0 || lineHeight <= 0) return 1
        var n = Math.floor((height - edgePadding * 2) / lineHeight)
        return n < 1 ? 1 : n
    }
    readonly property int effectiveScrollRows:
        Math.max(1, Math.min(scrollRows, autoRows))
    readonly property int effectiveTopRows:
        Math.max(1, Math.min(topRows, autoRows))
    readonly property int effectiveBottomRows:
        Math.max(1, Math.min(bottomRows, autoRows))

    // ── 内部状态（对应安卓 flying / laneOf）──
    //
    // 【为什么用普通对象而非 QML property】`flying`/`laneOf` 是每帧变化的
    // 中间状态，渲染只依赖 `frameItems`。若声明成 property，每次 tick 赋值
    // 都会触发 QML 属性通知 → 30fps 下产生大量无效绑定重算。放在普通对象
    // 里（`_state.xxx` 内部修改不触发通知）可完全避开。
    readonly property var _state: ({
        flying: [],     // 飞行缓存：已入屏的弹幕（跨帧保留到生命周期结束）
        laneOf: ({}),   // 行号绑定：timeMs:text → lane（-1 = 满槽丢弃）
        laneSig: ""     // 当前轨道容量签名
    })
    /// 当前帧要渲染的弹幕（含 lane 与 progress）。
    property var frameItems: []

    /// 轨道容量签名（行数/字号变化 → 必须整表重排）。
    readonly property string laneSig: effectiveScrollRows + "|"
        + effectiveTopRows + "|" + effectiveBottomRows + "|" + fontSize

    onLaneSigChanged: {
        // 行容量变化（转屏/改行数/改字号）→ 清空行号绑定，强制重排
        _state.laneOf = ({})
        _state.flying = []
        tick()
    }
    onDanmakuItemsChanged: tick()
    Component.onCompleted: tick()

    /// 估算文本宽度（逐字复刻 Flutter `DanmakuTimeline.estimateTextWidth`）。
    ///
    /// CJK / 全角按 1.0×字号，其余 0.55×。旧 ASS 方案没有这个估算，
    /// 用 `dur * 0.55` 粗略代替 → 长弹幕会被后一条追上。
    function estimateWidth(text, fs) {
        if (!text) return 0
        var units = 0
        for (var i = 0; i < text.length; i++) {
            var c = text.charCodeAt(i)
            var wide = c >= 0x1100 && (
                c <= 0x115F
                || c === 0x2329 || c === 0x232A
                || (c >= 0x2E80 && c <= 0xA4CF && c !== 0x303F)
                || (c >= 0xAC00 && c <= 0xD7A3)
                || (c >= 0xF900 && c <= 0xFAFF)
                || (c >= 0xFE30 && c <= 0xFE4F)
                || (c >= 0xFF00 && c <= 0xFF60)
                || (c >= 0xFFE0 && c <= 0xFFE6))
            units += wide ? 1.0 : 0.55
        }
        return units * fs
    }

    function keyOf(it) { return it.timeMs + ":" + it.text }

    /// 轨道占用时长（ms）：滚动 = 穿屏到「完全入屏」+ 间隙；顶/底 = 驻留 + 间隙。
    ///
    /// 对应安卓 `occupancyMs`，与 Flutter `_occupancySeconds` 同构。
    function occupancyMs(it, travelMs) {
        if (it.mode === "top" || it.mode === "bottom") {
            return fixedMs + trackGapMs
        }
        var textW = estimateWidth(it.text, fontSize)
        var fullyEntered = textW <= 0 ? 0 : textW / (width + textW)
        return travelMs * fullyEntered + trackGapMs
    }

    /// 飞行缓存维护（对应安卓 `syncFlying`）。
    ///
    /// 窗口新条目并入（`timeMs:text` 去重），生命周期结束才移除并释放行号。
    function syncFlying(pos, travelMs) {
        var list = _state.flying
        var changed = false
        for (var i = 0; i < danmakuItems.length; i++) {
            var it = danmakuItems[i]
            var k = keyOf(it)
            var seen = false
            for (var j = 0; j < list.length; j++) {
                if (keyOf(list[j]) === k) { seen = true; break }
            }
            if (!seen) {
                list = list.concat([it])
                changed = true
            }
        }
        var alive = []
        var lanes = _state.laneOf
        var lanesChanged = false
        for (var m = 0; m < list.length; m++) {
            var f = list[m]
            var elapsed = pos - f.timeMs
            var life = (f.mode === "top" || f.mode === "bottom")
                ? fixedMs : travelMs
            // 生命周期结束 + 余量 → 移除；超前过多（换集/大跨度 seek）→ 丢弃
            if (elapsed > life + lifeSlackMs || elapsed < -keepAheadMs) {
                if (lanes[keyOf(f)] !== undefined) {
                    delete lanes[keyOf(f)]
                    lanesChanged = true
                }
                continue
            }
            alive.push(f)
        }
        _state.flying = alive
        if (lanesChanged) _state.laneOf = lanes
        return changed || lanesChanged
    }

    /// 增量行分配（对应安卓 `assignLanes`）。
    ///
    /// ① 重建冲突表：只统计「已分配且仍在飞」的条目占用。
    /// ② 只给新条目分配（按 timeMs 升序）；轨道满 → lane=-1 丢弃。
    function assignLanes(all, travelMs) {
        var scrollAvail = []
        var topAvail = []
        var botAvail = []
        for (var i = 0; i < effectiveScrollRows; i++) scrollAvail.push(0)
        for (var i = 0; i < effectiveTopRows; i++) topAvail.push(0)
        for (var i = 0; i < effectiveBottomRows; i++) botAvail.push(0)

        var lanes = _state.laneOf

        // ① 重建冲突表（从当前在场条目，已离场的占用不再残留）
        for (var j = 0; j < all.length; j++) {
            var it = all[j]
            var lane = lanes[keyOf(it)]
            if (lane === undefined || lane < 0) continue
            var avail = it.mode === "top" ? topAvail
                : (it.mode === "bottom" ? botAvail : scrollAvail)
            if (lane >= avail.length) continue
            var occupiedUntil = it.timeMs + occupancyMs(it, travelMs)
            if (occupiedUntil > avail[lane]) avail[lane] = occupiedUntil
        }

        // ② 只给新条目分配
        for (var k = 0; k < all.length; k++) {
            var item = all[k]
            var key = keyOf(item)
            if (lanes[key] !== undefined) continue  // 已分配（含 -1）：不重分配
            var arr = item.mode === "top" ? topAvail
                : (item.mode === "bottom" ? botAvail : scrollAvail)
            var occ = occupancyMs(item, travelMs)
            var picked = -1
            for (var r = 0; r < arr.length; r++) {
                if (arr[r] <= item.timeMs) {
                    arr[r] = item.timeMs + occ
                    picked = r
                    break
                }
            }
            lanes[key] = picked  // -1 → 轨道满丢弃
        }
        _state.laneOf = lanes
    }

    /// 固定弹幕淡入淡出（首尾各 10% 生命周期，对应安卓 `fixedFade`）。
    function fixedFade(progress) {
        if (progress < 0.1) return progress / 0.1
        if (progress > 0.9) return (1.0 - progress) / 0.1
        return 1.0
    }

    /// 单帧更新：同步飞行缓存 → 分配行号 → 计算渲染项。
    function tick() {
        if (!danmakuEnabled || danmakuOpacity <= 0) {
            if (frameItems.length > 0) frameItems = []
            return
        }
        var pos = positionMs
        var spd = Math.max(0.25, Math.min(4.0, speed))
        var travelMs = scrollBaseMs / spd

        syncFlying(pos, travelMs)

        // 按时间升序（冲突表必须按时间序推进，否则误丢/跳行）
        var all = _state.flying.slice().sort(function (a, b) {
            return a.timeMs - b.timeMs
        })
        assignLanes(all, travelMs)

        var lanes = _state.laneOf
        var out = []
        for (var i = 0; i < all.length; i++) {
            var it = all[i]
            var lane = lanes[keyOf(it)]
            if (lane === undefined || lane < 0) continue
            var elapsed = pos - it.timeMs
            var isFixed = it.mode === "top" || it.mode === "bottom"
            var life = isFixed ? fixedMs : travelMs
            if (elapsed < 0 || elapsed > life) continue
            var textW = estimateWidth(it.text, fontSize)
            out.push({
                text: it.text || "",
                mode: it.mode,
                color: it.color || "#FFFFFF",
                lane: lane,
                textW: textW,
                progress: elapsed / life
            })
            if (out.length >= poolSize) break
        }
        frameItems = out
    }

    /// 帧驱动：只在播放中推进（暂停冻结，对应安卓 `paused` 逻辑）。
    Timer {
        interval: root.frameIntervalMs
        running: root.danmakuEnabled && root.playing && root.visible
        repeat: true
        onTriggered: root.tick()
    }

    // ── 渲染：固定池 + 只改属性（不重建节点）──
    Repeater {
        model: root.poolSize
        delegate: Text {
            required property int index
            readonly property var item:
                index < root.frameItems.length ? root.frameItems[index] : null
            readonly property bool isFixed:
                item !== null && (item.mode === "top" || item.mode === "bottom")

            visible: item !== null
            text: item !== null ? item.text : ""
            font.pixelSize: root.fontSize
            font.weight: Font.Medium
            font.family: "Microsoft YaHei"
            color: item !== null ? item.color : "transparent"

            // 滚动：progress=0 前沿贴右缘外，progress=1 完全离开左缘
            // 顶/底：水平居中
            x: {
                if (item === null) return 0
                if (item.mode === "scroll") {
                    return root.width - item.progress * (root.width + item.textW)
                }
                return (root.width - item.textW) / 2
            }
            // 顶：edgePad + lane*rowH；底：H - edgePad - (lane+1)*rowH
            y: {
                if (item === null) return 0
                if (item.mode === "top") {
                    return root.edgePadding + item.lane * root.lineHeight
                }
                if (item.mode === "bottom") {
                    return root.height - root.edgePadding
                        - (item.lane + 1) * root.lineHeight
                }
                return root.edgePadding + item.lane * root.lineHeight
            }

            style: Text.Outline
            styleColor: "#8A000000"

            // 顶/底淡入淡出；滚动不做淡变（进出屏幕边缘本就自然）
            opacity: root.danmakuOpacity * (isFixed
                ? root.fixedFade(item ? item.progress : 1.0) : 1.0)
        }
    }
}
