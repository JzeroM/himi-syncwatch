import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiWin

ApplicationWindow {
    id: root
    width: 920
    height: 640
    visible: true
    minimumWidth: 760
    minimumHeight: 560
    title: qsTr("HimiSync - Windows Client (M1: Agora RTM)")

    property bool dark: true
    color: dark ? "#1e1e2e" : "#f6f6f6"

    function ac(c1, c2) { return root.dark ? c1 : c2 }

    header: ToolBar {
        height: 48
        background: Rectangle { color: ac("#181825", "#e0e0e0") }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            Label { text: "HimiSync"; font.bold: true; font.pointSize: 14
                    color: ac("#cdd6f4", "#11111b") }
            Rectangle {
                Layout.leftMargin: 12
                width: 10; height: 10; radius: 5
                color: rtmEngine.status === "connected" ? "#a6e3a1"
                     : rtmEngine.status === "subscribed" ? "#f9e2af"
                     : ac("#f38ba8", "#d20f39")
            }
            Label { text: rtmEngine.status; color: ac("#a6adc8", "#555") }
            Item { Layout.fillWidth: true }
            Label { text: "在线: " + rtmEngine.onlineCount; font.bold: true
                    color: ac("#a6e3a1", "#0a7c3a") }
            Switch {
                Layout.leftMargin: 12
                checked: root.dark
                onToggled: root.dark = checked
                text: root.dark ? "深色" : "浅色"
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // 连接参数区
        GridLayout {
            columns: 6
            columnSpacing: 6
            rowSpacing: 6

            Label { text: "AppID"; color: ac("#a6adc8", "#555") }
            TextField {
                id: fAppId; Layout.preferredWidth: 170
                placeholderText: "声网 AppID"
            }
            Label { text: "用户ID"; color: ac("#a6adc8", "#555") }
            TextField {
                id: fUserId; Layout.preferredWidth: 130
                placeholderText: "如 test_01"
            }
            Label { text: "Token"; color: ac("#a6adc8", "#555") }
            TextField {
                id: fToken; Layout.preferredWidth: 220
                placeholderText: "控制台生成的临时 token"
            }

            Label { text: "频道"; color: ac("#a6adc8", "#555") }
            TextField {
                id: fChannel; Layout.preferredWidth: 220
                placeholderText: "房间号/频道名"
            }
            Button { text: "登录"; onClicked: rtmEngine.login(fAppId.text, fUserId.text, fToken.text) }
            Button { text: "登出"; onClicked: rtmEngine.logout() }
            Button { text: "订阅"; onClicked: rtmEngine.subscribeChannel(fChannel.text) }
            Button { text: "刷新人数"; onClicked: rtmEngine.refreshOnlineCount(fChannel.text) }
        }

        // 发送区
        RowLayout {
            TextField {
                id: fMsg; Layout.fillWidth: true
                placeholderText: "输入要广播的 JSON 消息..."
            }
            Button { text: "发布"; onClicked: { rtmEngine.publishMessage(fMsg.text); fMsg.clear() } }
        }

        // 日志区
        Item { Layout.fillWidth: true; Layout.preferredHeight: 6 }
        Label { text: "运行日志"; color: ac("#a6adc8", "#555"); font.bold: true }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: ac("#11111b", "#ffffff")
            border.color: ac("#45475a", "#d0d0d0")
            Flickable {
                anchors.fill: parent
                anchors.margins: 6
                contentHeight: logText.implicitHeight
                clip: true
                TextArea {
                    id: logText
                    width: parent.width
                    readOnly: true
                    text: rtmEngine.log
                    color: ac("#cdd6f4", "#11111b")
                    selectByMouse: true
                }
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
}
