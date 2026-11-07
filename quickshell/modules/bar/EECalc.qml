pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// EE calculators (divider, LED resistor, E-series, colour code) - see
// EECalcPreview. Hover or right-click opens the popup (left-click:
// floating). Lives in OffBarWidgets by default, so it's reached from the
// keytree (Super+U) rather than taking bar space.
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf0e7) // fa-bolt
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onPositionChanged: mouse => opener.hoverMoved(mapToItem(null, mouse.x, mouse.y))
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                opener.toggle();
            else
                opener.toggleFloating();
        }
    }

    PopupOpener {
        id: opener
        widget: root
        name: "eecalc"
        popup: EECalcPreview {
            anchorItem: root
        }
    }
}
