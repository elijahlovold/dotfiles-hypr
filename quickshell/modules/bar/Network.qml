pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.modules.theme
import qs.modules.common

Text {
    id: root

    // The Intel adapter (see WifiPrimary.qml), not just whichever Wi-Fi
    // device NetworkManager lists first.
    readonly property NetworkDevice wifiDevice: WifiPrimary.pick(Networking.devices.values.filter(d => d.type === DeviceType.Wifi))
    readonly property int state: root.wifiDevice?.state ?? ConnectionState.Disconnected
    readonly property WifiNetwork activeNetwork: root.wifiDevice?.networks.values.find(n => n.connected) ?? null
    // Quickshell reports 0-1; tolerate a 0-100 backend just in case.
    readonly property int signalPercent: {
        const s = root.activeNetwork?.signalStrength ?? 0;
        return Math.round(s <= 1 ? s * 100 : s);
    }
    readonly property string iconConnected: String.fromCharCode(0xf1eb) // fa-wifi
    readonly property string iconDisconnected: "󰖪"

    // Throughput of wifiDevice in Mbps, from /proc/net/dev byte counters
    // (same FileView + Timer approach as Cpu.qml - no process spawned).
    property real downMbps: 0
    property real upMbps: 0
    property var previousSample: null

    function formatMbps(v) {
        return (v < 10 ? v.toFixed(1) : Math.round(v).toString()).padStart(4, " ");
    }

    FileView {
        id: netDevFile
        path: "/proc/net/dev"
    }

    Timer {
        interval: 2000
        running: root.state === ConnectionState.Connected
        repeat: true
        triggeredOnStart: true
        onRunningChanged: {
            root.previousSample = null;
            root.downMbps = 0;
            root.upMbps = 0;
        }
        onTriggered: {
            netDevFile.reload();
            const iface = root.wifiDevice?.name ?? "";
            // "  wlp11s0: rx_bytes rx_packets ... (8 rx fields) tx_bytes ..."
            const line = netDevFile.text().split("\n").find(l => l.trim().startsWith(iface + ":"));
            if (!line)
                return;
            const fields = line.split(":")[1].trim().split(/\s+/).map(Number);
            const sample = { time: Date.now(), rx: fields[0], tx: fields[8] };
            const prev = root.previousSample;
            if (prev && sample.time > prev.time) {
                const secs = (sample.time - prev.time) / 1000;
                root.downMbps = Math.max(0, sample.rx - prev.rx) * 8 / 1e6 / secs;
                root.upMbps = Math.max(0, sample.tx - prev.tx) * 8 / 1e6 / secs;
            }
            root.previousSample = sample;
        }
    }

    // Connection state comes from the device itself - the per-network
    // `connected` flag can lag behind it (or the AP can be missing from the
    // scan list), which only costs the signal %, not the status.
    text: {
        if (!Networking.wifiEnabled || !root.wifiDevice)
            return root.iconDisconnected + " ";
        switch (root.state) {
        case ConnectionState.Connected:
            return root.iconConnected + "  ↓" + root.formatMbps(root.downMbps) + " ↑" + root.formatMbps(root.upMbps);
        case ConnectionState.Connecting:
            return root.iconConnected + "  …";
        default:
            return root.iconDisconnected + " ";
        }
    }
    opacity: root.state === ConnectionState.Connecting ? 0.6 : 1
    color: Theme.text
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize

    property bool previewOpen: false

    MouseArea {
        anchors.fill: parent
        // Reaches up through the gap above the pill to the screen edge
        // (overshoot past the bar's top is simply off-surface).
        anchors.topMargin: -Theme.barHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            closeTimer.stop();
            hoverOpenTimer.restart();
        }
        onExited: {
            hoverOpenTimer.stop();
            closeTimer.restart();
        }
        onClicked: root.previewOpen = !root.previewOpen
    }

    // Opens on hover after a short dwell, so sweeping the cursor across the
    // bar doesn't flash every popup on the way past. Clicks still toggle.
    Timer {
        id: hoverOpenTimer
        interval: 50
        onTriggered: root.previewOpen = true
    }

    // Grace period so crossing the small gap between the pill and the
    // popup below it doesn't flicker it closed (same as Music.qml).
    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (!(previewLoader.item?.hovered ?? false))
                root.previewOpen = false;
        }
    }

    // Keyboard/IPC open: qs ipc call barpopup open wifi
    PopupTarget {
        name: "wifi"
        widget: root
    }

    Loader {
        id: previewLoader
        active: root.previewOpen
        sourceComponent: WifiPreview {
            anchorItem: root
        }
    }

    Connections {
        target: previewLoader.item
        function onHoveredChanged() {
            if (previewLoader.item.hovered)
                closeTimer.stop();
            else
                closeTimer.restart();
        }
    }
}
