pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Singleton: callable directly from the shell (keytree actions). shell.qml
// touches it at startup so the IpcHandler below registers. Toggled via IPC, same
// pattern as Keytree/ImagePicker.
//   qs ipc call keybinds toggle
Singleton {
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
