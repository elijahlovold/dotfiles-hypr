import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Entry point: instantiate once from shell.qml. Blank every monitor (DPMS
// off, no lock) until the next input.
//   qs ipc call screens off
//
// Hyprland wakes DPMS on *any* key event, releases included
// (misc:key_press_enables_dpms), so blanking straight from a keybind or
// keytree leaf gets undone by letting go of that key. Instead, arm an
// ext-idle-notify monitor: the screens go off once input has gone quiet,
// and its resume edge - the first input after that - turns them back on.
//
// The config uses Hyprland's Lua provider, so `hyprctl dispatch` takes a
// Lua dispatcher expression, not the legacy `dpms off` syntax.
Scope {
    id: root

    property bool armed: false

    IpcHandler {
        target: "screens"

        function off(): void {
            root.armed = true;
        }
    }

    IdleMonitor {
        enabled: root.armed
        timeout: 1
        // Asked for explicitly, so a paused video's inhibitor shouldn't
        // keep the screens lit.
        respectInhibitors: false

        onIsIdleChanged: {
            if (isIdle) {
                Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "off" })']);
            } else if (root.armed) {
                root.armed = false;
                Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "on" })']);
            }
        }
    }
}
