import QtQuick
import Quickshell
import Quickshell.Io

// Entry point: instantiate once from shell.qml. Toggled via IPC, same
// pattern as Keytree/ImagePicker.
//   qs ipc call keybinds toggle
Scope {
    id: root

    property bool open: false

    function toggle() {
        root.open = !root.open;
    }

    IpcHandler {
        target: "keybinds"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.open = true;
        }
        function close(): void {
            root.open = false;
        }
    }

    Loader {
        active: root.open
        sourceComponent: KeybindsPanel {
            onDismissed: root.open = false
        }
    }
}
