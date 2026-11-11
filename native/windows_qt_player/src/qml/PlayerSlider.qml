import QtQuick
import QtQuick.Controls.Basic
import HimiPlayer
import "evolveui" as EUI

// 662：播放器滑杆（EvolveUI `ESlider` 的薄封装）。
//
// 【为什么包一层】两个缺口必须补（不改 EvolveUI 源码，见
// third_party/evolveui/NOTICE.md）：
//   1. ESlider 只支持**拖手柄**，不支持点击轨道跳转——进度条刚需；
//   2. ESlider 拖动时直接给 `value` 赋值，会**打断外部绑定**
//      （QML 赋值即删绑定，之后外部状态变化不再驱动滑杆）。
//      用 `Binding` 对象保护（元素级绑定不会被赋值摧毁）。
//
// 【命中分层】底层 MouseArea 接管轨道点击；ESlider 自身只有手柄
// 带 MouseArea 且在上层——点手柄仍归手柄，点轨道落到底层。
Item {
    id: root

    property string text: ""              // 行标签（空 = 紧凑滑杆）
    property real value: 0                // 外部可绑定
    property real minimumValue: 0
    property real maximumValue: 100
    property string valueSuffix: ""
    property int decimals: 0
    property bool showValue: true         // 右侧数值（纯文字，非 SpinBox）
    property int labelWidth: 44           // 与 Flutter styleSliderRow 标签列同宽
    // 668：玻璃轨道（半透明白，视频透过来）
    property color trackColor: Qt.rgba(1, 1, 1, 0.14)
    property color fillColor: theme.focusColor

    /// 拖动/点击连续回调（对应 Flutter Slider onChanged）
    signal moved(real v)
    /// 松手回调（seek 用：只在松手时真正 seek）
    signal finished(real v)

    implicitHeight: 44
    implicitWidth: 260


    EUI.ESlider {
        id: slider
        anchors.fill: parent
        text: root.text
        minimumValue: root.minimumValue
        maximumValue: root.maximumValue
        valueSuffix: root.valueSuffix
        decimals: root.decimals
        showValueLabel: root.showValue
        showValueText: root.showValue
        showSpinBox: false
        labelWidth: root.labelWidth
        backgroundVisible: true
        trackColor: root.trackColor
        fillColor: root.fillColor
        // 【662 瑕疵修复】ESlider 的 backgroundVisible:false 只藏底色，
        // **描边仍画**（1px theme.textColor 白）→ 滑杆带白框（真机截图）。
        // 走「透明描边」路线：保留暗色轨道底，去掉整圈描边。
        borderColor: "transparent"
        itemSpacing: 8

        // 【绑定保护】拖动期间暂停外部绑定，松手恢复。
        // Binding 元素不会被 slider.value 的命令式赋值摧毁。
        Binding {
            target: slider
            property: "value"
            value: root.value
            when: !slider.isPressed
        }

        onUserValueChanged: (v) => root.moved(v)
    }

    // 【676】松手检测已移除独立 Connections 链（见 trackDrag.onReleased）：
    // isPressed 由 true→false 的瞬间，`Binding`（when: !isPressed）会
    // **立刻把 slider.value 写回 root.value（外部旧值）**，Connections
    // 随后读到旧值再 finished() → seek 回旧位置（真机：进度条拖不动/
    // 点击跳不过去，音量亮度因为有 onMoved 实时回写所以正常）。
    // 现在改为松手时**先显式 finished(拖动值)**，再解除绑定保护。

    // 【675 B / 676】统一按压-拖动（Flutter Slider 语义）：按下即跳到
    // 光标、按住拖动全程跟随。置于 ESlider 之上接管全部鼠标（含手柄区
    // ——抓边不再偏移）。isPressed 悬起既有绑定保护。
    //
    // 【676 松手时序】先 finished(拖动值) 再 isPressed=false——顺序反了
    // 会被 Binding 立刻回写旧值，seek 回旧位置（进度条"拖不动"）。
    MouseArea {
        id: trackDrag
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        property bool active: false

        function applyAt(x) {
            var v = null
            try {
                v = slider.mapXToValue(x)
            } catch (e) {
                v = null
            }
            if (v === null || isNaN(v) || !isFinite(v)) {
                // 自含映射兜底（不依赖 ESlider 内部 id 链）：整宽线性。
                var w = Math.max(1, width)
                var ratio = Math.max(0, Math.min(1, x / w))
                v = root.minimumValue
                        + ratio * (root.maximumValue - root.minimumValue)
            }
            v = Math.max(root.minimumValue, Math.min(root.maximumValue, v))
            slider.value = v
            root.moved(v)
            return v
        }

        onPressed: (mouse) => {
            active = true
            slider.isPressed = true
            applyAt(mouse.x)
        }
        onPositionChanged: (mouse) => {
            if (active) applyAt(mouse.x)
        }
        // 676：松手 = 落到最终位置 → **先回调**（此时 slider.value 还是
        // 拖动值）→ 再解绑（绑定写回的是外部新值，不再二次 seek）。
        onReleased: (mouse) => {
            if (!active) return
            applyAt(mouse.x)
            active = false
            var v = slider.value
            root.finished(v)
            slider.isPressed = false
        }
        onCanceled: {
            active = false
            slider.isPressed = false
        }
    }
}
