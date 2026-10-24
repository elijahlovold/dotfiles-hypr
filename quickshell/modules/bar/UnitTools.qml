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
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: opener.toggle()
    }

    PopupOpener {
        id: opener
        widget: root
        name: "unittools"
        popup: UnitToolsPreview {
            anchorItem: root
        }
    }
}
