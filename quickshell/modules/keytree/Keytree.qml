import QtQuick
import Quickshell
import Quickshell.Io

// Entry point: instantiate once from shell.qml. Toggled via IPC so Hyprland
// can bind a key to it instead of spawning the old standalone binary, e.g.
//   qs ipc call keytree toggle default
//   qs ipc call keytree toggle stator
Scope {
    id: root

    property string activeConfig: ""

    // A panel still playing its close animation counts as closed - so a
    // quick reopen replaces it rather than toggling it shut.
    readonly property bool isOpen: root.activeConfig.length > 0 && !(panelLoader.item?.closing ?? false)

    function toggle(config) {
        const name = config && config.length > 0 ? config : "default";
        if (root.isOpen && root.activeConfig === name)
            root.close();
        else
            root.open(name);
    }

    function open(config) {
        const name = config && config.length > 0 ? config : "default";
        if (root.isOpen && root.activeConfig === name)
            return;
        // A panel that's closing, or showing another config, is reused:
        // reopen() cancels its close and restarts it at the root level on
        // the same surface (see KeytreePanel.reopen).
        const existing = panelLoader.item;
        root.activeConfig = name;
        if (existing)
            existing.reopen();
    }

    function close() {
        root.activeConfig = "";
    }

    IpcHandler {
        target: "keytree"

        function toggle(config: string): void {
            root.toggle(config);
        }
        function open(config: string): void {
            root.open(config);
        }
        function close(): void {
            root.close();
        }
    }

    Loader {
        id: panelLoader
        active: root.activeConfig.length > 0
        sourceComponent: KeytreePanel {
            id: panel
            configName: root.activeConfig
            // Ignore a late dismiss from a panel that's already been
            // replaced (its close timer can outlive the swap).
            onDismissed: {
                if (panelLoader.item === panel)
                    root.close();
            }
        }
    }
}
