pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.theme

// Output/input device picker + volume, right-click-toggled open from
// Sound.qml. All native Pipewire service state (same as MusicPreview's
// device label) - picking a row sets the preferred default node, which
// pipewire then routes to.
PillPopup {
    id: popup

    cardWidth: card.width
    cardHeight: card.height

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    // Hardware/virtual devices only - app streams (isStream) are left to
    // pavucontrol, still on left-click of the pill.
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)

    PwObjectTracker {
        objects: [popup.sink, popup.source]
    }

    // One "Output"/"Input" block: header with mute toggle, volume slider for
    // the current default, then the selectable device list. Inline
    // components don't see this file's ids, hence everything is passed in.
    component DeviceSection: Column {
        id: section

        required property string title
        required property PwNode current
        required property var nodes
        required property bool isSink
        readonly property real volume: section.current?.audio?.volume ?? 0
        readonly property bool muted: section.current?.audio?.muted ?? false

        function setVolume(v) {
            if (section.current?.audio)
                section.current.audio.volume = Math.max(0, Math.min(1, v));
        }

        width: parent?.width ?? 0
        spacing: 4

        Item {
            width: section.width
            height: titleText.implicitHeight

            Text {
                id: titleText
                text: section.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (section.isSink
                        ? String.fromCharCode(section.muted ? 0xf026 : 0xf028) // fa-volume-off / fa-volume-up
                        : String.fromCharCode(section.muted ? 0xf131 : 0xf130)) // fa-microphone-slash / fa-microphone
                      + "  " + Math.round(section.volume * 100) + "%"
                color: section.muted ? Theme.dimText : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (section.current?.audio)
                            section.current.audio.muted = !section.current.audio.muted;
                    }
                }
            }
        }

        Item {
            id: slider
            width: section.width
            height: 16

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 5
                radius: 2.5
                color: Theme.dimText

                Rectangle {
                    width: parent.width * section.volume
                    height: parent.height
                    radius: parent.radius
                    color: section.muted ? Theme.dimText : Theme.accent
                }
            }

            Rectangle {
                x: track.width * section.volume - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: section.muted ? Theme.dimText : Theme.accent
                border.color: Theme.pillBorder
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => section.setVolume(mouse.x / width)
                onPositionChanged: mouse => {
                    if (pressed)
                        section.setVolume(mouse.x / width);
                }
                onWheel: wheel => section.setVolume(section.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
            }
        }

        Repeater {
            model: section.nodes
            delegate: Rectangle {
                id: deviceRow
                required property PwNode modelData
                readonly property bool isDefault: deviceRow.modelData === section.current

                width: section.width
                height: 24
                radius: 4
                color: deviceMa.containsMouse ? Theme.hoverBg : "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        id: radio
                        text: String.fromCharCode(deviceRow.isDefault ? 0xf192 : 0xf10c) // fa-dot-circle-o / fa-circle-o
                        color: deviceRow.isDefault ? Theme.accent : Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Text {
                        width: parent.width - radio.width - 8
                        text: deviceRow.modelData.description || deviceRow.modelData.nickname || deviceRow.modelData.name
                        color: deviceRow.isDefault ? Theme.text : Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: deviceMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (section.isSink)
                            Pipewire.preferredDefaultAudioSink = deviceRow.modelData;
                        else
                            Pipewire.preferredDefaultAudioSource = deviceRow.modelData;
                    }
                }
            }
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
            spacing: 14

            DeviceSection {
                title: "Output"
                current: popup.sink
                nodes: popup.sinks
                isSink: true
            }

            DeviceSection {
                title: "Input"
                current: popup.source
                nodes: popup.sources
                isSink: false
            }
        }
    }
}
