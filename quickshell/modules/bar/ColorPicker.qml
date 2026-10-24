pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.common

// Click samples a screen pixel via hyprpicker and opens a popup breaking
// the result down into hex/rgb/hsl/hsv, each row click-to-copy. Needs
// `hyprpicker` installed - if the command isn't found the Process just
// produces no output and nothing happens (no popup opens on empty output).
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf043) // fa-tint
    property string lastColor: ""
    property bool previewOpen: false
    property bool picking: false

    implicitWidth: label.width
    implicitHeight: label.height
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        text: root.picking ? "…" : root.icon
        color: root.picking ? Theme.dimText : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Process {
        id: proc
        command: ["hyprpicker", "-f", "hex"]
        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                root.picking = false;
                const hex = collector.text.trim();
                if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
                    root.lastColor = hex;
                    root.previewOpen = true;
                }
            }
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
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.previewOpen = root.lastColor.length > 0 ? !root.previewOpen : false;
                return;
            }
            if (root.picking)
                return;
            root.picking = true;
            proc.running = true;
        }
    }

    PopupOpener {
        id: opener
        widget: root
        name: "colorpicker"
        available: root.lastColor.length > 0
        popup: ColorPickerPreview {
            anchorItem: root
            hex: root.lastColor
        }
    }
}
