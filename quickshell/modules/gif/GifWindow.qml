pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.theme

// Trim + export panel, as a full-screen transparent overlay surface with
// the panel centered. Focus works like KeytreeWindow.qml: Exclusive
// keyboard while open, so Hyprland's refocus on any layer unmap (keytree's
// own close, which launches this) can't take the keyboard away, and
// dismissal is explicit - Escape, or a click off the panel. The preview
// loops between the in and out points so what plays is what gets exported.
//
// Keys: j/k source, h/l seek 1s (H/L a frame), space play/pause, i/o set in/out,
// f fps, w width, b browse for a file, Enter export, Esc close (or cancel a
// running export).
PanelWindow {
    id: root

    required property var exporter // Gif.qml
    property string initialFile: ""

    signal dismissed

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "quickshell:gif"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The whole surface takes input, so the pointer is never over a window
    // the compositor could hand focus to; a press off the panel closes.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (contentItem.contains(mapToItem(contentItem, mouse.x, mouse.y)))
                mouse.accepted = false;
            else
                root.dismissed();
        }
    }

    readonly property int panelWidth: Math.min(1100, Math.round(root.screen.width * 0.6))
    readonly property int panelHeight: Math.min(680, Math.round(root.screen.height * 0.7))

    // ── Sources ────────────────────────────────────────────────────────────
    // hypr-screenrec's recordings, newest first, with initialFile (a custom
    // pick) on top when it isn't one of them.
    property var recordings: []
    readonly property var sources: root.initialFile && !root.recordings.includes(root.initialFile) ? [root.initialFile].concat(root.recordings) : root.recordings
    property int sourceIndex: 0
    readonly property string source: root.sources[root.sourceIndex] ?? ""

    Process {
        id: recentProc
        running: true
        command: ["hypr-screenrec", "recent", String(GifConfig.recentCount)]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();
                root.recordings = text.length > 0 ? text.split("\n") : [];
                root.sourceIndex = Math.max(0, root.sources.indexOf(root.initialFile));
            }
        }
    }

    // ── Trim (ms) ──────────────────────────────────────────────────────────
    readonly property real duration: player.duration
    property real inPoint: 0
    property real outPoint: 0
    readonly property real frameMs: 1000 / 30

    // Whether playback is wanted - the only thing that ever starts the
    // player. Seeks, trims and drags leave it alone, so a paused preview
    // stays paused; a drag holds playback only while the button is down.
    property bool playing: true

    function togglePlay() {
        root.playing = !root.playing;
        if (root.playing)
            player.play();
        else
            player.pause();
    }
    function hold() {
        player.pause();
    }
    function release() {
        if (root.playing)
            player.play();
    }

    onSourceChanged: {
        root.inPoint = 0;
        root.outPoint = 0;
    }
    onDurationChanged: {
        if (root.duration > 0 && root.outPoint <= 0)
            root.outPoint = root.duration;
    }

    function seek(ms) {
        player.position = Math.max(0, Math.min(root.duration, ms));
    }
    function setIn(ms) {
        root.inPoint = Math.max(0, Math.min(ms, root.outPoint - root.frameMs));
    }
    function setOut(ms) {
        root.outPoint = Math.min(root.duration, Math.max(ms, root.inPoint + root.frameMs));
    }

    // ── Output settings ────────────────────────────────────────────────────
    property int fpsIndex: 0
    property int widthIndex: 0
    readonly property int fps: GifConfig.fpsOptions[root.fpsIndex]
    readonly property int outWidth: GifConfig.widthOptions[root.widthIndex]

    function exportGif() {
        if (!root.source || root.duration <= 0 || root.exporter.exporting)
            return;
        root.playing = false;
        player.pause();
        root.exporter.startExport(root.source, root.inPoint / 1000, root.outPoint / 1000, root.fps, root.outWidth);
    }

    function fmt(ms) {
        const s = Math.max(0, ms) / 1000;
        const m = Math.floor(s / 60);
        return m + ":" + (s - m * 60).toFixed(2).padStart(5, "0");
    }

    MediaPlayer {
        id: player
        source: root.source ? "file://" + root.source : ""
        videoOutput: videoOut
        // A newly loaded source plays if playback is wanted. LoadedMedia
        // also comes back after seeks, hence `playing` rather than play().
        onMediaStatusChanged: {
            if (player.mediaStatus === MediaPlayer.LoadedMedia && root.playing)
                player.play();
        }
        // Loop the trimmed range. Also pulls a playhead dragged before the
        // in point forward, so playback never runs outside the range.
        onPositionChanged: {
            if (player.playbackState !== MediaPlayer.PlayingState || root.duration <= 0)
                return;
            if (player.position >= root.outPoint || player.position < root.inPoint - 50)
                player.position = root.inPoint;
        }
        // Hitting the real end of the file stops the player rather than
        // looping on its own. A paused step onto the last frame (l) ends
        // up here too, and stays put.
        onPlaybackStateChanged: {
            if (player.playbackState === MediaPlayer.StoppedState && player.mediaStatus === MediaPlayer.EndOfMedia) {
                player.position = root.inPoint;
                if (root.playing)
                    player.play();
            }
        }
    }

    // Pointer starts on the panel, ready for mouse use - cosmetic only.
    Component.onCompleted: {
        Quickshell.execDetached(["hyprctl", "dispatch", "movecursor",
            String(Math.round(root.screen.x + root.screen.width / 2)),
            String(Math.round(root.screen.y + root.screen.height / 2))]);
        contentItem.forceActiveFocus();
    }

    Item {
        id: contentItem
        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        focus: true

        Keys.onPressed: event => {
            const shift = event.modifiers & Qt.ShiftModifier;
            switch (event.key) {
            case Qt.Key_Escape:
                if (root.exporter.exporting)
                    root.exporter.cancelExport();
                else
                    root.dismissed();
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.exportGif();
                break;
            case Qt.Key_J:
            case Qt.Key_Down:
                root.sourceIndex = Math.min(root.sources.length - 1, root.sourceIndex + 1);
                break;
            case Qt.Key_K:
            case Qt.Key_Up:
                root.sourceIndex = Math.max(0, root.sourceIndex - 1);
                break;
            case Qt.Key_H:
            case Qt.Key_Left:
                root.seek(player.position - (shift ? root.frameMs : 1000));
                break;
            case Qt.Key_L:
            case Qt.Key_Right:
                root.seek(player.position + (shift ? root.frameMs : 1000));
                break;
            case Qt.Key_Space:
                root.togglePlay();
                break;
            case Qt.Key_I:
            case Qt.Key_BracketLeft:
                root.setIn(player.position);
                break;
            case Qt.Key_O:
            case Qt.Key_BracketRight:
                root.setOut(player.position);
                break;
            case Qt.Key_F:
                root.fpsIndex = (root.fpsIndex + 1) % GifConfig.fpsOptions.length;
                break;
            case Qt.Key_W:
                root.widthIndex = (root.widthIndex + 1) % GifConfig.widthOptions.length;
                break;
            case Qt.Key_B:
                root.exporter.browse();
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.pillBg
            border.color: Theme.pillBorder
            border.width: 1
        }

        // Source list
        Column {
            id: sourceColumn
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 14
            width: 220
            spacing: 4

            Text {
                text: "Recordings"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                bottomPadding: 4
            }

            Text {
                visible: root.sources.length === 0
                width: parent.width
                text: "No recordings - b to browse"
                color: Theme.dimText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.sources
                delegate: Rectangle {
                    id: sourceRow
                    required property string modelData
                    required property int index
                    width: sourceColumn.width
                    height: 26
                    radius: 4
                    color: sourceRow.index === root.sourceIndex ? Theme.hoverBg : "transparent"
                    border.width: sourceRow.index === root.sourceIndex ? 1 : 0
                    border.color: Theme.accent

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        verticalAlignment: Text.AlignVCenter
                        text: sourceRow.modelData.split("/").pop()
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideMiddle
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sourceIndex = sourceRow.index
                    }
                }
            }
        }

        // Preview, timeline, settings
        Column {
            id: mainColumn
            anchors.left: sourceColumn.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 14
            spacing: 10

            Rectangle {
                width: parent.width
                height: parent.height - timeline.height - infoRow.height - hintText.height - 3 * parent.spacing
                radius: 6
                color: "black"
                clip: true

                VideoOutput {
                    id: videoOut
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.togglePlay()
                }
            }

            // Trim bar: the selected range is filled; drag either handle,
            // click/drag anywhere else to scrub.
            Item {
                id: timeline
                width: parent.width
                height: 34

                function msAt(x) {
                    return Math.max(0, Math.min(1, x / timeline.width)) * root.duration;
                }
                function xOf(ms) {
                    return root.duration > 0 ? ms / root.duration * timeline.width : 0;
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Theme.hoverBg
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: timeline.xOf(root.inPoint)
                    width: timeline.xOf(root.outPoint) - x
                    height: 8
                    radius: 4
                    color: Theme.withAlpha(Theme.accent, 0.6)
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: mouse => {
                        root.hold();
                        root.seek(timeline.msAt(mouse.x));
                    }
                    onPositionChanged: mouse => root.seek(timeline.msAt(mouse.x))
                    onReleased: root.release()
                }

                // Playhead
                Rectangle {
                    x: timeline.xOf(player.position) - 1
                    width: 2
                    height: parent.height
                    color: Theme.text
                }

                // In (0) and out (1) handles.
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: handle
                        required property int index
                        readonly property real ms: handle.index === 0 ? root.inPoint : root.outPoint

                        x: timeline.xOf(handle.ms) - width / 2
                        y: (timeline.height - height) / 2
                        width: 10
                        height: 24
                        radius: 3
                        color: Theme.accent

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.SizeHorCursor
                            onPressed: root.hold()
                            onReleased: root.release()
                            onPositionChanged: mouse => {
                                const ms = timeline.msAt(mapToItem(timeline, mouse.x, 0).x);
                                if (handle.index === 0)
                                    root.setIn(ms);
                                else
                                    root.setOut(ms);
                                root.seek(ms);
                            }
                        }
                    }
                }
            }

            Row {
                id: infoRow
                width: parent.width
                spacing: 16

                component Info: Text {
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Info {
                    text: root.fmt(player.position) + " / " + root.fmt(root.duration)
                }
                Info {
                    text: root.fmt(root.inPoint) + " → " + root.fmt(root.outPoint) + "  (" + ((root.outPoint - root.inPoint) / 1000).toFixed(2) + "s)"
                    color: Theme.accent
                }
                Info {
                    text: root.fps + "fps"
                }
                Info {
                    text: root.outWidth > 0 ? root.outWidth + "px" : "source width"
                }
            }

            Item {
                width: parent.width
                height: hintText.height

                Text {
                    id: hintText
                    visible: !root.exporter.exporting
                    width: parent.width
                    text: "h/l seek · H/L frame · space play · i/o in/out · f fps · w width · b browse · ⏎ export"
                    color: Theme.dimText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.exporter.exporting
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Theme.hoverBg

                    Rectangle {
                        width: parent.width * root.exporter.progress
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                    }
                }
            }
        }
    }
}
