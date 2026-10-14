pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.common

// Left-click toggles a region recording (slurp -> wl-screenrec, see
// scripts/hypr-screenrec), right-click opens ScreenRecPreview for the other
// modes and recent files. Shows a red dot + elapsed time while recording.
Item {
    id: root

    readonly property string iconIdle: String.fromCharCode(0xf03d) // fa-video-camera
    readonly property string iconRec: String.fromCharCode(0xf111) // fa-circle
    property bool previewOpen: false
    property real now: Date.now() / 1000

    readonly property string elapsed: {
        const s = Math.max(0, Math.floor(root.now - ScreenRecState.startedAt));
        return "%1:%2".arg(String(Math.floor(s / 60)).padStart(2, "0")).arg(String(s % 60).padStart(2, "0"));
    }

    implicitWidth: contentRow.width
    implicitHeight: contentRow.height
    width: implicitWidth
    height: implicitHeight

    Timer {
        interval: 1000
        running: ScreenRecState.recording
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now() / 1000
    }

    Row {
        id: contentRow
        spacing: 6

        Text {
            id: recIcon
            anchors.verticalCenter: parent.verticalCenter
            text: ScreenRecState.recording ? root.iconRec : root.iconIdle
            // Fixed red rather than a palette slot - wallust palettes are often too
            // muted for any of them to read as "recording".
            color: ScreenRecState.recording ? "#ff4d4d" : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: ScreenRecState.recording ? Theme.fontSize - 4 : Theme.fontSize

            SequentialAnimation on opacity {
                running: ScreenRecState.recording
                loops: Animation.Infinite
                onRunningChanged: if (!running) recIcon.opacity = 1
                NumberAnimation { to: 0.3; duration: 700 }
                NumberAnimation { to: 1; duration: 700 }
            }
        }

        Text {
            visible: ScreenRecState.recording
            anchors.verticalCenter: parent.verticalCenter
            text: root.elapsed
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton
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
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.previewOpen = !root.previewOpen;
                return;
            }
            root.previewOpen = false;
            ScreenRecState.run(["toggle"]);
        }
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

    // Keyboard/IPC open: qs ipc call barpopup open screenrec
    PopupTarget {
        name: "screenrec"
        widget: root
    }

    Loader {
        id: previewLoader
        active: root.previewOpen
        sourceComponent: ScreenRecPreview {
            anchorItem: root
            elapsed: root.elapsed
            onActionTaken: root.previewOpen = false
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
