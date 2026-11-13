import QtQuick
import QtQuick.Controls.Basic
import HimiPlayer

/// 697：播放调试面板（Windows Qt 播放窗）。
///
/// ## 为什么必须在 Qt 侧重写
///
/// Windows 走独立 Qt 进程（`wid` 直出 + HDR 直出），Flutter 播放页已退场，
/// 旧的 Flutter `SyncDebugPanel` 在这里**根本看不到**。而 Windows 恰好是
/// 唯一能跑完整 libplacebo 杜比视界处理的平台（D3D11 compute）——
/// 排查 DV 必须在这里有面板。
///
/// ## 数据来源
///
/// 全部来自 `playerState`（Dart 侧 1s 轮询 mpv 属性后经 IPC 下发）。
/// 与 Flutter 面板**同源**，不会出现「两个面板说不同的数」。
///
/// ## HDR/DV 排查三元组
///
/// | 层 | 字段 | 回答 |
/// |---|---|---|
/// | 输入 | videoParamsPrimaries/Gamma/SigPeak/DoviProfile | 片源是什么？ |
/// | 决策 | dvContent | 识别成什么了？ |
/// | 输出 | targetPrim/targetTrc/toneMapping | 怎么渲染的？ |
Rectangle {
    id: root

    /// 设置项开关（Dart 侧下发 `showDebug`）。
    property bool shown: false

    /// 本次开关周期内是否被用户手动关闭过。
    ///
    /// 【为什么需要】关闭按钮不能直接写 `shown = false`——那会打断
    /// `shown: playerState.showDebug` 的绑定，之后在设置里重新打开也
    /// 不会生效。改为本地置 `dismissed`，等 `shown` 再次变 true 时复位。
    property bool dismissed: false

    /// 面板位置（拖动后本地持有）。
    property real panelX: 16
    property real panelY: 80

    /// 各分组折叠状态（key → true 表示已折叠）。
    property var collapsedMap: ({})

    signal closed()

    // 锁定态隐藏（与安卓/鸿蒙一致：锁定后只留锁钮）。
    visible: shown && !dismissed && !playerState.locked
    x: panelX
    y: panelY
    width: 300
    height: Math.min(contentColumn.implicitHeight + headerBar.height + 14,
                     parent ? parent.height * 0.78 : 480)
    color: Qt.rgba(0, 0, 0, 0.72)
    radius: 10
    border.width: 1
    border.color: Qt.rgba(0.4, 1.0, 0.6, 0.45)
    z: 100

    // 设置项重新打开时复位 dismissed（否则手动关闭过一次就再也打不开）。
    onShownChanged: {
        if (shown) dismissed = false
    }

    // ── 工具函数 ──────────────────────────────────────────────

    function isCollapsed(key) {
        return root.collapsedMap[key] === true
    }

    function toggle(key) {
        var m = root.collapsedMap
        m[key] = !root.isCollapsed(key)
        // 整体替换才触发 QML var 属性通知
        root.collapsedMap = m
    }

    /// 输出是否真的在 HDR（target-trc 为 pq/hlg）。
    function isHdrOut() {
        var t = playerState.targetTrc
        return t === "pq" || t === "hlg"
    }

    /// 是否杜比视界内容。
    /// 是否 DV 内容。
    ///
    /// 【必须用 dvContent 兜底】`doviProfile` 来自 mpv 的
    /// `current-tracks/video/dolby-vision-profile`，部分构建读不到（恒 0）。
    /// `dvContent` 来自 Emby 元数据，可靠——只看 profile 会把 P5 显示成
    /// 「非 DV 内容」（真机回归）。
    function isDv() {
        return playerState.doviProfile > 0 || playerState.dvContent
    }

    /// 当前渲染后端是否支持 DV 元数据（libplacebo compute shader）。
    ///
    /// D3D11（Windows）/ Vulkan（鸿蒙 ohosvk）支持；
    /// OpenGL ES（安卓，libplacebo Vulkan 被禁用）不支持。
    function backendSupportsDv() {
        var ctx = (playerState.gpuContext || "").toLowerCase()
        return ctx.indexOf("d3d11") >= 0 || ctx.indexOf("vulkan") >= 0
    }

    /// 毫秒 → mm:ss / hh:mm:ss。
    function fmtMs(ms) {
        if (!ms || ms <= 0) return "00:00"
        var s = Math.floor(ms / 1000)
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        function two(v) { return v < 10 ? "0" + v : "" + v }
        return h > 0 ? two(h) + ":" + two(m) + ":" + two(sec)
                     : two(m) + ":" + two(sec)
    }

    /// 一键复制的纯文本（对齐 Dart 侧 `DebugMetrics.toPlainText()`）。
    ///
    /// 【为什么直接拼 playerState 而不是遍历子项】子项遍历依赖
    /// `children` 顺序与自定义属性存在性，分组折叠/隐藏时会漏项。
    /// 直接读数据源保证「复制的内容 = 面板该显示的内容」。
    function plainText() {
        var lines = []
        function sec(t) { lines.push("## " + t) }
        function row(label, value) { lines.push(label + ": " + value) }

        sec("播放")
        row("状态", playerState.paused ? "PAUSED" : "PLAYING")
        row("位置", root.fmtMs(playerState.positionMs) + " / "
                    + root.fmtMs(playerState.durationMs))
        row("缓冲", playerState.bufferedMs + "ms")
        row("倍速", playerState.speed.toFixed(2))
        row("实际帧率", playerState.estimatedVfFps > 0
                        ? playerState.estimatedVfFps.toFixed(2) : "-")
        row("丢帧", "渲染 " + playerState.frameDropCount
                    + " / 解码 " + playerState.decoderFrameDropCount)

        sec("HDR 输入")
        row("色彩", (playerState.videoParamsPrimaries || "-") + " / "
                    + (playerState.videoParamsGamma || "-"))
        row("位深", playerState.videoParamsBitDepth + "bit · "
                    + (playerState.videoParamsPixelFormat || "-"))
        // mpv 的 sig-peak 是 max_luma/100 的倍数，必须 ×100 才是 nits
        row("峰值", playerState.videoParamsSigPeak > 0
                    ? (playerState.videoParamsSigPeak * 100).toFixed(0) + " nits"
                    : "-")
        row("编码", playerState.videoFormat || "-")
        row("硬解", playerState.hwdecCurrent || "-")

        sec("HDR 输出")
        row("路径", playerState.hdrOutput ? "Surface · HDR 直出"
                                          : "Surface · SDR（tone map）")
        row("目标", (playerState.targetPrim || "-") + " / "
                    + (playerState.targetTrc || "-"))
        row("映射", (playerState.toneMapping || "-")
                    + (playerState.toneMappingMode
                       ? " (" + playerState.toneMappingMode + ")" : ""))
        row("峰值计算", playerState.hdrComputePeak || "-")

        sec("杜比视界")
        row("Profile", playerState.doviProfile > 0
                       ? "P" + playerState.doviProfile
                         + (playerState.doviProfile === 5 ? "（单层 IPT）" : "")
                         + (playerState.doviLevel > 0
                            ? " L" + playerState.doviLevel : "")
                       : (playerState.dvContent
                          ? "DV（Profile 未知 · Emby 元数据）" : "非 DV 内容"))
        if (root.isDv()) {
            row("识别", playerState.dvContent ? "已识别为 DV"
                                              : "未识别（按普通 HDR 处理）")
            row("后端", (playerState.gpuContext || "-")
                        + (root.backendSupportsDv() ? " · 支持 DV"
                                                    : " · 不支持 DV"))
        }

        sec("渲染管线")
        row("vo", playerState.currentVo || "-")
        row("gpu-api", playerState.gpuApi || "-")
        row("gpu-context", playerState.gpuContext || "-")
        row("输出", playerState.videoOutputActual || "-")

        return lines.join("\n")
    }

    // ── 标题栏（可拖动）──────────────────────────────────────
    Rectangle {
        id: headerBar
        width: parent.width
        height: 28
        color: Qt.rgba(0.4, 1.0, 0.6, 0.12)
        radius: root.radius

        MouseArea {
            anchors.fill: parent
            // 右侧留给复制/关闭按钮
            anchors.rightMargin: 56
            cursorShape: Qt.SizeAllCursor
            property real pressX: 0
            property real pressY: 0
            onPressed: (mouse) => {
                pressX = mouse.x
                pressY = mouse.y
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                root.panelX += mouse.x - pressX
                root.panelY += mouse.y - pressY
            }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                text: "\u2630"
                color: "#66FF99"
                font.pixelSize: 12
            }
            Text {
                text: "播放调试"
                color: "#66FF99"
                font.pixelSize: 12
                font.bold: true
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                text: "\u29C9"
                color: "#8AFFFFFF"
                font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        clipboardHelper.text = root.plainText()
                        clipboardHelper.selectAll()
                        clipboardHelper.copy()
                    }
                }
            }

            Text {
                text: "\u2715"
                color: "#8AFFFFFF"
                font.pixelSize: 13
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.dismissed = true
                        root.closed()
                    }
                }
            }
        }
    }

    /// 复制用剪贴板载体。
    ///
    /// 【为什么是 1×1 透明而不是 `visible: false`】`TextEdit.copy()` 依赖
    /// 选区，不可见项在部分平台上选区会失效。1×1 透明能保证可靠。
    TextEdit {
        id: clipboardHelper
        width: 1
        height: 1
        opacity: 0
        readOnly: false
    }

    // ── 内容区 ────────────────────────────────────────────────
    Flickable {
        id: contentFlick
        anchors.top: headerBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        clip: true
        contentHeight: contentColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentColumn
            width: contentFlick.width
            spacing: 1

            // ═══ 播放 ═══
            DebugGroupHeader {
                title: "播放"
                collapsed: root.isCollapsed("playback")
                onToggleRequested: root.toggle("playback")
            }
            DebugRow {
                visible: !root.isCollapsed("playback")
                label: "状态"
                value: playerState.paused ? "PAUSED" : "PLAYING"
                severity: playerState.paused ? "warn" : "good"
            }
            DebugRow {
                visible: !root.isCollapsed("playback")
                label: "位置"
                value: root.fmtMs(playerState.positionMs) + " / "
                       + root.fmtMs(playerState.durationMs)
            }
            DebugRow {
                visible: !root.isCollapsed("playback")
                label: "缓冲"
                value: playerState.bufferedMs + "ms"
            }
            DebugRow {
                visible: !root.isCollapsed("playback")
                label: "倍速"
                value: playerState.speed.toFixed(2)
            }
            DebugRow {
                visible: !root.isCollapsed("playback")
                label: "实际帧率"
                value: playerState.estimatedVfFps > 0
                       ? playerState.estimatedVfFps.toFixed(2) : "-"
            }
            DebugRow {
                visible: !root.isCollapsed("playback")
                label: "丢帧"
                value: "渲染 " + playerState.frameDropCount
                       + " / 解码 " + playerState.decoderFrameDropCount
                severity: (playerState.frameDropCount > 100
                           || playerState.decoderFrameDropCount > 100)
                          ? "error"
                          : (playerState.frameDropCount > 10
                             || playerState.decoderFrameDropCount > 10)
                            ? "warn" : "good"
            }

            // ═══ HDR 输入 ═══
            DebugGroupHeader {
                title: "HDR 输入"
                collapsed: root.isCollapsed("input")
                highlighted: true
                onToggleRequested: root.toggle("input")
            }
            DebugRow {
                visible: !root.isCollapsed("input")
                label: "色彩"
                value: (playerState.videoParamsPrimaries || "-") + " / "
                       + (playerState.videoParamsGamma || "-")
                severity: (playerState.videoParamsGamma === "pq"
                           || playerState.videoParamsGamma === "hlg")
                          ? "good" : "normal"
            }
            DebugRow {
                visible: !root.isCollapsed("input")
                label: "位深"
                value: playerState.videoParamsBitDepth + "bit · "
                       + (playerState.videoParamsPixelFormat || "-")
            }
            DebugRow {
                visible: !root.isCollapsed("input")
                label: "峰值"
                // sig-peak 是归一化倍数（×100 = nits）
                value: playerState.videoParamsSigPeak > 0
                       ? (playerState.videoParamsSigPeak * 100).toFixed(0)
                         + " nits"
                       : "-"
            }
            DebugRow {
                visible: !root.isCollapsed("input")
                label: "编码"
                value: playerState.videoFormat || "-"
            }
            DebugRow {
                visible: !root.isCollapsed("input")
                label: "硬解"
                value: playerState.hwdecCurrent || "-"
                severity: (!playerState.hwdecCurrent
                           || playerState.hwdecCurrent === "no")
                          ? "warn" : "good"
            }

            // ═══ HDR 输出 ═══
            DebugGroupHeader {
                title: "HDR 输出"
                collapsed: root.isCollapsed("output")
                highlighted: true
                onToggleRequested: root.toggle("output")
            }
            DebugRow {
                visible: !root.isCollapsed("output")
                label: "路径"
                value: playerState.hdrOutput
                       ? "Surface · HDR 直出"
                       : "Surface · SDR（tone map）"
                severity: playerState.hdrOutput ? "good" : "normal"
            }
            DebugRow {
                visible: !root.isCollapsed("output")
                label: "目标"
                value: (playerState.targetPrim || "-") + " / "
                       + (playerState.targetTrc || "-")
                severity: root.isHdrOut() ? "good" : "normal"
            }
            DebugRow {
                visible: !root.isCollapsed("output")
                label: "映射"
                value: (playerState.toneMapping || "-")
                       + (playerState.toneMappingMode
                          ? " (" + playerState.toneMappingMode + ")" : "")
                // 697：DV 必须用 bt.2390，否则高光细节丢失
                severity: (root.isDv() && playerState.toneMapping !== "bt.2390")
                          ? "error" : "good"
            }
            DebugRow {
                visible: !root.isCollapsed("output")
                label: "峰值计算"
                value: playerState.hdrComputePeak || "-"
            }

            // ═══ 杜比视界 ═══
            DebugGroupHeader {
                title: "杜比视界"
                collapsed: root.isCollapsed("dv")
                highlighted: true
                onToggleRequested: root.toggle("dv")
            }
            DebugRow {
                visible: !root.isCollapsed("dv")
                label: "Profile"
                value: playerState.doviProfile > 0
                       ? "P" + playerState.doviProfile
                         + (playerState.doviProfile === 5
                            ? "（单层 IPT）" : "")
                         + (playerState.doviLevel > 0
                            ? " L" + playerState.doviLevel : "")
                       : (playerState.dvContent
                          ? "DV（Profile 未知 · Emby 元数据）"
                          : "非 DV 内容")
            }
            DebugRow {
                visible: !root.isCollapsed("dv") && root.isDv()
                label: "识别"
                value: playerState.dvContent
                       ? "已识别为 DV" : "未识别（按普通 HDR 处理）"
                severity: playerState.dvContent ? "good" : "error"
            }
            DebugRow {
                visible: !root.isCollapsed("dv") && root.isDv()
                label: "后端"
                value: (playerState.gpuContext || "-")
                       + (root.backendSupportsDv()
                          ? " · 支持 DV" : " · 不支持 DV")
                severity: root.backendSupportsDv() ? "good" : "warn"
            }
            DebugRow {
                // P5 单层 IPT + 后端不支持 → 画面必偏色，明确报错
                visible: !root.isCollapsed("dv")
                         && root.isDv()
                         && playerState.doviProfile === 5
                         && !root.backendSupportsDv()
                label: "P5 风险"
                value: "后端不支持 DV，画面会偏色"
                severity: "error"
            }

            // ═══ 渲染管线 ═══
            DebugGroupHeader {
                title: "渲染管线"
                collapsed: root.isCollapsed("pipeline")
                onToggleRequested: root.toggle("pipeline")
            }
            DebugRow {
                visible: !root.isCollapsed("pipeline")
                label: "vo"
                value: playerState.currentVo || "-"
            }
            DebugRow {
                visible: !root.isCollapsed("pipeline")
                label: "gpu-api"
                value: playerState.gpuApi || "-"
            }
            DebugRow {
                visible: !root.isCollapsed("pipeline")
                label: "gpu-context"
                value: playerState.gpuContext || "-"
            }
            DebugRow {
                visible: !root.isCollapsed("pipeline")
                label: "输出"
                value: playerState.videoOutputActual || "-"
            }
        }
    }
}
