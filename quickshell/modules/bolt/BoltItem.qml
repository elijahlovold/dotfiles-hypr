pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.modules.theme

// One lightning bolt renderer, drawn in this item's own coordinates - use it
// directly inside any window (KeytreeWindow does), or via BoltWindow's
// fullscreen overlay for Bolts.strike(). strike(spec) with
//   { from, to, style }  - from `from` (null = a random point on the bottom
//                          edge near `to`) to `to`
//   { path, style }      - through explicit waypoints, ending at the last
// timed and sized by `style` (a BoltConfig.styles entry). A new strike
// replaces one still in flight. `finished` fires once it has faded out.
//
// Geometry: the main channel is classic midpoint displacement (each
// segment's midpoint pushed sideways by a random amount that shrinks every
// subdivision), plus a few shorter forks. Every frame the points get a
// small fresh jitter so it crackles instead of sliding in as a static line.
// Drawn as stacked QtQuick.Shapes polylines - wide faint accent glow, mid
// accent, thin white core.
Item {
    id: root

    signal finished

    property var style: BoltConfig.styles.popup
    property real targetX: 0
    property real targetY: 0
    readonly property real travelPortion: Math.min(0.95, root.style.travelMs / root.style.totalMs)
    readonly property real widthScale: root.style.width ?? 1

    // 0 -> 1 over the whole strike; everything below derives from it.
    property real t: 0
    property bool striking: false

    property var mainBase: []
    property var forkBases: [] // [{ from: index into mainBase, points: [...] }]

    // Per-frame outputs fed to the Shapes.
    property var mainPoints: []
    property var forkPoints: []
    property real strength: 1

    function displace(x0, y0, x1, y1, levels, spread) {
        return Bolts.displace(x0, y0, x1, y1, levels, spread);
    }

    function strike(spec) {
        strikeAnim.stop();
        root.style = spec.style;
        const end = spec.path ? spec.path[spec.path.length - 1] : spec.to;
        root.targetX = end.x;
        root.targetY = end.y;
        if (spec.path)
            root.generatePath(spec.path);
        else
            root.generate(spec.from);
        root.striking = true;
        root.t = 0;
        root.frame();
        strikeAnim.start();
    }

    function randomSpread() {
        return root.style.spread * (1 + (Math.random() * 2 - 1) * (root.style.spreadJitter ?? 0.4));
    }

    // Jagged run through explicit waypoints (e.g. a spiral): each leg gets
    // its own small midpoint displacement, `levels` deep. No forks.
    function generatePath(path) {
        const spread = root.randomSpread();
        let pts = [path[0]];
        for (let i = 1; i < path.length; i++) {
            const a = path[i - 1], b = path[i];
            const leg = root.displace(a.x, a.y, b.x, b.y, root.style.levels, Math.hypot(b.x - a.x, b.y - a.y) * spread);
            pts = pts.concat(leg.slice(1));
        }
        root.mainBase = pts;
        root.forkBases = [];
    }

    function generate(from) {
        const w = root.width, h = root.height;
        // Default launch point: somewhere on the bottom edge within ~35% of
        // the screen width of the target, so it reads as heading for it.
        const startX = from ? from.x : Math.max(w * 0.05, Math.min(w * 0.95, root.targetX + (Math.random() * 2 - 1) * w * 0.35));
        const startY = from ? from.y : h;
        const length = Math.hypot(root.targetX - startX, root.targetY - startY);
        const spread = root.randomSpread();
        root.mainBase = root.displace(startX, startY, root.targetX, root.targetY, root.style.levels, length * spread);

        const n = root.mainBase.length;
        const forks = [];
        const [minForks, maxForks] = root.style.forks;
        const count = minForks + Math.floor(Math.random() * (maxForks - minForks + 1));
        for (let f = 0; f < count && n > 3; f++) {
            const at = Math.min(n - 2, Math.floor(n * 0.12 + Math.random() * n * 0.55));
            const a = root.mainBase[at], b = root.mainBase[Math.min(at + 2, n - 1)];
            const dir = Math.atan2(b.y - a.y, b.x - a.x) + (Math.random() < 0.5 ? -1 : 1) * (0.4 + Math.random() * 0.5);
            const len = length * (0.08 + Math.random() * 0.14);
            forks.push({
                from: at,
                points: root.displace(a.x, a.y, a.x + Math.cos(dir) * len, a.y + Math.sin(dir) * len, 4, len * 0.25)
            });
        }
        root.forkBases = forks;
    }

    // Polyline from fraction `start` (rounded down to a point) to `fraction`,
    // interpolating the last point.
    function partial(pts, fraction, jitter, start) {
        const out = [];
        const last = Math.max(0, Math.min(pts.length - 1, fraction * (pts.length - 1)));
        const whole = Math.floor(last);
        const first = Math.min(whole, Math.floor((start ?? 0) * (pts.length - 1)));
        for (let i = first; i <= whole; i++) {
            const j = i === 0 ? 0 : jitter;
            out.push(Qt.point(pts[i].x + (Math.random() * 2 - 1) * j, pts[i].y + (Math.random() * 2 - 1) * j));
        }
        if (last > whole) {
            const a = pts[whole], b = pts[whole + 1], k = last - whole;
            out.push(Qt.point(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k));
        }
        return out;
    }

    function frame() {
        const travel = Math.min(1, root.t / root.travelPortion);
        const landed = travel >= 1;
        const jitter = landed ? 2.5 : 1;

        // With a tail, only the stretch just behind the head is drawn - a
        // comet rather than the whole channel.
        const tail = root.style.tail ?? 0;
        const tailStart = tail > 0 ? Math.max(0, travel - tail) : 0;
        root.mainPoints = root.partial(root.mainBase, travel, jitter, tailStart);

        const forks = [];
        const headIndex = travel * (root.mainBase.length - 1);
        for (const f of root.forkBases) {
            if (headIndex <= f.from)
                continue;
            // Forks grow out a little behind the head.
            const grown = Math.min(1, (headIndex - f.from) / Math.max(2, (root.mainBase.length - 1) * 0.2));
            forks.push(root.partial(f.points, grown, jitter));
        }
        root.forkPoints = forks;

        // Full brightness while travelling, then a flickering fade.
        const fade = landed ? Math.max(0, 1 - (root.t - root.travelPortion) / (1 - root.travelPortion)) : 1;
        root.strength = fade * (landed ? 0.65 + Math.random() * 0.35 : 1);
    }

    onTChanged: {
        if (root.striking)
            root.frame();
    }

    NumberAnimation {
        id: strikeAnim
        target: root
        property: "t"
        from: 0
        to: 1
        duration: root.style.totalMs
        onFinished: {
            root.striking = false;
            root.mainPoints = [];
            root.forkPoints = [];
            root.finished();
        }
    }

    Shape {
        anchors.fill: parent
        visible: root.striking
        opacity: root.strength * (root.style.opacity ?? 1)
        preferredRendererType: Shape.CurveRenderer

        // Glow
        ShapePath {
            strokeWidth: 10 * root.widthScale
            strokeColor: Theme.withAlpha(Theme.accent, 0.18)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.mainPoints }
        }
        ShapePath {
            strokeWidth: 5 * root.widthScale
            strokeColor: Theme.withAlpha(Theme.accent, 0.12)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: root.forkPoints }
        }
        // Mid
        ShapePath {
            strokeWidth: Math.max(1, 3.5 * root.widthScale)
            strokeColor: Theme.withAlpha(Theme.accent, 0.75)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.mainPoints }
        }
        // Core
        ShapePath {
            strokeWidth: Math.max(0.8, 1.4 * root.widthScale)
            strokeColor: "white"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.mainPoints }
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

    // Impact flash where the bolt meets its target.
    Rectangle {
        readonly property real k: Math.max(0, (root.t - root.travelPortion) / (1 - root.travelPortion))
        visible: root.striking && root.t >= root.travelPortion && root.style.flash > 0
        x: root.targetX - width / 2
        y: root.targetY - height / 2
        width: 8 * root.widthScale + root.style.flash * k
        height: width
        radius: width / 2
        color: Theme.withAlpha(Theme.accent, 0.5)
        opacity: 1 - k
    }
}
