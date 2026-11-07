pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Countdown timers behind Timers.qml / TimersPreview.qml, shared by every
// bar. Each timer is { id, label, duration, endsAt, left, sound } - ms; endsAt is
// an epoch time while running (0 when paused), left the time remaining
// while paused; sound is whether it plays the alarm (off unless toggled
// on in the popup). Named Timers* rather than Timer*, which QtQuick owns.
//
// One tick drives everything while a timer runs: it updates `now` for the
// countdowns on screen and fires whatever has run out. It compares against
// the wall clock, so a timer that ends during suspend goes off right after
// resume rather than drifting by the time asleep. Nothing ticks while no
// timer runs.
//
// Saved to the cache with absolute end times, so timers survive reloads
// and restarts; one that ran out while the shell was down goes off on load.
//
// Going off: a critical notification (with a Restart action that starts
// the same timer again), plus the freedesktop alarm sound for timers that
// have it on.
Singleton {
    id: root

    property var timers: []
    property int nextId: 1
    property real now: Date.now()

    readonly property var presets: [
        { label: "1m", ms: 60000 },
        { label: "5m", ms: 300000 },
        { label: "10m", ms: 600000 },
        { label: "15m", ms: 900000 },
        { label: "25m", ms: 1500000 },
        { label: "1h", ms: 3600000 }
    ]
    readonly property string sound: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

    readonly property var runningTimers: root.timers.filter(t => t.endsAt > 0)
    // The running timer that ends first, or null.
    readonly property var soonest: root.runningTimers.reduce((a, t) => !a || t.endsAt < a.endsAt ? t : a, null)

    function remaining(t) {
        return t.endsAt > 0 ? Math.max(0, t.endsAt - root.now) : t.left;
    }

    // 3725000 -> "1:02:05", 65000 -> "1:05". Rounds up, so a timer reads
    // 0:01 for its last second rather than 0:00.
    function format(ms) {
        const s = Math.ceil(ms / 1000);
        const h = Math.floor(s / 3600);
        const m = Math.floor(s % 3600 / 60);
        const ss = String(s % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
    }

    // "25" (minutes), "90s", "5m", "1h30m", "1h 30m", "10:00" (m:ss),
    // "1:02:03" (h:mm:ss), optionally followed by a label: "25m tea".
    // Returns { ms, label } or null.
    function parse(text) {
        const m = /^\s*((?:\d+(?:\.\d+)?\s*[hms]\s*)+|\d+(?::\d{1,2}){1,2}|\d+(?:\.\d+)?)(?:\s+(.*\S))?\s*$/i.exec(text ?? "");
        if (!m)
            return null;
        const spec = m[1].replace(/\s+/g, "").toLowerCase();
        let ms = 0;
        if (spec.includes(":")) {
            ms = spec.split(":").reduce((acc, part) => acc * 60 + Number(part), 0) * 1000;
        } else if (/[hms]/.test(spec)) {
            const unit = { h: 3600000, m: 60000, s: 1000 };
            const re = /(\d+(?:\.\d+)?)([hms])/g;
            for (let part = re.exec(spec); part; part = re.exec(spec))
                ms += Number(part[1]) * unit[part[2]];
        } else {
            ms = Number(spec) * 60000;
        }
        ms = Math.round(ms);
        return ms > 0 ? { ms: ms, label: m[2] ?? "" } : null;
    }

    function start(ms, label, sound) {
        root.now = Date.now();
        const t = { id: root.nextId, label: label ?? "", duration: ms, endsAt: root.now + ms, left: 0, sound: !!sound };
        root.nextId += 1;
        root.timers = root.timers.concat([t]);
    }

    function update(id, change) {
        root.now = Date.now();
        root.timers = root.timers.map(t => t.id === id ? Object.assign({}, t, change(t)) : t);
    }

    function pause(id) {
        root.update(id, t => ({ endsAt: 0, left: Math.max(0, t.endsAt - root.now) }));
    }

    function resume(id) {
        root.update(id, t => ({ endsAt: root.now + t.left, left: 0 }));
    }

    function toggle(id) {
        const t = root.timers.find(t => t.id === id);
        if (t)
            t.endsAt > 0 ? root.pause(id) : root.resume(id);
    }

    function toggleSound(id) {
        root.update(id, t => ({ sound: !t.sound }));
    }

    function cancel(id) {
        root.timers = root.timers.filter(t => t.id !== id);
    }

    function fire(t, late) {
        const name = t.label || root.format(t.duration) + " timer";
        const body = late ? "Went off at " + Qt.formatTime(new Date(t.endsAt), "hh:mm") + " while the shell was down" : root.format(t.duration) + " is up";
        // $1 is the sound file, or "" for a silent timer.
        Quickshell.execDetached(["sh", "-c", '[ -n "$1" ] && pw-play "$1" 2>/dev/null & ' + 'action=$(notify-send -a Timers -u critical -A restart=Restart "$2" "$3"); ' + '[ "$action" = restart ] && qs ipc call timers start "$4" "$5" "$6"', "timers", t.sound ? root.sound : "", name, body, String(t.duration), t.label, t.sound ? "1" : "0"]);
    }

    function check() {
        root.now = Date.now();
        const done = root.timers.filter(t => t.endsAt > 0 && t.endsAt <= root.now);
        if (done.length === 0)
            return;
        root.timers = root.timers.filter(t => !done.includes(t));
        for (const t of done)
            root.fire(t, false);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.runningTimers.length > 0
        onTriggered: root.check()
    }

    // ---- Persistence ----
    property bool loaded: false

    function save() {
        if (root.loaded)
            store.setText(JSON.stringify({ nextId: root.nextId, timers: root.timers }));
    }

    onTimersChanged: root.save()

    FileView {
        id: store
        path: Quickshell.cachePath("timers.json")
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(store.text());
                const now = Date.now();
                const missed = (saved.timers ?? []).filter(t => t.endsAt > 0 && t.endsAt <= now);
                root.nextId = saved.nextId ?? 1;
                root.timers = (saved.timers ?? []).filter(t => !missed.includes(t));
                for (const t of missed)
                    root.fire(t, true);
            } catch (e) {}
            root.loaded = true;
            root.save();
        }
        onLoadFailed: root.loaded = true
    }

    // `qs ipc call timers start 300000 tea 1` (last arg: sound on) - also
    // how a notification's Restart action starts the timer again, sound
    // setting included.
    IpcHandler {
        target: "timers"

        function start(ms: string, label: string, sound: string): void {
            const n = Number(ms);
            if (n > 0)
                root.start(n, label, sound === "1");
        }
        // Same syntax as the popup's field: "25m tea", "10:00", ...
        function add(spec: string): string {
            const p = root.parse(spec);
            if (!p)
                return "can't parse: " + spec;
            root.start(p.ms, p.label);
            return "started " + root.format(p.ms);
        }
        function list(): string {
            return root.timers.map(t => `${t.id}\t${root.format(root.remaining(t))}\t${t.endsAt > 0 ? "running" : "paused"}\t${t.sound ? "sound" : "silent"}\t${t.label}`).join("\n");
        }
    }
}
