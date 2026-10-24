pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme
import qs.modules.overlay

// Recording modes + recent files, right-click-toggled open from
// ScreenRec.qml. Every start/stop goes through scripts/hypr-screenrec; the
// popup closes itself first (actionTaken) so it isn't in the slurp overlay
// or the recording.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    required property string elapsed

    signal actionTaken

    function act(args) {
        popup.actionTaken();
        ScreenRecState.run(args);
    }

    readonly property var modes: ScreenRecState.recording ? [
        { icon: String.fromCharCode(0xf04d), label: "Stop", args: ["stop"] } // fa-stop
    ] : [
        { icon: String.fromCharCode(0xf125), label: "Region", args: ["start", "region"] }, // fa-crop
        { icon: String.fromCharCode(0xf108), label: "Focused monitor", args: ["start", "output"] }, // fa-desktop
        { icon: String.fromCharCode(0xf130), label: "Region + audio", args: ["start", "region", "audio"] } // fa-microphone
    ]

    // Keyboard selection runs across the modes and then the recent files:
    // j/k move, gg/G top/bottom, r jumps to the first recent file, Enter
    // triggers the row (same as clicking it).
    property int selected: 0
    readonly property int rowCount: popup.modes.length + ScreenRecState.recent.length

    function trigger(index) {
        if (index < popup.modes.length) {
            popup.act(popup.modes[index].args);
        } else {
            const file = ScreenRecState.recent[index - popup.modes.length];
            if (!file)
                return;
            popup.actionTaken();
            Quickshell.execDetached(["xdg-open", file]);
        }
    }

    onVimAction: (name, count) => {
        const last = popup.rowCount - 1;
        switch (name) {
        case "down":
            popup.selected = Math.min(last, popup.selected + count);
            break;
        case "up":
            popup.selected = Math.max(0, popup.selected - count);
            break;
        case "top":
            popup.selected = 0;
            break;
        case "bottom":
            popup.selected = last;
            break;
        case "key:r":
            if (ScreenRecState.recent.length > 0)
                popup.selected = popup.modes.length;
            break;
        case "select":
            popup.trigger(popup.selected);
            break;
        }
    }
    onRowCountChanged: popup.selected = Math.min(popup.selected, Math.max(0, popup.rowCount - 1))

    component ActionRow: Rectangle {
        id: actionRow
        required property string icon
        required property string label
        property bool selected: false
        signal triggered

        width: parent?.width ?? 0
        height: 26
        radius: 4
        color: actionMa.containsMouse || actionRow.selected ? Theme.hoverBg : "transparent"
        border.width: actionRow.selected ? 1 : 0
        border.color: Theme.accent

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text {
                width: 16
                text: actionRow.icon
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                text: actionRow.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        MouseArea {
            id: actionMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionRow.triggered()
        }
    }

    Item {
        id: card
        width: 260
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 4

            Text {
                width: parent.width
                text: ScreenRecState.recording ? "Recording  " + popup.elapsed : "Screen recording"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                bottomPadding: 4
            }

            Repeater {
                model: popup.modes
                delegate: ActionRow {
                    required property var modelData
                    required property int index
                    icon: modelData.icon
                    label: modelData.label
                    selected: popup.keyboardActive && popup.selected === index
                    onTriggered: popup.trigger(index)
                }
            }

            Text {
                visible: ScreenRecState.recent.length > 0
                width: parent.width
                text: "Recent"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                topPadding: 8
            }

            Repeater {
                model: ScreenRecState.recent
                delegate: ActionRow {
                    required property string modelData
                    required property int index
                    icon: String.fromCharCode(0xf008) // fa-film
                    label: modelData.split("/").pop()
                    selected: popup.keyboardActive && popup.selected === popup.modes.length + index
                    onTriggered: popup.trigger(popup.modes.length + index)
                }
            }
        }
    }
}
