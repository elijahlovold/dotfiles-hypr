import QtQuick
import qs.modules.theme
import "layouts/ring.js" as Ring
import "layouts/tree.js" as Tree

// Layout "tree" (not named TreeView: that's a built-in QtQuick type, and
// it wins over a local file of the same name): a tree growing from the bottom edge - trunk, recursive
// forks, leaves in a rounded canopy. Entering a folder keeps the whole
// tree: that leaf becomes the folder's hub and sprouts a new cluster of
// branches while the earlier levels dim and the camera pulls back to fit.
// Going back prunes the newest growth from its tips inward. Geometry:
// layouts/tree.js; everything here lives in `world`, which the camera
// pans and scales.
KeytreeView {
    id: root

    readonly property var cfg: Object.assign({ trunk: 210, canopy: 420, thickness: 3.5, fork: 0.42, foliage: true }, layoutConfig.tree ?? {})
    readonly property real nodeD: Ring.nodeDiameter(nodeScale)
    readonly property real nodeR: nodeD / 2
    readonly property real groundY: height - 8
    // Animation timing, ms.
    readonly property int stepMs: 80          // one branch depth of growth
    readonly property int bloomMs: 180        // a leaf popping open
    readonly property int sproutDelayMs: 120  // folder branches start after the hub settles
    readonly property int cameraMs: 420
    readonly property int dimMs: 200
    readonly property int pruneStepMs: 45     // one depth of pruning
    readonly property int pruneSegMs: 80      // one branch retracting
    readonly property int leafFoldMs: 110

    fullscreen: true
    halo: false
    totalAnimMs: 600
    centerAnimDuration: 160
    closeWaitMs: closing ? 700 : totalAnimMs

    readonly property color bark: Qt.darker(Theme.connector, 1.9)
    readonly property color barkEdge: Theme.connector
    readonly property color barkLight: Qt.lighter(Theme.connector, 1.25)

    // Level geometry by id (tree.js results plus the level's items); the
    // model only carries ids so appending/removing a level never rebuilds
    // the others.
    property var levelData: ({})
    property int nextLevel: 0
    ListModel {
        id: levels
    }
    // Levels not being pruned; they're always the first liveCount entries.
    property int liveCount: 0

    function removeLevel(lid) {
        for (let i = 0; i < levels.count; i++) {
            if (levels.get(i).lid === lid) {
                levels.remove(i);
                delete root.levelData[lid];
                return;
            }
        }
    }

    function prune(i) {
        levels.setProperty(i, "pruning", true);
        root.liveCount = Math.min(root.liveCount, i);
    }

    function topLevel() {
        return root.liveCount > 0 ? root.levelData[levels.get(root.liveCount - 1).lid] : null;
    }

    // ── Level changes ─────────────────────────────────────────────────────
    function plant() {
        // The surface can get its width before its height; planting then
        // would put the ground above the screen.
        if (root.width <= 0 || root.height <= 0 || root.items.length === 0)
            return;
        levels.clear();
        root.levelData = {};
        root.liveCount = 0;
        root.addLevel(Tree.root(root.items.length, root.width / 2, root.groundY, root.nodeD, root.cfg), 0);
        camera.jump = true;
        root.fitCamera();
        camera.jump = false;
    }

    function addLevel(geom, delay) {
        const lid = root.nextLevel++;
        root.levelData[lid] = { geom: geom, items: root.items, delay: delay };
        // Before any levels still being pruned, so live ones stay first.
        levels.insert(root.liveCount, { lid: lid, openKey: "", pruning: false });
        root.liveCount++;
    }

    onNavChanged: {
        const top = root.liveCount - 1;
        if (nav.kind === "back" && top > 0) {
            root.prune(top);
            levels.setProperty(top - 1, "openKey", "");
        }
    }

    onItemsChanged: {
        if (nav.kind === "enter" && root.liveCount > 0) {
            const top = root.topLevel();
            const i = top.items.findIndex(it => it.key === nav.key);
            if (i >= 0) {
                levels.setProperty(root.liveCount - 1, "openKey", nav.key);
                root.addLevel(Tree.folder(root.items.length, top.geom.leaves[i], root.nodeD, root.cfg), root.sproutDelayMs);
                root.fitCamera();
                return;
            }
        }
        if (nav.kind === "back" && root.liveCount > 0) {
            root.fitCamera();
            return;
        }
        root.plant();
    }
    // Geometry is in screen px, so a new size replants a root-only tree;
    // deeper in, keep the levels and just refit.
    function resized() {
        if (root.liveCount <= 1 && !root.closing)
            root.plant();
        else
            root.fitCamera();
    }
    onWidthChanged: resized()
    onHeightChanged: resized()
    onClosingChanged: {
        if (closing) {
            for (let i = levels.count - 1; i >= 0; i--)
                root.prune(i);
        } else {
            root.plant();
        }
    }

    // ── Camera ────────────────────────────────────────────────────────────
    // Fits the newest level, its hub and the base of the trunk, keeping the
    // ground on the bottom edge. Never zooms in past 1.
    property var camTarget: ({ s: 1, x: 0, y: 0 })

    function liveLevels() {
        const out = [];
        for (let i = 0; i < root.liveCount; i++)
            out.push(root.levelData[levels.get(i).lid]);
        return out;
    }

    function fitCamera() {
        const live = root.liveLevels();
        const top = live[live.length - 1];
        if (!top)
            return;
        const pts = top.geom.leaves.map(l => [l.x, l.y]).concat([top.geom.hub, [root.width / 2, root.groundY]]);
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const p of pts) {
            x0 = Math.min(x0, p[0] - root.nodeR - 40);
            x1 = Math.max(x1, p[0] + root.nodeR + 40);
            y0 = Math.min(y0, p[1] - root.nodeR - 50);
            y1 = Math.max(y1, p[1]);
        }
        const s = Math.min(1, root.width / (x1 - x0), (root.height - 8) / (y1 - y0));
        root.camTarget = { s: s, x: root.width / 2 - s * (x0 + x1) / 2, y: root.groundY - s * root.groundY };
    }

    function toView(p) {
        return Qt.point(p[0] * root.camTarget.s + root.camTarget.x, p[1] * root.camTarget.s + root.camTarget.y);
    }

    center: {
        const top = root.liveLevels().pop();
        return top ? root.toView(top.geom.hub) : Qt.point(width / 2, height / 2);
    }

    function nodeCenter(key) {
        const lv = levelRepeater.itemAt(root.liveCount - 1);
        return lv ? lv.leafCenter(key) : null;
    }

    function nodeFinalCenter(index) {
        const top = root.liveLevels().pop();
        const l = top?.geom.leaves[index];
        return l ? root.toView([l.x, l.y]) : null;
    }

    function menuContains(x, y) {
        for (const lv of root.liveLevels()) {
            const b = lv.geom.box, a = root.toView([b.x, b.y]), s = root.camTarget.s;
            if (x >= a.x && y >= a.y && x <= a.x + b.w * s && y <= a.y + b.h * s)
                return true;
        }
        return false;
    }

    // Soft light on the ground under the trunk.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.5
        height: 140
        opacity: root.closing ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 600 } }
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(Theme.centerDot.r, Theme.centerDot.g, Theme.centerDot.b, 0.08) }
        }
    }

    Item {
        id: camera
        property bool jump: false
        transformOrigin: Item.TopLeft
        x: root.camTarget.x
        y: root.camTarget.y
        scale: root.camTarget.s
        width: root.width
        height: root.height

        Behavior on x { enabled: !camera.jump; NumberAnimation { duration: root.cameraMs; easing.type: Easing.InOutCubic } }
        Behavior on y { enabled: !camera.jump; NumberAnimation { duration: root.cameraMs; easing.type: Easing.InOutCubic } }
        Behavior on scale { enabled: !camera.jump; NumberAnimation { duration: root.cameraMs; easing.type: Easing.InOutCubic } }

        Repeater {
            id: levelRepeater
            model: levels

            Item {
                id: level
                required property int index
                required property int lid
                required property string openKey
                required property bool pruning

                // Not `data`: that's Item's default property.
                readonly property var info: root.levelData[lid]
                readonly property var geom: info.geom
                readonly property bool isTop: index >= root.liveCount - 1
                readonly property int growTotal: geom.depth * root.stepMs + root.bloomMs + 40
                readonly property int pruneTotal: geom.depth * root.pruneStepMs + root.pruneSegMs + 60

                // Growth and pruning clocks, ms.
                property real grown: 0
                property real pruned: 0
                property real dim: isTop || pruning ? 0 : 1
                Behavior on dim { NumberAnimation { duration: root.dimMs } }

                SequentialAnimation {
                    running: true
                    PauseAnimation { duration: level.info.delay }
                    NumberAnimation { target: level; property: "grown"; from: 0; to: level.growTotal; duration: level.growTotal }
                }

                onPruningChanged: if (pruning) pruneAnim.start()
                NumberAnimation {
                    id: pruneAnim
                    target: level
                    property: "pruned"
                    from: 0
                    to: level.pruneTotal
                    duration: level.pruneTotal
                    onFinished: if (!root.closing) Qt.callLater(root.removeLevel, level.lid)
                }

                function segProgress(depth) {
                    const g = Math.min(1, Math.max(0, (level.grown - depth * root.stepMs) / (root.stepMs * 1.1)));
                    const p = 1 - Math.min(1, Math.max(0, (level.pruned - (level.geom.depth - depth) * root.pruneStepMs) / root.pruneSegMs));
                    return Math.min(g, p);
                }

                function leafCenter(key) {
                    const i = level.info.items.findIndex(it => it.key === key);
                    const d = i >= 0 ? leaves.itemAt(i) : null;
                    return d ? d.mapToItem(null, d.width / 2, d.height / 2) : null;
                }

                Canvas {
                    id: branches
                    x: level.geom.box.x
                    y: level.geom.box.y
                    width: level.geom.box.w
                    height: level.geom.box.h
                    opacity: 1 - level.dim * 0.55

                    readonly property real grown: level.grown
                    readonly property real pruned: level.pruned
                    onGrownChanged: requestPaint()
                    onPrunedChanged: requestPaint()

                    function rng(seed) {
                        let s = seed >>> 0;
                        return () => {
                            s = (s * 1103515245 + 12345) >>> 0;
                            return (s >>> 8) / 16777216;
                        };
                    }

                    // Quadratic Bézier point and tapered width at u.
                    function at(sg, u) {
                        const v = 1 - u;
                        return [v * v * sg.A[0] + 2 * v * u * sg.C[0] + u * u * sg.B[0],
                                v * v * sg.A[1] + 2 * v * u * sg.C[1] + u * u * sg.B[1],
                                sg.w0 + (sg.w1 - sg.w0) * u];
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);
                        ctx.translate(-x, -y);
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";

                        // Roots, on the first level only.
                        if (level.index === 0) {
                            const r = level.segProgress(0);
                            const bx = root.width / 2, gy = root.groundY;
                            ctx.strokeStyle = root.bark;
                            ctx.globalAlpha = r;
                            for (const [dx, w] of [[-90, 6], [-40, 9], [55, 8], [110, 5]]) {
                                ctx.lineWidth = w;
                                ctx.beginPath();
                                ctx.moveTo(bx, gy);
                                ctx.quadraticCurveTo(bx + dx * 0.4, gy + 4, bx + dx, gy + 14);
                                ctx.stroke();
                            }
                            ctx.globalAlpha = 1;
                        }

                        for (const sg of level.geom.segs) {
                            const p = level.segProgress(sg.depth);
                            if (p <= 0)
                                continue;
                            const N = 18, n = Math.max(2, Math.ceil(N * p));
                            const pts = [];
                            for (let i = 0; i <= n; i++)
                                pts.push(at(sg, Math.min(p, i / N)));
                            const left = [], right = [];
                            for (let i = 0; i < pts.length; i++) {
                                const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
                                let nx = -(b[1] - a[1]), ny = b[0] - a[0];
                                const m = Math.hypot(nx, ny) || 1;
                                nx /= m;
                                ny /= m;
                                const w = pts[i][2] / 2;
                                left.push([pts[i][0] + nx * w, pts[i][1] + ny * w]);
                                right.push([pts[i][0] - nx * w, pts[i][1] - ny * w]);
                            }
                            const outline = left.concat(right.reverse());
                            ctx.beginPath();
                            ctx.moveTo(outline[0][0], outline[0][1]);
                            for (let i = 1; i < outline.length; i++)
                                ctx.lineTo(outline[i][0], outline[i][1]);
                            ctx.closePath();
                            ctx.fillStyle = root.bark;
                            ctx.fill();
                            ctx.lineWidth = 1;
                            ctx.strokeStyle = root.barkEdge;
                            ctx.globalAlpha = 0.8;
                            ctx.stroke();

                            // Light down one side of the bark.
                            ctx.beginPath();
                            for (let i = 0; i < pts.length; i++) {
                                const hx = pts[i][0] + (left[i][0] - pts[i][0]) * 0.45;
                                const hy = pts[i][1] + (left[i][1] - pts[i][1]) * 0.45;
                                if (i === 0)
                                    ctx.moveTo(hx, hy);
                                else
                                    ctx.lineTo(hx, hy);
                            }
                            ctx.lineWidth = Math.max(0.8, sg.w1 * 0.18);
                            ctx.strokeStyle = root.barkLight;
                            ctx.globalAlpha = 0.35;
                            ctx.stroke();

                            // Sprigs of foliage on the finer branches.
                            if (root.cfg.foliage && sg.depth >= 2) {
                                const r = rng(sg.seed);
                                ctx.fillStyle = root.barkEdge;
                                for (let j = 0; j < 3; j++) {
                                    const u = 0.25 + r() * 0.6, ang = r() * Math.PI * 2, s = 7 + r() * 6;
                                    if (u > p)
                                        continue;
                                    const q = at(sg, u);
                                    ctx.save();
                                    ctx.translate(q[0], q[1]);
                                    ctx.rotate(ang);
                                    ctx.globalAlpha = 0.55;
                                    ctx.beginPath();
                                    ctx.ellipse(0, -s * 0.42, s * 2, s * 0.84);
                                    ctx.fill();
                                    ctx.restore();
                                }
                            }
                            ctx.globalAlpha = 1;
                        }
                    }
                }

                Repeater {
                    id: leaves
                    model: level.geom.leaves.length

                    NodeCard {
                        id: leaf
                        required property int index
                        readonly property var l: level.geom.leaves[index]
                        readonly property var it: level.info.items[index]
                        readonly property bool isHub: level.openKey === it.key

                        // Blooms once its branch is grown, shrinks first on prune.
                        readonly property real bloom: {
                            const g = Math.min(1, Math.max(0, (level.grown - l.depth * root.stepMs) / root.bloomMs));
                            const p = 1 - Math.min(1, Math.max(0, level.pruned / root.leafFoldMs));
                            return Math.min(root.outBack(g), p);
                        }

                        x: l.x - width / 2
                        y: l.y - height / 2
                        width: root.nodeD
                        height: root.nodeD
                        scale: Math.max(0, bloom) * (isHub ? 1 : 1 - level.dim * 0.3)
                        opacity: Math.min(1, Math.max(0, bloom)) * (isHub ? 1 : 1 - level.dim * 0.65)
                        z: isHub ? 1 : 0
                        item: it
                        hub: isHub
                        hubLabel: it.label
                        fontScale: root.fontScale
                        nodeScale: root.nodeScale
                    }
                }
            }
        }
    }

    function outBack(u) {
        const c = 1.70158;
        return u <= 0 ? 0 : 1 + (c + 1) * Math.pow(u - 1, 3) + c * Math.pow(u - 1, 2);
    }
}
