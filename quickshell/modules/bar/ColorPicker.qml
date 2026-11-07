import QtQuick
import Quickshell
import qs.modules.theme

// Click to pick a colour off the screen with hyprpicker: its zoom lens
// shows the colour under the cursor, and the click copies it (hex) to the
// clipboard (-a, via wl-copy). No popup. Not on the bar by default - the
// utils keytree (Super+U, c) runs the same command.
Text {
    id: root

    readonly property string icon: String.fromCharCode(0xf043) // fa-tint

    text: root.icon
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: Quickshell.execDetached(["hyprpicker", "-a"])
    }
}
