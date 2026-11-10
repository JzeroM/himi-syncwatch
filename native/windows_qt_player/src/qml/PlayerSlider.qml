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
    property color trackColor: theme.secondaryColor
    property color fillColor: theme.focusColor

    /// 拖动/点击连续回调（对应 Flutter Slider onChanged）
    signal moved(real v)
    /// 松手回调（seek 用：只在松手时真正 seek）
    signal finished(real v)

    implicitHeight: 44
    implicitWidth: 260

    // 轨道点击跳转（在 ESlider 之下，不抢手柄事件）
    MouseArea {
        id: trackClick
        anchors.fill: parent
        onClicked: (mouse) => {
            var trackLeft = (root.labelWidth > 0 ? root.labelWidth : 0)
                    + slider.itemSpacing + slider.containerMargins
            var trackW = Math.max(1, width - trackLeft
                                 - (root.showValue ? 60 : 0)
                                 - slider.containerMargins)
            var ratio = Math.max(0, Math.min(1, (mouse.x - trackLeft) / trackW))
            var v = root.minimumValue + ratio * (root.maximumValue - root.minimumValue)
            slider.value = v
            root.moved(v)
            root.finished(v)
        }
    }

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

    // 松手检测（ESlider 只有连续的 userValueChanged）
    Connections {
        target: slider
        function onIsPressedChanged() {
            if (!slider.isPressed) root.finished(slider.value)
        }
    }
}
