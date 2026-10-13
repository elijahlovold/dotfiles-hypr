pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Click opens a popup with a live unit converter and a timestamp reader -
// both pure QML/JS, no process/service involved.
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf1ec) // fa-calculator
    property bool previewOpen: false

    implicitWidth: label.width
    implicitHeight: label.height
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        text: root.icon
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            closeTimer.stop();
            hoverOpenTimer.restart();
        }
        onExited: {
            hoverOpenTimer.stop();
            closeTimer.restart();
        }
        onClicked: root.previewOpen = !root.previewOpen
    }

    // Opens on hover after a short dwell, so sweeping the cursor across the
    // bar doesn't flash every popup on the way past. Clicks still toggle.
    Timer {
        id: hoverOpenTimer
        interval: 50
        onTriggered: root.previewOpen = true
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!(previewLoader.item?.hovered ?? false))
                root.previewOpen = false;
        }
    }

    // Keyboard/IPC open: qs ipc call barpopup open unittools
    PopupTarget {
        name: "unittools"
        widget: root
    }

    Loader {
        id: previewLoader
        active: root.previewOpen
        sourceComponent: UnitToolsPreview {
            anchorItem: root
        }
    }

    Connections {
        target: previewLoader.item
        function onHoveredChanged() {
            if (previewLoader.item.hovered)
                closeTimer.stop();
            else
                closeTimer.restart();
        }
    }
}
