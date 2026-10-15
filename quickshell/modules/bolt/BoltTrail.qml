pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.modules.theme

// Live bolt trailing the cursor for Super+Ctrl+drag (BoltConfig.draw).
// addPoint() takes cursor samples in this item's coordinates; the trail
// keeps the last trailMs of them, so it shortens to just the head glow
// when the cursor stops. end() fades it out, then `finished` fires.
//
// Shape: anchors sit every `spacing` px of distance travelled since the
// drawing started (fixed to the path, so they don't slide as the tail is
// trimmed), and each gap between anchors gets a kink from midpoint
// displacement. The kinks' random numbers are kept per gap and only
// re-rolled every reshapeMs, so between re-rolls it reads as one bolt
// moving with the cursor - just a pixel of jitter per frame on top -
// instead of a fresh flash every frame. A polyline has one width/opacity,
// so the taper is faked with two: the whole trail in glow + accent, the
// newest stretch with the white core.
Item {
    id: root

    signal finished

    readonly property var cfg: BoltConfig.draw
    readonly property real widthScale: root.cfg.width ?? 1

    property bool drawing: false
    readonly property bool busy: root.drawing || frames.running

    property var samples: [] // [{ x, y, t, s }] - s = distance travelled
    property real endTime: 0
    property real fade: 1
    property real flicker: 1

    // Gap index -> its kink's random numbers (and maybe a fork), cleared
    // every reshapeMs.
    property var kinks: ({})
    property real reshapedAt: 0

    // Per-frame outputs fed to the Shape.
    property var trailPoints: []
    property var headPoints: []
    property var forkPoints: []
    property point head: Qt.point(0, 0)

    function addPoint(p) {
        if (!root.drawing) {
            root.drawing = true;
            root.samples = [];
            root.kinks = {};
            root.reshapedAt = Date.now();
            root.fade = 1;
        }
        const prev = root.samples[root.samples.length - 1];
        const s = prev ? prev.s + Math.hypot(p.x - prev.x, p.y - prev.y) : 0;
        root.samples.push({ x: p.x, y: p.y, t: Date.now(), s: s });
        if (root.samples.length === 1)
            root.head = p;
        frames.running = true;
    }

    function end() {
        if (!root.drawing)
            return;
        root.drawing = false;
        root.endTime = Date.now();
    }

    // Point at distance `s` along the samples.
    function pointAt(s) {
        const pts = root.samples;
        for (let i = 1; i < pts.length; i++) {
            if (pts[i].s >= s) {
                const a = pts[i - 1], b = pts[i];
                const k = b.s > a.s ? (s - a.s) / (b.s - a.s) : 1;
                return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k };
            }
        }
        const last = pts[pts.length - 1];
        return { x: last.x, y: last.y };
    }

    // [{ x, y, gap }] - the oldest sample, every multiple of `spacing`
    // after it, and the newest sample. `gap` numbers the stretch ending at
    // that anchor, the same number for as long as that stretch exists.
    function anchorPoints() {
        const pts = root.samples, step = root.cfg.spacing;
        const first = pts[0], last = pts[pts.length - 1];
        const out = [{ x: first.x, y: first.y, gap: -1 }];
        for (let k = Math.floor(first.s / step) + 1; k * step < last.s; k++)
            out.push(Object.assign(root.pointAt(k * step), { gap: k }));
        out.push({ x: last.x, y: last.y, gap: Math.floor(last.s / step) + 1 });
        return out;
    }

    // Random numbers for a gap: one per midpoint for `levels` subdivisions,
    // plus maybe a fork off its start.
    function kink(gap) {
        let k = root.kinks[gap];
        if (!k) {
            const n = Math.pow(2, root.cfg.levels) - 1;
            const offsets = [];
            for (let i = 0; i < n; i++)
                offsets.push(Math.random() * 2 - 1);
            k = {
                offsets: offsets,
                fork: Math.random() < root.cfg.forkChance ? {
                    side: Math.random() < 0.5 ? -1 : 1,
                    angle: 0.5 + Math.random() * 0.7,
                    len: 14 + Math.random() * 22,
                    offsets: [0, 0, 0, 0, 0, 0, 0].map(() => Math.random() * 2 - 1)
                } : null
            };
            root.kinks[gap] = k;
        }
        return k;
    }

    // Bolts.displace, but with the offsets supplied (consumed in order)
    // instead of rolled - so the same gap keeps its shape between re-rolls.
    function displaceWith(a, b, levels, spread, offsets) {
        let pts = [a, b];
        let d = spread, used = 0;
        for (let l = 0; l < levels; l++) {
            const next = [pts[0]];
            for (let i = 1; i < pts.length; i++) {
                const p = pts[i - 1], q = pts[i];
                const dx = q.x - p.x, dy = q.y - p.y;
                const len = Math.hypot(dx, dy) || 1;
                const off = offsets[used++ % offsets.length] * d;
                next.push({ x: (p.x + q.x) / 2 - dy / len * off, y: (p.y + q.y) / 2 + dx / len * off });
                next.push(q);
            }
            pts = next;
            d *= 0.55;
        }
        return pts;
    }

    function frame() {
        const now = Date.now();
        if (root.drawing) {
            // Keep the newest sample even when stale - it's the head.
            const cutoff = now - root.cfg.trailMs;
            let drop = 0;
            while (drop < root.samples.length - 1 && root.samples[drop].t < cutoff)
                drop++;
            if (drop > 0)
                root.samples = root.samples.slice(drop);
        } else {
            root.fade = Math.max(0, 1 - (now - root.endTime) / root.cfg.fadeMs);
            if (root.fade <= 0) {
                frames.running = false;
                root.samples = [];
                root.kinks = {};
                root.trailPoints = [];
                root.headPoints = [];
                root.forkPoints = [];
                root.finished();
                return;
            }
        }
        if (now - root.reshapedAt >= root.cfg.reshapeMs) {
            root.kinks = {};
            root.reshapedAt = now;
        }

        if (root.samples.length < 2) {
            root.trailPoints = [];
            root.headPoints = [];
            root.forkPoints = [];
            return;
        }
        // Here rather than in addPoint so it never runs a frame ahead of
        // the trail's end.
        const newest = root.samples[root.samples.length - 1];
        root.head = Qt.point(newest.x, newest.y);

        const anchors = root.anchorPoints();
        const jitter = root.cfg.jitter;
        const jit = p => Qt.point(p.x + (Math.random() * 2 - 1) * jitter, p.y + (Math.random() * 2 - 1) * jitter);
        let pts = [anchors[0]];
        const forks = [];
        for (let i = 1; i < anchors.length; i++) {
            const a = anchors[i - 1], b = anchors[i];
            // Full-size kinks even on the partial gaps at either end, so
            // they don't flatten out as the tail shortens or the head grows.
            const k = root.kink(b.gap);
            pts = pts.concat(root.displaceWith(a, b, root.cfg.levels, root.cfg.spacing * root.cfg.spread, k.offsets).slice(1));
            if (k.fork && i < anchors.length - 1) {
                const dir = Math.atan2(b.y - a.y, b.x - a.x) + k.fork.side * k.fork.angle;
                const end = { x: a.x + Math.cos(dir) * k.fork.len, y: a.y + Math.sin(dir) * k.fork.len };
                forks.push(root.displaceWith(a, end, 3, k.fork.len * 0.3, k.fork.offsets).map(jit));
            }
        }
        const line = pts.map(jit);
        root.trailPoints = line;
        root.headPoints = line.slice(Math.floor(line.length * 0.55));
        root.forkPoints = forks;
        root.flicker = 0.85 + Math.random() * 0.15;
    }

    FrameAnimation {
        id: frames
        running: false
        onTriggered: root.frame()
    }

    Shape {
        anchors.fill: parent
        visible: root.busy
        opacity: root.fade * root.flicker * (root.cfg.opacity ?? 1)
        preferredRendererType: Shape.CurveRenderer

        // Glow
        ShapePath {
            strokeWidth: 10 * root.widthScale
            strokeColor: Theme.withAlpha(Theme.accent, 0.16)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.trailPoints }
        }
        // Mid
        ShapePath {
            strokeWidth: Math.max(1, 3 * root.widthScale)
            strokeColor: Theme.withAlpha(Theme.accent, 0.7)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.trailPoints }
        }
        // Core, newest stretch only
        ShapePath {
            strokeWidth: Math.max(0.8, 1.4 * root.widthScale)
            strokeColor: "white"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.headPoints }
        }
        ShapePath {
            strokeWidth: Math.max(0.6, root.widthScale)
            strokeColor: Theme.withAlpha("white", 0.7)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: root.forkPoints }
        }
    }

    // Glow on the cursor itself.
    Rectangle {
        visible: root.busy && root.cfg.head > 0
        width: 2 * root.cfg.head
        height: width
        radius: width / 2
        x: root.head.x - width / 2
        y: root.head.y - height / 2
        color: Theme.withAlpha(Theme.accent, 0.45)
        opacity: root.fade
    }
}
