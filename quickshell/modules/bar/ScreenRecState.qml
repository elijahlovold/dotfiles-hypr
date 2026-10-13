pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Recording state mirrored from scripts/hypr-screenrec, which owns the
// actual wl-screenrec process (so the keybind and the bar share one source
// of truth). The script pushes `qs ipc call screenrec refresh` whenever a
// recording starts or ends - no polling - and this re-reads its status.
// Singleton so the IpcHandler registers once rather than once per bar.
Singleton {
    id: root

    property bool recording: false
    property string file: ""
    property real startedAt: 0 // epoch seconds
    property var recent: []

    function refresh() {
        if (statusProc.running)
            root.refreshPending = true;
        else
            statusProc.running = true;
    }
    property bool refreshPending: false

    function run(args) {
        Quickshell.execDetached(["hypr-screenrec"].concat(args));
    }

    Process {
        id: statusProc
        command: ["hypr-screenrec", "status"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                const parts = statusOut.text.trim().split("\t");
                root.recording = parts[0] === "recording";
                root.file = root.recording ? parts[1] : "";
                root.startedAt = root.recording ? Number(parts[2]) : 0;
                recentProc.running = true;
            }
        }
        onExited: {
            if (root.refreshPending) {
                root.refreshPending = false;
                statusProc.running = true;
            }
        }
    }

    Process {
        id: recentProc
        command: ["hypr-screenrec", "recent", "5"]
        stdout: StdioCollector {
            id: recentOut
            onStreamFinished: {
                const text = recentOut.text.trim();
                root.recent = text.length > 0 ? text.split("\n") : [];
            }
        }
    }

    IpcHandler {
        target: "screenrec"

        function refresh(): void {
            root.refresh();
        }
    }

    Component.onCompleted: root.refresh()
}
