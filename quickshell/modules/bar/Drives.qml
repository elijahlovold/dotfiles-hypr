pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Drives + MTP phones (state in DrivesState.qml, event-driven). Always shown
// now that the popup covers every disk: mounted/total filesystems, then the
// phone glyph with a dot while it's mounted. Hover or right-click opens
// DrivesPreview docked, left-click opens it floating.
Item {
    id: root

    readonly property string iconDrive: String.fromCodePoint(0xf02ca) // md-harddisk
    readonly property string iconPhone: String.fromCharCode(0xf10b) // fa-mobile
    readonly property int mountedCount: DrivesState.drives.filter(d => d.mountpoint.length > 0).length
    property bool previewOpen: false

    implicitWidth: label.width
    implicitHeight: label.height
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        text: {
            let s = root.iconDrive + "  " + root.mountedCount + "/" + DrivesState.drives.length;
            if (DrivesState.phones.length > 0)
                s += "   " + root.iconPhone + (DrivesState.phoneMount.length > 0 ? "  ●" : "");
            return s;
        }
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
        name: "drives"
        popup: DrivesPreview {
            anchorItem: root
            drives: DrivesState.drives
            phones: DrivesState.phones
            phoneMount: DrivesState.phoneMount
            onActionFinished: DrivesState.refresh()
        }
    }
}
