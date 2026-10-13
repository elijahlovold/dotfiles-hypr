pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.theme

// One lightning strike: a click-through fullscreen overlay that exists only
// for the ~300ms the bolt is on screen (see Bolt.qml). The bolt rises from
// a random point on the bottom edge to (targetX, targetY) - the bottom of a
// bar pill - and BarPopups opens that pill's popup on impact
// (BarPopups.travelMs), so the bolt is still crackling while the popup
// drops open.
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

    required property real targetX
    required property real targetY

    signal finished

    readonly property int totalMs: 320
    readonly property real travelPortion: BarPopups.travelMs / root.totalMs

    // 0 -> 1 over the whole strike; everything below derives from it.
    property real t: 0

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

    function generate() {
        const w = root.screen.width, h = root.screen.height;
        // Launch point: somewhere on the bottom edge within ~35% of the
        // screen width of the target, so it reads as heading for it.
        const startX = Math.max(w * 0.05, Math.min(w * 0.95, root.targetX + (Math.random() * 2 - 1) * w * 0.35));
        const length = Math.hypot(root.targetX - startX, root.targetY - h);
        root.mainBase = root.displace(startX, h, root.targetX, root.targetY, 6, length * 0.16);

        const forks = [];
        const count = 2 + Math.floor(Math.random() * 2);
        for (let f = 0; f < count; f++) {
            const from = 8 + Math.floor(Math.random() * (root.mainBase.length * 0.55));
            const a = root.mainBase[from], b = root.mainBase[Math.min(from + 2, root.mainBase.length - 1)];
            const dir = Math.atan2(b.y - a.y, b.x - a.x) + (Math.random() < 0.5 ? -1 : 1) * (0.4 + Math.random() * 0.5);
            const len = length * (0.08 + Math.random() * 0.14);
            forks.push({
                from: from,
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
            const grown = Math.min(1, (headIndex - f.from) / 12);
            forks.push(root.partial(f.points, grown, jitter));
        }
        root.forkPoints = forks;

        // Full brightness while travelling, then a flickering fade.
        const fade = landed ? Math.max(0, 1 - (root.t - root.travelPortion) / (1 - root.travelPortion)) : 1;
        root.strength = fade * (landed ? 0.65 + Math.random() * 0.35 : 1);
    }

    onTChanged: root.frame()

    NumberAnimation on t {
        id: strikeAnim
        running: false
        from: 0
        to: 1
        duration: root.totalMs
        onFinished: root.finished()
    }

    Component.onCompleted: {
        root.generate();
        root.frame();
        strikeAnim.start();
    }

    Shape {
        anchors.fill: parent
        opacity: root.strength
        preferredRendererType: Shape.CurveRenderer

        // Glow
        ShapePath {
            strokeWidth: 10
            strokeColor: Theme.withAlpha(Theme.accent, 0.18)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.mainPoints }
        }
        ShapePath {
            strokeWidth: 5
            strokeColor: Theme.withAlpha(Theme.accent, 0.12)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: root.forkPoints }
        }
        // Mid
        ShapePath {
            strokeWidth: 3.5
            strokeColor: Theme.withAlpha(Theme.accent, 0.75)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.mainPoints }
        }
        // Core
        ShapePath {
            strokeWidth: 1.4
            strokeColor: "white"
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.mainPoints }
        }
        ShapePath {
            strokeWidth: 1
            strokeColor: Theme.withAlpha("white", 0.7)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathMultiline { paths: root.forkPoints }
        }
    }

    // Impact flash where the bolt meets the pill.
    Rectangle {
        readonly property real k: Math.max(0, (root.t - root.travelPortion) / (1 - root.travelPortion))
        visible: root.t >= root.travelPortion
        x: root.targetX - width / 2
        y: root.targetY - height / 2
        width: 8 + 40 * k
        height: width
        radius: width / 2
        color: Theme.withAlpha(Theme.accent, 0.5)
        opacity: 1 - k
    }
}
