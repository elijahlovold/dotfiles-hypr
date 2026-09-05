pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme

// Device list popup, right-click-toggled open from SerialWatcher.qml.
// Clicking a device opens a terminal running picocom against it - swap for
// minicom (`minicom -D <dev>`) below if that's what's installed instead.
PopupWindow {
    id: popup

    required property Item anchorItem
    required property var devices

    readonly property alias hovered: cardHoverHandler.hovered

    function openConsole(devicePath) {
        Quickshell.execDetached(["alacritty", "-e", "sh", "-c", 'picocom -b 115200 "$1"', "sh", devicePath]);
    }

    anchor {
        item: popup.anchorItem
        edges: Edges.Bottom
        gravity: Edges.Bottom
        margins.top: 0
    }

    visible: true
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    PopupFrame {
        id: card
        width: 220
        height: layout.implicitHeight + 32

        HoverHandler { id: cardHoverHandler }

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 6

            Text {
                width: parent.width
                text: "Serial devices"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Repeater {
                model: popup.devices
                delegate: Rectangle {
                    required property string modelData
                    width: layout.width
                    height: 24
                    radius: 4
                    color: rowMa.containsMouse ? Theme.hoverBg : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 6
                        text: modelData
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.openConsole(modelData)
                    }
                }
            }
        }
    }
}
