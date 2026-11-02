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
// the popup the moment the bolt lands. summon(name, true) opens it as a
// floating window centred on the screen instead (see PillPopup), with the
// bolt aimed at the screen centre.
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

    function summon(name, floating) {
        // A floating popup doesn't hang from the bar, so a hidden bar is fine.
        if (!root.barShown && !floating) {
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
        let hit = pill.mapToItem(null, pill.width / 2, pill.height);
        if (floating) {
            const host = Overlays.hostFor(target.screenName);
            hit = Qt.point((host?.width ?? 0) / 2, (host?.height ?? 0) / 2);
        }

        root.pending = target;
        root.pendingPill = pill;
        root.pendingFloating = floating === true;
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
    property bool pendingFloating: false

    function land() {
        const widget = root.pending?.widget ?? null;
        const floating = root.pendingFloating;
        // `summoned` lets PillPopup close it again on its own if the
        // cursor never comes over (no hover -> no hover-out to close it).
        // Floating popups take the keyboard themselves and never hover-close.
        if (!floating && root.pendingPill?.isPill)
            root.pendingPill.summoned = true;
        if (widget) {
            // Already open in the other mode: reopen in the requested one.
            if (widget.previewOpen && Overlays.isFloating(widget) !== floating)
                widget.previewOpen = false;
            if (floating)
                Overlays.floatingAnchor = widget;
            else if (Overlays.isFloating(widget))
                Overlays.floatingAnchor = null;
            widget.previewOpen = true;
        }
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
        function float(name: string): void {
            root.summon(name, true);
        }
        function list(): string {
            return [...new Set(root.targets.map(t => t.name))].sort().join("\n");
        }
    }
}
