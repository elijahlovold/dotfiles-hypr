pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.theme

// Detail popup, right-click-toggled open from Bambu.qml. Pure presentation
// over the `status` object the socket already parsed - no process/service
// work happens here.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    required property var status

    readonly property real fraction: Math.max(0, Math.min(1, (popup.status.percent ?? 0) / 100))

    readonly property var rows: [
        { label: "Layer", value: (popup.status.layer ?? 0) + " / " + (popup.status.totalLayers ?? 0) },
        { label: "Remaining", value: (popup.status.remainingMin ?? 0) + " min" },
        { label: "Nozzle", value: (popup.status.nozzleTemp ?? 0) + " / " + (popup.status.nozzleTarget ?? 0) + " °C" },
        { label: "Bed", value: (popup.status.bedTemp ?? 0) + " / " + (popup.status.bedTarget ?? 0) + " °C" }
    ]

    Item {
        id: card
        width: 220
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 8

            Text {
                width: parent.width
                text: popup.status.state === "paused" ? "Paused" : "Printing"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                width: parent.width
                text: popup.status.file
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                elide: Text.ElideRight
            }

            // Progress bar - flat two-rectangle fill, no MultiEffect/mask
            // needed since it's an axis-aligned rectangle-in-rectangle.
            Item {
                width: parent.width
                height: 10

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: Theme.hoverBg
                }
                Rectangle {
                    width: parent.width * popup.fraction
                    height: parent.height
                    radius: 5
                    color: Theme.accent
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: popup.status.percent + "%"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Repeater {
                model: popup.rows
                delegate: Row {
                    required property var modelData
                    width: layout.width
                    spacing: 8

                    Text {
                        width: 80
                        text: modelData.label
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                    }
                    Text {
                        text: modelData.value
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }
        }
    }
}
