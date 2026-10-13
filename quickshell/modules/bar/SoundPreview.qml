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

    // Live signal for one node via PwNodePeakMonitor - for a sink that's
    // what is actually being sent to the device, for a source what the mic
    // is capturing, so "is audio really going through this device" is
    // visible at a glance. Per-channel meters (fast attack, slow fall, peak
    // hold) plus a short scrolling history strip.
    //
    // Fixed height regardless of channel count: the channel list only
    // arrives once the monitor connects, after the popup surface is already
    // mapped, and popup surfaces don't reliably resize after mapping - so
    // rows share a fixed block instead of each adding height.
    component LevelMeter: Column {
        id: meter

        required property PwNode node

        // Peaks are linear amplitude; meters read in dB (-30..0) - anything
        // quieter than -30 dB sits at zero.
        function toPos(p) {
            if (p <= 0.001)
                return 0;
            return Math.max(0, Math.min(1, 1 + (20 * Math.log10(p)) / 30));
        }
        function channelLabel(ch) {
            const s = PwAudioChannel.toString(ch);
            if (s === "FrontLeft")
                return "L";
            if (s === "FrontRight")
                return "R";
            if (s === "Mono")
                return "M";
            return s.replace(/[a-z]/g, "");
        }

        property var levels: [] // per channel, smoothed 0..1
        property var holds: [] // per channel, peak-hold position
        property var holdAges: [] // ticks since each hold was set
        property var history: [] // overall level per tick, newest last
        readonly property int historyLength: Math.max(1, Math.floor(meter.width / 3))
        readonly property bool silent: meter.history.length >= meter.historyLength && meter.history.every(v => v === 0)

        spacing: 6

        PwNodePeakMonitor {
            id: monitor
            node: meter.node
        }

        Timer {
            interval: 33
            running: true
            repeat: true
            onTriggered: {
                const peaks = monitor.peaks;
                const levels = [], holds = [], ages = [];
                for (let i = 0; i < peaks.length; i++) {
                    const level = Math.max(meter.toPos(peaks[i]), (meter.levels[i] ?? 0) - 0.04);
                    let hold = meter.holds[i] ?? 0;
                    let age = (meter.holdAges[i] ?? 0) + 1;
                    if (level >= hold) {
                        hold = level;
                        age = 0;
                    } else if (age > 30) {
                        hold = Math.max(level, hold - 0.02);
                    }
                    levels.push(level);
                    holds.push(hold);
                    ages.push(age);
                }
                meter.levels = levels;
                meter.holds = holds;
                meter.holdAges = ages;
                meter.history = meter.history.concat([meter.toPos(monitor.peak)]).slice(-meter.historyLength);
                historyCanvas.requestPaint();
            }
        }

        Item {
            id: channelBlock
            readonly property int count: Math.max(1, monitor.channels.length)
            readonly property real rowHeight: channelBlock.height / channelBlock.count
            width: meter.width
            height: 16

            Repeater {
                model: monitor.channels
                delegate: Item {
                    id: channelRow
                    required property int index
                    required property var modelData
                    readonly property real level: meter.levels[channelRow.index] ?? 0
                    readonly property real hold: meter.holds[channelRow.index] ?? 0
                    readonly property bool showLabel: channelBlock.count <= 2

                    y: channelRow.index * channelBlock.rowHeight
                    width: channelBlock.width
                    height: channelBlock.rowHeight

                    Text {
                        id: channelLabel
                        visible: channelRow.showLabel
                        width: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: meter.channelLabel(channelRow.modelData)
                        color: Theme.dimText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 6
                    }

                    Item {
                        anchors.left: channelRow.showLabel ? channelLabel.right : parent.left
                        anchors.leftMargin: channelRow.showLabel ? 4 : 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.max(2, Math.min(4, channelRow.height - 2))

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Theme.withAlpha(Theme.dimText, 0.35)
                        }
                        Rectangle {
                            width: parent.width * channelRow.level
                            height: parent.height
                            radius: height / 2
                            color: Theme.accent
                        }
                        // Peak hold - red once it touches 0 dBFS (clipping).
                        Rectangle {
                            visible: channelRow.hold > 0.01
                            x: (parent.width - width) * channelRow.hold
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: parent.height + 2
                            color: channelRow.hold >= 0.995 ? "#ff4d4d" : Theme.text
                        }
                    }
                }
            }
        }

        Item {
            width: meter.width
            height: 20

            Canvas {
                id: historyCanvas
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const h = meter.history;
                    const mid = height / 2;
                    ctx.fillStyle = Theme.accent;
                    for (let i = 0; i < h.length; i++) {
                        const x = width - (h.length - i) * 3;
                        const amp = Math.max(0.5, h[i] * mid);
                        ctx.fillRect(x, mid - amp, 2, amp * 2);
                    }
                }
            }

            Text {
                visible: meter.silent
                anchors.centerIn: parent
                text: "no signal"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 5
            }
        }
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

        LevelMeter {
            node: section.current
            width: section.width
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
