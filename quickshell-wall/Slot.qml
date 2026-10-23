pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia

// One wallpaper player. WallpaperWindow keeps two and alternates them, so
// the incoming video is already playing while the outgoing one still is.
// Black behind the video, like mpv's letterboxing - the bars stay opaque
// when a transition draws this slot over the other one.
Rectangle {
    id: root

    // "" = unloaded (decoder released).
    property string path: ""
    property bool paused: false
    // First frame delivered since the last load().
    property bool ready: false

    signal loaded
    signal failed(string reason)

    function load(path) {
        root.ready = false;
        root.path = path;
    }

    function unload() {
        root.ready = false;
        root.path = "";
    }

    color: "black"

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    MediaPlayer {
        id: player
        // A local path or a stream URL. No AudioOutput: silent.
        source: !root.path ? "" : root.path.startsWith("/") ? "file://" + root.path.split("/").map(encodeURIComponent).join("/") : root.path
        videoOutput: output
        loops: MediaPlayer.Infinite

        onSourceChanged: {
            if (player.source != "" && !root.paused)
                player.play();
        }
        onErrorOccurred: (error, errorString) => root.failed(errorString)
    }

    onPausedChanged: {
        if (!root.path)
            return;
        if (root.paused)
            player.pause();
        else
            player.play();
    }

    // Only while waiting for the first frame (or counting them) - not a
    // JS call on every frame of normal playback.
    Connections {
        target: output.videoSink
        enabled: !root.ready || stats.enabled

        function onVideoFrameChanged() {
            if (!root.ready && root.path) {
                root.ready = true;
                root.loaded();
            }
            if (stats.enabled)
                stats.frame();
        }
    }

    Stats {
        id: stats
        enabled: WallConfig.stats && root.ready
        name: root.path
        // Not read while off, so position changes don't run Stats' handler.
        position: stats.enabled ? player.position : 0
    }
}
