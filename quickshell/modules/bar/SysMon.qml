import QtQuick
import qs.modules.theme
import qs.modules.common

// The System pill's content (GPU | CPU | Mem) as one hover target for
// SysMonPreview. The three readouts keep their own light polling; all the
// detailed sampling lives inside the popup and only runs while it's open.
Item {
    id: root

    property bool full: true
    property bool previewOpen: false

    implicitWidth: row.width
    implicitHeight: row.height
    width: implicitWidth
    height: implicitHeight

    Row {
        id: row
        spacing: 10

        AmdGpu {
            full: root.full
        }
        Separator {}
        Cpu {
            full: root.full
        }
        Separator {}
        Memory {
            full: root.full
        }
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (same as Network.qml).
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

    // Short dwell so sweeping across the bar doesn't flash the popup.
    Timer {
        id: hoverOpenTimer
        interval: 50
        onTriggered: root.previewOpen = true
    }

    // Grace period for crossing from the pill into the popup.
    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!(previewLoader.item?.hovered ?? false))
                root.previewOpen = false;
        }
    }

    // Keyboard/IPC open: qs ipc call barpopup open sysmon
    PopupTarget {
        name: "sysmon"
        widget: root
    }

    Loader {
        id: previewLoader
        active: root.previewOpen
        sourceComponent: SysMonPreview {
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
