pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.common

// Bar pill fed entirely by bambu_statusd.py over a unix socket (persistent
// MQTT connection lives there, not here - see that file's header comment).
// Collapses to nothing whenever the printer isn't actively printing/paused,
// same convention Music.qml uses for "nothing playing".
Item {
    id: root

    readonly property string icon: String.fromCharCode(0xf1b2) // fa-cube
    property bool previewOpen: false

    property var status: ({
        online: false,
        state: "offline",
        file: "",
        percent: 0,
        layer: 0,
        totalLayers: 0,
        remainingMin: 0,
        nozzleTemp: 0,
        nozzleTarget: 0,
        bedTemp: 0,
        bedTarget: 0
    })

    readonly property bool active: root.status.state === "printing" || root.status.state === "paused"

    visible: root.active
    implicitWidth: contentRow.width
    implicitHeight: contentRow.height
    width: implicitWidth
    height: implicitHeight

    // One persistent connection, reconnected automatically by Quickshell if
    // the daemon restarts - never poll/reconnect from this side manually.
    Socket {
        id: sock
        path: BambuConfig.socketPath
        connected: true
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    root.status = JSON.parse(data);
                } catch (e) {
                    // daemon not up yet / mid-write - just wait for the next line
                }
            }
        }
    }

    Row {
        id: contentRow
        spacing: 6

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon + "  " + String(root.status.percent).padStart(3, " ") + "%"
            color: root.status.state === "paused" ? Theme.dimText : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: opener.toggle()
    }

    PopupOpener {
        id: opener
        widget: root
        name: "bambu"
        popup: BambuPreview {
            anchorItem: root
            status: root.status
        }
    }
}
