pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Removable drives + MTP phones from scripts/hypr-usb, re-listed only when
// something actually changes - no polling. Two long-lived watchers feed a
// short debounce (a single plug-in fires a burst of udev events):
//   - `udevadm monitor` for block/usb add/remove (drives, phones)
//   - `findmnt --poll` for mount table changes (udisksctl, aft-mtp-mount,
//     or anything else mounting/unmounting outside the bar)
// Singleton so both bars share one set of watchers.
Singleton {
    id: root

    property var drives: []
    property var phones: []
    property string phoneMount: ""

    function refresh() {
        debounce.restart();
    }

    Process {
        id: listProc
        command: ["hypr-usb", "list"]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                try {
                    const data = JSON.parse(listOut.text);
                    root.drives = data.drives;
                    root.phones = data.phones;
                    root.phoneMount = data.phoneMount;
                } catch (e) {
                    root.drives = [];
                    root.phones = [];
                    root.phoneMount = "";
                }
            }
        }
        // An event that landed mid-list would otherwise be lost.
        onExited: {
            if (root.pending) {
                root.pending = false;
                listProc.running = true;
            }
        }
    }
    property bool pending: false

    Timer {
        id: debounce
        interval: 400
        onTriggered: {
            if (listProc.running)
                root.pending = true;
            else
                listProc.running = true;
        }
    }

    Process {
        id: udevWatch
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block", "--subsystem-match=usb"]
        stdout: SplitParser {
            onRead: root.refresh()
        }
        onExited: restartWatchers.start()
    }

    Process {
        id: mountWatch
        running: true
        command: ["findmnt", "--poll", "--noheadings", "--output", "ACTION"]
        stdout: SplitParser {
            onRead: root.refresh()
        }
        onExited: restartWatchers.start()
    }

    // Watchers shouldn't exit; if one does, bring it back and resync in case
    // an event was missed in between.
    Timer {
        id: restartWatchers
        interval: 2000
        onTriggered: {
            udevWatch.running = true;
            mountWatch.running = true;
            root.refresh();
        }
    }

    Component.onCompleted: listProc.running = true
}
