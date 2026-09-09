import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiWin

ApplicationWindow {
    id: root
    width: 960
    height: 600
    visible: true
    title: qsTr("HimiSync - Windows Client (M0)")

    // 简单明暗切换
    property bool dark: true
    color: dark ? "#1e1e2e" : "#f6f6f6"

    header: ToolBar {
        height: 48
        background: Rectangle { color: root.dark ? "#181825" : "#e0e0e0" }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            Label {
                text: "HimiSync"
                font.bold: true
                font.pointSize: 14
                color: root.dark ? "#cdd6f4" : "#11111b"
            }
            Item { Layout.fillWidth: true }
            Switch {
                checked: root.dark
                onToggled: root.dark = checked
                text: root.dark ? "深色" : "浅色"
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16
        width: Math.min(root.width * 0.7, 460)

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: "M0 工程骨架已验证运行"
            font.pointSize: 20
            font.bold: true
            color: root.dark ? "#cdd6f4" : "#11111b"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: 8
            color: root.dark ? "#313244" : "#ffffff"
            border.color: root.dark ? "#45475a" : "#d0d0d0"
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                Label {
                    text: "RTM 状态"
                    color: root.dark ? "#a6adc8" : "#555"
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: rtmEngine.status
                    font.bold: true
                    color: rtmEngine.status === "connected"
                           ? "#a6e3a1"
                           : (root.dark ? "#f38ba8" : "#d20f39")
                }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            text: "下一步(M1)：接入 Agora RTM C++ SDK，验证登录/加入频道/在线人数。"
            color: root.dark ? "#a6adc8" : "#666"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
