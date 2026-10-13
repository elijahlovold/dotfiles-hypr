pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.theme

Text {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: root.sink?.audio.volume ?? 0
    readonly property bool muted: root.sink?.audio.muted ?? false
    readonly property string iconMuted: String.fromCharCode(0xf026) // fa-volume-off
    readonly property string iconUnmuted: String.fromCharCode(0xf028) // fa-volume-up
    property bool previewOpen: false

    PwObjectTracker {
        objects: [root.sink]
    }

    text: (root.muted ? root.iconMuted : root.iconUnmuted) + "  " + Math.round(root.volume * 100) + "%"
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: closeTimer.stop()
        onExited: closeTimer.restart()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.previewOpen = !root.previewOpen;
            else
                Quickshell.execDetached(["pavucontrol"]);
        }
        onWheel: event => {
            if (!root.sink)
                return;
            const step = 0.05;
            const delta = event.angleDelta.y > 0 ? step : -step;
            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + delta));
        }
    }

    // Grace period so crossing the small gap between the pill and the
    // popup below it doesn't flicker it closed (same as Music.qml).
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
        sourceComponent: SoundPreview {
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
