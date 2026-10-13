pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme

// Log popup, right-click-toggled open from Stator.qml. Same pipeline as
// MusicPreview.qml/CalendarPreview.qml: just tails `stator-rs --log`, no
// QML-side reimplementation needed since the formatting (columns, bar
// chart) already comes fully rendered from the tool itself.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    property string logText: ""

    Process {
        id: proc
        command: ["bash", "-c", "stator-rs --log | tail -n 20"]
        running: true
        stdout: StdioCollector {
            id: collector
            onStreamFinished: popup.logText = collector.text.replace(/\s+$/, "")
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: proc.running = true
    }

    // Only mapped once the log is actually loaded, so the surface is
    // created already at its final size instead of appearing small (while
    // "Loading..." is showing) and needing to grow once the real content
    // arrives - popup/layer-shell surfaces don't reliably live-resize
    // after being mapped.
    visible: popup.logText.length > 0

    Item {
        id: card
        width: logView.implicitWidth + 32
        height: logView.implicitHeight + 32

        Text {
            id: logView
            anchors.centerIn: parent
            text: popup.logText.length > 0 ? popup.logText : "Loading…"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
    }
}
