pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Networking
import qs.modules.theme

// Wi-Fi device/network picker opened from Network.qml, entirely on
// Quickshell.Networking (NetworkManager over D-Bus) - the same live model
// the pill reads, so the two can't disagree. That model lives for the
// whole shell session, which doubles as the cache: the popup renders the
// last-known networks/status instantly on open, and active scanning
// (scannerEnabled, only while open) updates rows in place as results land.
//
// Row click: known or open network -> connect(), secured+unknown (or a
// known one failing with NoSecrets) -> inline password field ->
// connectWithPsk(). The connected row gets a disconnect icon, known rows a
// forget icon.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    readonly property var devices: Networking.devices.values.filter(d => d.type === DeviceType.Wifi)
    // Chip choice, else the Intel card (WifiPrimary.qml).
    property string selected: ""
    readonly property NetworkDevice current: popup.devices.find(d => d.name === popup.selected) ?? WifiPrimary.pick(popup.devices)
    readonly property bool radioOn: Networking.wifiEnabled

    // Snapshot of current.networks in display order (connected, known,
    // strongest). Only re-sorted when membership or the connected network
    // changes - not on every signal fluctuation, which would reshuffle rows
    // under the cursor and recreate delegates (wiping a half-typed
    // password). Signal/lock/state bindings on each row stay live anyway.
    property var networks: []
    property string passwordFor: ""
    property WifiNetwork pending: null
    property string error: ""

    function percent(s) {
        return Math.round(s <= 1 ? s * 100 : s);
    }

    function isSecure(net) {
        return net.security !== WifiSecurityType.Open && net.security !== WifiSecurityType.Owe;
    }

    function resort() {
        if (popup.passwordFor.length > 0)
            return;
        const nets = (popup.current?.networks.values ?? []).filter(n => n.name.length > 0);
        nets.sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
        if (nets.length !== popup.networks.length || nets.some((n, i) => n !== popup.networks[i]))
            popup.networks = nets;
    }

    // Keyboard: j/k move through networks, gg/G top/bottom, Enter = click
    // the row, h/l switch between adapters.
    property int cursor: 0

    function moveCursor(index) {
        popup.cursor = Math.max(0, Math.min(popup.networks.length - 1, index));
        list.positionViewAtIndex(popup.cursor, ListView.Contain);
    }

    function cycleDevice(step) {
        if (popup.devices.length < 2)
            return;
        const i = popup.devices.indexOf(popup.current);
        popup.selected = popup.devices[(i + step + popup.devices.length) % popup.devices.length].name;
    }

    onVimAction: (name, count) => {
        switch (name) {
        case "down":
            popup.moveCursor(popup.cursor + count);
            break;
        case "up":
            popup.moveCursor(popup.cursor - count);
            break;
        case "top":
            popup.moveCursor(0);
            break;
        case "bottom":
            popup.moveCursor(popup.networks.length - 1);
            break;
        case "left":
            popup.cycleDevice(-count);
            break;
        case "right":
            popup.cycleDevice(count);
            break;
        case "select":
            if (popup.networks[popup.cursor])
                popup.activate(popup.networks[popup.cursor]);
            break;
        }
    }
    onNetworksChanged: popup.cursor = Math.min(popup.cursor, Math.max(0, popup.networks.length - 1))

    function activate(net) {
        if (net.connected || net.stateChanging)
            return;
        popup.error = "";
        if (net.known || !popup.isSecure(net)) {
            popup.pending = net;
            net.connect();
        } else {
            popup.passwordFor = popup.passwordFor === net.name ? "" : net.name;
        }
    }

    function connectWithPassword(net, password) {
        popup.passwordFor = "";
        popup.error = "";
        popup.pending = net;
        net.connectWithPsk(password);
    }

    // Active scanning only while the popup is open (and only on the adapter
    // being shown); NetworkManager's own background scans keep the cached
    // list reasonably fresh the rest of the time.
    property NetworkDevice scanning: null
    function setScanning(dev) {
        if (popup.scanning && popup.scanning !== dev)
            popup.scanning.scannerEnabled = false;
        popup.scanning = dev;
        if (dev)
            dev.scannerEnabled = true;
    }

    onCurrentChanged: {
        popup.setScanning(popup.current);
        popup.passwordFor = "";
        popup.resort();
    }
    Component.onCompleted: {
        popup.setScanning(popup.current);
        popup.resort();
    }
    Component.onDestruction: popup.setScanning(null)

    Connections {
        target: popup.current?.networks ?? null
        function onValuesChanged() {
            popup.resort();
        }
    }

    Connections {
        target: popup.current
        function onStateChanged() {
            popup.resort();
        }
    }

    Connections {
        target: popup.pending
        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets) {
                popup.passwordFor = popup.pending.name;
                popup.error = "Password required for " + popup.pending.name;
            } else {
                popup.error = popup.pending.name + ": " + ConnectionFailReason.toString(reason);
            }
            popup.pending = null;
        }
        function onConnectedChanged() {
            if (popup.pending?.connected)
                popup.pending = null;
        }
    }

    component IconButton: Text {
        id: iconButton
        signal triggered
        property bool active: false

        color: iconMa.containsMouse || iconButton.active ? Theme.accent : Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1

        MouseArea {
            id: iconMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.triggered()
        }
    }

    Item {
        id: card
        width: 340
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 6

            Item {
                width: parent.width
                height: titleText.implicitHeight

                Text {
                    id: titleText
                    text: "Wi-Fi"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                IconButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: Networking.wifiHardwareEnabled
                    text: String.fromCharCode(popup.radioOn ? 0xf205 : 0xf204) // fa-toggle-on / fa-toggle-off
                    active: popup.radioOn
                    onTriggered: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }

            // Device chips - only worth showing with more than one adapter.
            Flow {
                visible: popup.devices.length > 1
                width: parent.width
                spacing: 6

                Repeater {
                    model: popup.devices
                    delegate: Rectangle {
                        id: chip
                        required property NetworkDevice modelData
                        readonly property bool selected: chip.modelData === popup.current

                        width: chipText.implicitWidth + 16
                        height: 22
                        radius: 4
                        color: chip.selected ? Theme.hoverBg : "transparent"
                        border.width: 1
                        border.color: chip.selected ? Theme.accent : Theme.pillBorder

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData.name
                            color: chip.selected ? Theme.text : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.selected = chip.modelData.name
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: {
                    if (popup.devices.length === 0)
                        return "No Wi-Fi adapter";
                    if (!Networking.wifiHardwareEnabled)
                        return "Wi-Fi is hardware-blocked";
                    if (!popup.radioOn)
                        return "Wi-Fi is off";
                    const d = popup.current;
                    if (!d)
                        return "";
                    if (d.state !== ConnectionState.Connected)
                        return d.name + "  ·  " + ConnectionState.toString(d.state).toLowerCase();
                    const net = d.networks.values.find(n => n.connected);
                    return d.name + "  ·  connected" + (net ? " to " + net.name : "");
                }
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
            }

            Text {
                visible: popup.radioOn && popup.current !== null && popup.networks.length === 0
                width: parent.width
                text: "Scanning…"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            ListView {
                id: list
                visible: popup.radioOn && popup.networks.length > 0
                width: parent.width
                height: Math.min(contentHeight, 300)
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: popup.networks

                delegate: Rectangle {
                    id: netRow
                    required property WifiNetwork modelData
                    required property int index
                    readonly property bool isCursor: popup.keyboardActive && popup.cursor === netRow.index
                    readonly property bool asking: popup.passwordFor === netRow.modelData.name

                    width: list.width
                    height: netRow.asking ? 56 : 26
                    radius: 4
                    color: netMa.containsMouse || netRow.asking || netRow.isCursor ? Theme.hoverBg : "transparent"
                    border.width: netRow.isCursor ? 1 : 0
                    border.color: Theme.accent

                    MouseArea {
                        id: netMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: netRow.modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: popup.activate(netRow.modelData)
                    }

                    Item {
                        id: netLine
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        height: 26

                        Text {
                            id: checkIcon
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            text: netRow.modelData.connected ? String.fromCharCode(0xf00c) // fa-check
                                  : netRow.modelData.stateChanging ? "…" : ""
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }

                        Text {
                            anchors.left: checkIcon.right
                            anchors.leftMargin: 4
                            anchors.right: netActions.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: netRow.modelData.name
                            color: netRow.modelData.connected || netRow.modelData.known ? Theme.text : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: netRow.modelData.connected
                            elide: Text.ElideRight
                        }

                        Row {
                            id: netActions
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            IconButton {
                                visible: netRow.modelData.connected
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCharCode(0xf127) // fa-chain-broken
                                onTriggered: netRow.modelData.disconnect()
                            }
                            IconButton {
                                visible: netRow.modelData.known
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCharCode(0xf014) // fa-trash-o
                                onTriggered: netRow.modelData.forget()
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: popup.isSecure(netRow.modelData)
                                text: String.fromCharCode(0xf023) // fa-lock
                                color: Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                horizontalAlignment: Text.AlignRight
                                text: popup.percent(netRow.modelData.signalStrength) + "%"
                                color: Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                    }

                    Rectangle {
                        visible: netRow.asking
                        anchors.top: netLine.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 6
                        anchors.topMargin: 0
                        height: 24
                        radius: 4
                        color: Theme.hoverBg
                        border.color: Theme.pillBorder
                        border.width: 1

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            anchors.margins: 6
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            selectByMouse: true
                            onAccepted: {
                                if (text.length > 0)
                                    popup.connectWithPassword(netRow.modelData, text);
                            }
                            Keys.onEscapePressed: popup.passwordFor = ""

                            Text {
                                visible: passwordInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Password, Enter to connect"
                                color: Theme.dimText
                                font: passwordInput.font
                            }
                        }
                    }

                    onAskingChanged: {
                        if (netRow.asking) {
                            passwordInput.text = "";
                            popup.activateKeyboard();
                            passwordInput.forceActiveFocus();
                        } else if (passwordInput.activeFocus) {
                            // Hand the keys back to the list's vim motions.
                            passwordInput.focus = false;
                            popup.activateKeyboard();
                        }
                    }
                    Component.onCompleted: {
                        if (netRow.asking)
                            passwordInput.forceActiveFocus();
                    }
                }
            }

            Text {
                visible: text.length > 0
                width: parent.width
                topPadding: 2
                text: popup.pending ? "Connecting to " + popup.pending.name + "…" : popup.error
                color: popup.pending ? Theme.dimText : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }
        }
    }
}
