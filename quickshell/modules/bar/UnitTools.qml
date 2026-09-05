pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

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
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: closeTimer.stop()
        onExited: closeTimer.restart()
        onClicked: root.previewOpen = !root.previewOpen
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!(previewLoader.item?.hovered ?? false))
                root.previewOpen = false;
        }
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
