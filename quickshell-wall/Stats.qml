import QtQuick

// Playback instrumentation for a Slot, on with WALL_STATS=1 (see WallConfig).
// Logs delivered fps, the longest wait between two frames and the loop
// count every 5s, so a stall at the loop seam shows up as a gap.
QtObject {
    id: root

    property bool enabled: false
    property string name: ""
    property int position: 0

    property int frames: 0
    property real last: 0
    property real worst: 0
    property int gaps: 0
    property int loops: 0
    property int lastPos: 0
    property real since: Date.now()

    function frame() {
        const now = Date.now();
        if (root.last > 0) {
            const dt = now - root.last;
            root.worst = Math.max(root.worst, dt);
            // 2.5 frames at 60fps / 1.25 at 24 - a visibly dropped frame either way.
            if (dt > 50)
                root.gaps++;
        }
        root.last = now;
        root.frames++;
    }

    onPositionChanged: {
        if (root.position < root.lastPos)
            root.loops++;
        root.lastPos = root.position;
    }

    onEnabledChanged: {
        root.frames = 0;
        root.last = 0;
        root.loops = 0;
        root.lastPos = 0;
        root.since = Date.now();
    }

    readonly property Timer timer: Timer {
        running: root.enabled
        repeat: true
        interval: 5000
        onTriggered: {
            const secs = (Date.now() - root.since) / 1000;
            console.info(`wallpaper: stats fps=${(root.frames / secs).toFixed(1)} worst_gap_ms=${root.worst} gaps_over_50ms=${root.gaps} loops=${root.loops} ${root.name}`);
            root.frames = 0;
            root.worst = 0;
            root.gaps = 0;
            root.loops = 0;
            root.since = Date.now();
        }
    }
}
