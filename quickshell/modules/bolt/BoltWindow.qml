pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.modules.theme

// Lightning strikes on one screen: a click-through fullscreen overlay that
// Bolt.qml creates on demand and tears down shortly after the last strike.
// strike({ from, to, style }) draws a bolt from `from` (screen-local; null =
// a random point on the bottom edge near the target) to `to`, timed and
// sized by `style` (a BoltConfig.styles entry). A new strike replaces one
// still in flight. BarPopups opens a pill's popup on impact (style
// travelMs), so the bolt is still crackling while the popup drops open.
//
// Geometry: the main channel is classic midpoint displacement (each
// segment's midpoint pushed sideways by a random amount that shrinks every
// subdivision), plus a few shorter forks. Every frame the points get a
// small fresh jitter so it crackles instead of sliding in as a static line.
// Drawn as stacked QtQuick.Shapes polylines - wide faint accent glow, mid
// accent, thin white core.
//
// Needs a Hyprland layer rule disabling animations for the
// "quickshell:bolt" namespace (hypr/hyprland/rules.lua) - otherwise the
// compositor's own layersIn fade eats most of the bolt's lifetime.
PanelWindow {
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

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:bolt"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: Region {}

    function displace(x0, y0, x1, y1, levels, spread) {
        let pts = [{ x: x0, y: y0 }, { x: x1, y: y1 }];
        let d = spread;
        for (let l = 0; l < levels; l++) {
            const next = [pts[0]];
            for (let i = 1; i < pts.length; i++) {
                const a = pts[i - 1], b = pts[i];
                const dx = b.x - a.x, dy = b.y - a.y;
                const len = Math.hypot(dx, dy) || 1;
                const off = (Math.random() * 2 - 1) * d;
                next.push({ x: (a.x + b.x) / 2 - dy / len * off, y: (a.y + b.y) / 2 + dx / len * off });
                next.push(b);
            }
            pts = next;
            d *= 0.55;
        }
        return pts;
    }

    function strike(spec) {
        strikeAnim.stop();
        root.style = spec.style;
        root.targetX = spec.to.x;
        root.targetY = spec.to.y;
        root.generate(spec.from);
        root.striking = true;
        root.t = 0;
        root.frame();
        strikeAnim.start();
    }

    function generate(from) {
        const w = root.screen.width, h = root.screen.height;
        // Default launch point: somewhere on the bottom edge within ~35% of
        // the screen width of the target, so it reads as heading for it.
        const startX = from ? from.x : Math.max(w * 0.05, Math.min(w * 0.95, root.targetX + (Math.random() * 2 - 1) * w * 0.35));
        const startY = from ? from.y : h;
        const length = Math.hypot(root.targetX - startX, root.targetY - startY);
        root.mainBase = root.displace(startX, startY, root.targetX, root.targetY, root.style.levels, length * root.style.spread);

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

    // First `fraction` of a polyline, interpolating the last point.
    function partial(pts, fraction, jitter) {
        const out = [];
        const last = Math.max(0, Math.min(pts.length - 1, fraction * (pts.length - 1)));
        const whole = Math.floor(last);
        for (let i = 0; i <= whole; i++) {
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

        root.mainPoints = root.partial(root.mainBase, travel, jitter);

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
