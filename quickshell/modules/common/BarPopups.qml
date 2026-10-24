pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.bolt
import qs.modules.overlay

// Keyboard/IPC entry point for opening bar popups by name - e.g. the
// keytree "popups" config (Super+P) runs `qs ipc call barpopup open sound`.
// Widgets opt in with a PopupTarget child; summon() picks the instance on
// the focused monitor's bar, fires a lightning strike at its pill (drawn by
// modules/bolt - from the keytree node that summoned it, if any) and opens
// the popup the moment the bolt lands.
//
// Lives in common rather than bar so modules outside bar (bambu) can
// register without bar <-> bambu becoming a circular import.
Singleton {
    id: root

    property var targets: []

    // Bar shown/hidden (Super+Ctrl+Space, `qs ipc call bar toggle` - see
    // Bar.qml). Lives here so summon() can tell the pills aren't on screen.
    property bool barShown: true

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
        if (!root.barShown) {
            Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-u", "low", "-t", "1500", "Bar", "Bar is hidden (Super+Ctrl+Space)"]);
            return;
        }
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
        // Keep the keyboard on the overlay through the bolt's flight, so
        // a summon from keytree hands focus straight to the popup.
        Overlays.hold(target.screenName);
        const origin = Bolts.takeOrigin();
        if (!Bolts.active("popup")) {
            root.land();
            return;
        }
        // The popup opens on impact, so the two stay in sync.
        impactTimer.interval = BoltConfig.styles.popup.travelMs;
        Bolts.strike(origin, Bolts.toGlobal(target.screenName, hit.x, hit.y), "popup");
        impactTimer.restart();
    }

    property var pending: null
    property Item pendingPill: null

    function land() {
        // `summoned` lets PillPopup close it again on its own if the
        // cursor never comes over (no hover -> no hover-out to close it).
        if (root.pendingPill?.isPill)
            root.pendingPill.summoned = true;
        if (root.pending?.widget)
            root.pending.widget.previewOpen = true;
        root.pending = null;
        root.pendingPill = null;
        // The popup has claimed the keyboard by now (if it could open).
        Overlays.unhold();
    }

    Timer {
        id: impactTimer
        onTriggered: root.land()
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
