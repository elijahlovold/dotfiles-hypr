pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.common

// Generic "run a script on an interval, show its stdout" widget - the QML
// equivalent of an i3status-rust `custom` block / waybar `custom/*` module.
Text {
    id: root

    required property list<string> command
    property int interval: 5000
    property string prefix: ""
    property list<string> leftClickCommand: []
    property list<string> rightClickCommand: []
    // Optional right-click popup (e.g. StatorPreview.qml) - takes priority
    // over rightClickCommand when set. Instantiated component must expose
    // `required property Item anchorItem` and `readonly property bool hovered`
    // (see MusicPreview.qml/CalendarPreview.qml for the established shape).
    property Component popupComponent: null
    // Name for keyboard/IPC opening (qs ipc call barpopup open <name>);
    // empty = not registered.
    property string popupName: ""

    property string output: ""
    property bool previewOpen: false

    text: root.output.length > 0 ? root.prefix + root.output : ""
    visible: root.text.length > 0
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    Process {
        id: proc
        command: root.command
        stdout: StdioCollector {
            id: collector
            onStreamFinished: root.output = collector.text.trim()
        }
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        enabled: root.leftClickCommand.length > 0 || root.rightClickCommand.length > 0 || root.popupComponent !== null
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: root.popupComponent !== null
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: opener.hoverEntered()
        onExited: opener.hoverExited()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton && root.popupComponent !== null) {
                opener.toggle();
                return;
            }
            const cmd = mouse.button === Qt.LeftButton ? root.leftClickCommand : root.rightClickCommand;
            if (cmd.length > 0) {
                Quickshell.execDetached(cmd);
                proc.running = true;
            }
        }
    }

    PopupOpener {
        id: opener
        widget: root
        name: root.popupComponent !== null ? root.popupName : ""
        available: root.popupComponent !== null
        popup: root.popupComponent
    }
}
