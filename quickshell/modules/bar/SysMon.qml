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
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: opener.toggle()
    }

    PopupOpener {
        id: opener
        widget: root
        name: "sysmon"
        popup: SysMonPreview {
            anchorItem: root
        }
    }
}
