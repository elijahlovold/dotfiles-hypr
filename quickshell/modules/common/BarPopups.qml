pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.bolt

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

    // True for a moment after a popup launches its own window: the bar
    // drops its keyboard interactivity to None (Bar.qml) so it can't keep
    // the keyboard the popup's focus grab handed back to it - Hyprland
    // won't move focus off a focused layer when a window maps
    // (misc:layers_hog_keyboard_focus), so the new window would open
    // unfocused. Once the bar has let go, restoring OnDemand doesn't take
    // focus back (that only happens on a click), so the window only needs
    // to cover that hand-off, not the app's startup.
    property bool yieldFocus: false

    function yieldKeyboard() {
        root.yieldFocus = true;
        yieldTimer.restart();
    }

    Timer {
        id: yieldTimer
        interval: 1000
        onTriggered: root.yieldFocus = false
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
