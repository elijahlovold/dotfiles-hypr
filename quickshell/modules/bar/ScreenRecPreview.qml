pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme

// Recording modes + recent files, right-click-toggled open from
// ScreenRec.qml. Every start/stop goes through scripts/hypr-screenrec; the
// popup closes itself first (actionTaken) so it isn't in the slurp overlay
// or the recording.
PopupWindow {
    id: popup

    required property Item anchorItem
    required property string elapsed

    signal actionTaken

    readonly property alias hovered: cardHoverHandler.hovered

    function act(args) {
        popup.actionTaken();
        ScreenRecState.run(args);
    }

    anchor {
        item: popup.anchorItem
        edges: Edges.Bottom
        gravity: Edges.Bottom
        margins.top: 0
    }

    visible: true
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    component ActionRow: Rectangle {
        id: actionRow
        required property string icon
        required property string label
        signal triggered

        width: parent?.width ?? 0
        height: 26
        radius: 4
        color: actionMa.containsMouse ? Theme.hoverBg : "transparent"

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

    PopupFrame {
        id: card
        width: 260
        height: layout.implicitHeight + 32

        HoverHandler { id: cardHoverHandler }

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

            ActionRow {
                visible: ScreenRecState.recording
                icon: String.fromCharCode(0xf04d) // fa-stop
                label: "Stop"
                onTriggered: popup.act(["stop"])
            }
            ActionRow {
                visible: !ScreenRecState.recording
                icon: String.fromCharCode(0xf125) // fa-crop
                label: "Region"
                onTriggered: popup.act(["start", "region"])
            }
            ActionRow {
                visible: !ScreenRecState.recording
                icon: String.fromCharCode(0xf108) // fa-desktop
                label: "Focused monitor"
                onTriggered: popup.act(["start", "output"])
            }
            ActionRow {
                visible: !ScreenRecState.recording
                icon: String.fromCharCode(0xf130) // fa-microphone
                label: "Region + audio"
                onTriggered: popup.act(["start", "region", "audio"])
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
                    icon: String.fromCharCode(0xf008) // fa-film
                    label: modelData.split("/").pop()
                    onTriggered: {
                        popup.actionTaken();
                        Quickshell.execDetached(["xdg-open", modelData]);
                    }
                }
            }
        }
    }
}
