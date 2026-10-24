pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.theme
import qs.modules.common

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
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                opener.toggle();
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

    PopupOpener {
        id: opener
        widget: root
        name: "sound"
        popup: SoundPreview {
            anchorItem: root
        }
    }
}
