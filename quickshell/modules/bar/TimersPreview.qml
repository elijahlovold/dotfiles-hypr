pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.theme
import qs.modules.overlay

// Opened from Timers.qml: start a timer by typing a duration (see
// TimersState.parse - "25m tea", "1h30m", "10:00", a bare number is
// minutes) or clicking a preset, and pause/resume or cancel running ones.
// Enter starts what's typed; Escape isn't taken, so it bubbles up to
// PillPopup and closes.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    readonly property var parsed: TimersState.parse(field.text)
    readonly property bool invalid: field.text.trim().length > 0 && popup.parsed === null
    // Fixed red, as in ScreenRec - wallust palettes are often too muted
    // for any slot to read as an error.
    readonly property color errorColor: "#ff4d4d"

    function startTyped() {
        if (!popup.parsed)
            return;
        TimersState.start(popup.parsed.ms, popup.parsed.label);
        field.text = "";
    }

    onKeyboardActivated: Qt.callLater(() => field.forceActiveFocus())

    Item {
        id: card
        width: 280
        height: layout.implicitHeight + 32

        Column {
            id: layout
            anchors.centerIn: parent
            width: parent.width - 32
            spacing: 10

            Text {
                text: "Timers"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                font.bold: true
            }

            Rectangle {
                width: parent.width
                height: 26
                radius: 4
                color: Theme.hoverBg
                border.color: popup.invalid ? popup.errorColor : Theme.pillBorder
                border.width: 1

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.margins: 6
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    selectByMouse: true
                    onAccepted: popup.startTyped()

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text.length === 0
                        text: "25m tea, 1h30m, 10:00…"
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: TimersState.presets
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        width: chipLabel.width + 14
                        height: 22
                        radius: 4
                        color: chipMouse.containsMouse ? Theme.hoverBg : "transparent"
                        border.color: Theme.pillBorder
                        border.width: 1

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 4
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Takes the field's label, if one's typed.
                            onClicked: TimersState.start(chip.modelData.ms, popup.parsed?.label ?? field.text.trim())
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.pillBorder
            }

            Text {
                visible: TimersState.timers.length === 0
                text: "No timers"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
            }

            Repeater {
                model: TimersState.timers
                delegate: Column {
                    id: entry
                    required property var modelData
                    readonly property bool running: modelData.endsAt > 0
                    readonly property real remainingMs: TimersState.remaining(modelData)

                    width: layout.width
                    spacing: 4

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - timeText.width - buttons.width - 16
                            text: entry.modelData.label || TimersState.format(entry.modelData.duration)
                            elide: Text.ElideRight
                            color: entry.running ? Theme.text : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }

                        Text {
                            id: timeText
                            anchors.verticalCenter: parent.verticalCenter
                            text: TimersState.format(entry.remainingMs)
                            color: entry.running ? Theme.accent : Theme.dimText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: entry.running
                        }

                        Row {
                            id: buttons
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            // Alarm sound for this timer, off by default.
                            Text {
                                text: entry.modelData.sound ? String.fromCharCode(0xf0f3) : String.fromCharCode(0xf1f6) // fa-bell / fa-bell-slash
                                color: soundMouse.containsMouse ? Theme.accent : entry.modelData.sound ? Theme.text : Theme.dimText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4

                                MouseArea {
                                    id: soundMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: TimersState.toggleSound(entry.modelData.id)
                                }
                            }

                            Text {
                                text: entry.running ? String.fromCharCode(0xf04c) : String.fromCharCode(0xf04b) // fa-pause / fa-play
                                color: pauseMouse.containsMouse ? Theme.accent : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4

                                MouseArea {
                                    id: pauseMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: TimersState.toggle(entry.modelData.id)
                                }
                            }

                            Text {
                                text: String.fromCharCode(0xf00d) // fa-times
                                color: cancelMouse.containsMouse ? popup.errorColor : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 4

                                MouseArea {
                                    id: cancelMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: TimersState.cancel(entry.modelData.id)
                                }
                            }
                        }
                    }

                    // Progress: drains as the timer runs.
                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Theme.hoverBg

                        Rectangle {
                            width: parent.width * Math.min(1, entry.remainingMs / Math.max(1, entry.modelData.duration))
                            height: parent.height
                            radius: parent.radius
                            color: entry.running ? Theme.accent : Theme.dimText
                        }
                    }
                }
            }
        }
    }
}
