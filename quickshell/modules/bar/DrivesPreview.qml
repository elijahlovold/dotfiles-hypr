pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme

// Drive/phone list popup, opened from Drives.qml. Clicking a row mounts it
// if needed and opens a terminal there; the trailing icons unmount / eject.
// All actions go through scripts/hypr-usb (udisksctl for drives,
// aft-mtp-mount / android-file-transfer for phones), run as a Process so a
// failure's stderr can be shown inline instead of silently vanishing.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    required property var drives
    required property var phones
    required property string phoneMount

    signal actionFinished

    property string status: ""
    property string lastError: ""
    readonly property bool busy: actionProc.running

    function run(args, message) {
        if (actionProc.running)
            return;
        popup.status = message;
        popup.lastError = "";
        actionProc.command = ["hypr-usb"].concat(args);
        actionProc.running = true;
    }

    // stderr's end and the exit can arrive in either order - whichever
    // lands second settles the final status line.
    Process {
        id: actionProc
        stderr: StdioCollector {
            id: actionErr
            onStreamFinished: {
                const err = actionErr.text.trim();
                popup.lastError = err.length > 0 ? err.split("\n").pop() : "";
                if (!actionProc.running && popup.lastError.length > 0)
                    popup.status = popup.lastError;
            }
        }
        onExited: code => {
            popup.status = code === 0 ? "" : (popup.lastError || "Failed (exit " + code + ")");
            popup.actionFinished();
        }
    }

    // Small clickable glyph used for the per-row actions.
    component IconButton: Text {
        id: iconButton
        signal triggered

        color: iconMa.containsMouse ? Theme.accent : Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        anchors.verticalCenter: parent?.verticalCenter

        MouseArea {
            id: iconMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: iconButton.triggered()
        }
    }

    component SectionLabel: Text {
        width: parent?.width ?? 0
        color: Theme.dimText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        topPadding: 4
    }

    Item {
        id: card
        width: 320
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 4

            Text {
                width: parent.width
                text: "Devices"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            SectionLabel {
                visible: popup.drives.length > 0
                text: "Drives"
            }

            Repeater {
                model: popup.drives
                delegate: Rectangle {
                    id: driveRow
                    required property var modelData
                    readonly property bool mounted: modelData.mountpoint.length > 0

                    width: layout.width
                    height: 38
                    radius: 4
                    color: driveMa.containsMouse ? Theme.hoverBg : "transparent"

                    MouseArea {
                        id: driveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.run(["open", driveRow.modelData.path], "Opening " + driveRow.modelData.path + "…")
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: driveActions.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: (driveRow.modelData.label || driveRow.modelData.model || driveRow.modelData.path)
                                  + "  " + driveRow.modelData.size
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: driveRow.modelData.fstype + "  ·  "
                                  + (driveRow.mounted ? driveRow.modelData.mountpoint : driveRow.modelData.path)
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                            elide: Text.ElideMiddle
                        }
                    }

                    Row {
                        id: driveActions
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        spacing: 12

                        IconButton {
                            visible: driveRow.mounted
                            text: String.fromCharCode(0xf127) // fa-chain-broken (unmount)
                            onTriggered: popup.run(["unmount", driveRow.modelData.path], "Unmounting…")
                        }
                        IconButton {
                            text: String.fromCharCode(0xf052) // fa-eject
                            onTriggered: popup.run(["eject", driveRow.modelData.disk], "Ejecting " + driveRow.modelData.disk + "…")
                        }
                    }
                }
            }

            SectionLabel {
                visible: popup.phones.length > 0
                text: "Phones"
            }

            Repeater {
                model: popup.phones
                delegate: Rectangle {
                    id: phoneRow
                    required property var modelData
                    readonly property bool mounted: popup.phoneMount.length > 0

                    width: layout.width
                    height: 38
                    radius: 4
                    color: phoneMa.containsMouse ? Theme.hoverBg : "transparent"

                    MouseArea {
                        id: phoneMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.run(["open-phone"], "Mounting phone…")
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: phoneActions.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: phoneRow.modelData.name || "Phone"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: phoneRow.mounted ? "mtp  ·  " + popup.phoneMount : "mtp  ·  not mounted"
                            color: Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                            elide: Text.ElideMiddle
                        }
                    }

                    Row {
                        id: phoneActions
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        spacing: 12

                        IconButton {
                            text: String.fromCharCode(0xf2d0) // fa-window-maximize
                            onTriggered: popup.run(["gui-phone"], "Opening Android File Transfer…")
                        }
                        IconButton {
                            visible: phoneRow.mounted
                            text: String.fromCharCode(0xf127) // fa-chain-broken (unmount)
                            onTriggered: popup.run(["unmount-phone"], "Unmounting phone…")
                        }
                    }
                }
            }

            Text {
                visible: popup.status.length > 0
                width: parent.width
                topPadding: 4
                text: popup.status
                color: popup.busy ? Theme.dimText : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }
        }
    }
}
