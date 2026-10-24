pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

// Who owns the keyboard, and where every overlay surface lives.
//
// Everything that pops up over the desktop - bar popups, keytree, the
// clipboard/image/GIF/keybind panels, bolts - is an Item inside one
// OverlayHost window per screen (modules/overlay/OverlayHost.qml), never a
// window of its own. At most one OverlaySurface is `modal` at a time: it
// holds the keyboard, and its screen's host takes Exclusive keyboard focus
// and the whole screen's input. Claiming dismisses whichever surface held
// it before, so opening keytree over a focused popup closes the popup.
//
// Keyboard ownership is plain layer-shell keyboard interactivity, not a
// HyprlandFocusGrab: Hyprland records an Exclusive layer as the real focus
// target, so other layers unmapping hand the keyboard back to it instead of
// stealing it (CLayerSurface::onUnmap), and dropping back to None returns
// focus to the last window by itself (CLayerSurface::onCommit).
Singleton {
    id: root

    // screen name -> OverlayHost window
    property var hosts: ({})

    function registerHost(host) {
        const next = Object.assign({}, root.hosts);
        next[host.screenName] = host;
        root.hosts = next;
    }

    function unregisterHost(host) {
        if (root.hosts[host.screenName] !== host)
            return;
        const next = Object.assign({}, root.hosts);
        delete next[host.screenName];
        root.hosts = next;
    }

    function hostFor(screenName) {
        return root.hosts[screenName] ?? root.hosts[root.focusedScreenName()] ?? Object.values(root.hosts)[0] ?? null;
    }

    function focusedScreenName() {
        return Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
    }

    // ── Keyboard ownership ───────────────────────────────────────────────────
    property Item modal: null

    // Screen kept holding the keyboard with no surface on it - bridges a
    // hand-off where the next owner appears a moment later, e.g. keytree
    // summoning a bar popup that opens when its bolt lands. Without it the
    // keyboard would bounce to a window and back in between.
    property string holdScreen: ""

    readonly property string modalScreen: root.modal ? root.modal.screenName : root.holdScreen

    function claim(surface) {
        if (root.modal === surface)
            return;
        const previous = root.modal;
        root.modal = surface;
        root.holdScreen = "";
        if (previous)
            previous.dismiss();
    }

    function release(surface) {
        if (root.modal === surface)
            root.modal = null;
    }

    // Takes effect once the current owner (if any) lets go.
    function hold(screenName) {
        root.holdScreen = screenName;
    }

    function unhold() {
        root.holdScreen = "";
    }

    // A press outside every surface on the modal screen (OverlayHost's
    // backdrop).
    function outsidePressed() {
        if (root.modal)
            root.modal.dismiss();
        else
            root.unhold();
    }
}
