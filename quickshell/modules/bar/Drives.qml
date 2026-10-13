pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme

// Removable drives + MTP phones (state in DrivesState.qml, event-driven). Same
// collapse-when-empty convention as SerialWatcher.qml - invisible unless
// something is plugged in. Left- or right-click opens DrivesPreview.
Item {
    id: root

    readonly property string iconUsb: String.fromCharCode(0xf287) // fa-usb
    readonly property string iconPhone: String.fromCharCode(0xf10b) // fa-mobile
    property bool previewOpen: false

    visible: DrivesState.drives.length > 0 || DrivesState.phones.length > 0
    implicitWidth: label.width
    implicitHeight: label.height
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        text: {
            const parts = [];
            if (DrivesState.drives.length > 0)
                parts.push(root.iconUsb + "  " + DrivesState.drives.length);
            if (DrivesState.phones.length > 0)
                parts.push(root.iconPhone + (DrivesState.phoneMount.length > 0 ? "  ●" : ""));
            return parts.join("   ");
        }
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
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
        // Also drops the popup once the last device is unplugged/ejected,
        // since the pill it's anchored to collapses away.
        active: root.previewOpen && root.visible
        sourceComponent: DrivesPreview {
            anchorItem: root
            drives: DrivesState.drives
            phones: DrivesState.phones
            phoneMount: DrivesState.phoneMount
            onActionFinished: DrivesState.refresh()
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
