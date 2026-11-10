import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 664：通用选择面板（EvolveUI `ECard` + `EList` 组合，对应 Flutter
// `_openSelectorPanel` 的右侧浮层）。
//
// 【构成】ECard（主题卡片 + 阴影）+ 标题行（EButton 关闭）+ EList
// （display 主文 / sub 副文 / selected 选中勾——EList 的 himi 扩展，
// 见 third_party/evolveui/NOTICE.md）。
//
// 【items 模型】[{ id, display, sub, selected }]：`id` 是业务 id
// （集号/轨 id/速度值/档位名…），EList 的 itemClicked 只回 index，
// 这里映射回业务 id 再上抛。
EUI.ECard {
    id: root

    property string title: ""
    property var items: []          // [{ id, display, sub, selected }]

    signal itemClicked(var id)
    signal closed()

    /// 行高合计（EList 行：有副文 56 / 单行 buttonHeight 44，行距 6）
    readonly property real rowsHeight: {
        var h = 0
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            h += (it.sub !== undefined && it.sub !== "" && it.sub !== null)
                 ? 56 : 44
            if (i < items.length - 1) h += 6
        }
        return h
    }

    width: Math.max(Theme.panelMinWidth,
                    Math.min(Theme.panelMaxWidth,
                             parent ? parent.width * 0.42 : Theme.panelMinWidth))
    height: Math.min(parent ? parent.height - Theme.panelTopOffset
                                  - Theme.panelBottomOffset : 400,
                     root.padding * 2 + 36 + root.rowsHeight)
    radius: 20
    visible: false

    // ── 标题行 ──
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 36

        Text {
            Layout.fillWidth: true
            text: root.title
            color: theme.textColor
            font.pixelSize: Theme.panelTitleSize
            font.weight: 600
        }
        ControlButton {
            icon: Icons.close
            iconSize: 18
            tooltip: "关闭"
            onClicked: root.closed()
        }
    }

    // ── 行列表（EList；底色/阴影交给外层 ECard）──
    EUI.EList {
        Layout.fillWidth: true
        Layout.preferredHeight: root.rowsHeight
        backgroundVisible: false
        shadowEnabled: false
        buttonHeight: 44
        model: root.items
        onItemClicked: (index, data) => root.itemClicked(root.items[index].id)
    }
}
