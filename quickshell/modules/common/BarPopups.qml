pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keyboard/IPC entry point for opening bar popups by name - e.g. the
// keytree "popups" config (Super+P) runs `qs ipc call barpopup open sound`.
// Widgets opt in with a PopupTarget child; summon() picks the instance on
// the focused monitor's bar, fires a lightning strike at its pill (drawn by
// modules/bolt) and opens the popup the moment the bolt lands.
//
// Lives in common rather than bar so modules outside bar (bambu) can
// register without bar <-> bambu becoming a circular import.
Singleton {
    id: root

    // How long the bolt takes to reach the pill - the popup opens on impact.
    // Bolt.qml reads this so the two stay in sync.
    readonly property int travelMs: 90

    property var targets: []

    // Bolt.qml listens; coordinates are screen-local logical pixels.
    signal strike(string screenName, real x, real y)

    function register(target) {
        root.targets = root.targets.concat([target]);
    }

    function unregister(target) {
        root.targets = root.targets.filter(t => t !== target);
    }

    function findPill(item) {
        for (let p = item; p; p = p.parent)
            if (p.isPill === true)
                return p;
        return item;
    }

    function summon(name) {
        const focused = Hyprland.focusedMonitor?.name ?? "";
        const candidates = root.targets.filter(t => t.name === name && t.widget && t.widget.visible && t.widget.width > 0);
        if (candidates.length === 0) {
            Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-u", "low", "-t", "1500", "Bar", "Nothing to show for " + name]);
            return;
        }
        const target = candidates.find(t => t.screenName === focused) ?? candidates[0];
        const pill = root.findPill(target.widget);
        const hit = pill.mapToItem(null, pill.width / 2, pill.height);

        root.pending = target;
        root.pendingPill = pill;
        root.strike(target.screenName, hit.x, hit.y);
        impactTimer.restart();
    }

    property var pending: null
    property Item pendingPill: null

    Timer {
        id: impactTimer
        interval: root.travelMs
        onTriggered: {
            // `summoned` lets PillPopup close it again on its own if the
            // cursor never comes over (no hover -> no hover-out to close it).
            if (root.pendingPill?.isPill)
                root.pendingPill.summoned = true;
            if (root.pending?.widget)
                root.pending.widget.previewOpen = true;
            root.pending = null;
            root.pendingPill = null;
        }
    }

    IpcHandler {
        target: "barpopup"

        function open(name: string): void {
            root.summon(name);
        }
        function list(): string {
            return [...new Set(root.targets.map(t => t.name))].sort().join("\n");
        }
    }
}
