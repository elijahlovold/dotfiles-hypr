pragma Singleton
import QtQuick
import Quickshell

// Which Wi-Fi interface counts as "the" Wi-Fi for the bar - the Intel card,
// not the Realtek also in this machine, whichever order NetworkManager
// happens to list them in.
Singleton {
    id: root

    readonly property string iface: "wlp11s0"

    // Picks the preferred adapter out of a list of NetworkDevices, falling
    // back to the first one if it's missing.
    function pick(devices) {
        return devices.find(d => d.name === root.iface) ?? devices[0] ?? null;
    }
}
