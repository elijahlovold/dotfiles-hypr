import QtQuick
import qs.modules.theme
import "layouts/hex.js" as Hex

// Layout "hex": a honeycomb of tiles around a hub tile. Tiles grow out of
// the tile one ring in, sweeping clockwise ring by ring. Entering a folder
// slides its tile into the hub while the rest fold back; going back folds
// the level into the hub and slides the folder's tile out to its slot.
// Placement: layouts/hex.js.
KeytreeView {
    id: root

    readonly property var cfg: Object.assign({ tileSize: 62, gap: 9, ringDelay: 120 }, layoutConfig.hex ?? {})
    readonly property real tileR: cfg.tileSize
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property var slots: Hex.slots(items.length, tileR, cfg.gap)
    readonly property int rings: slots.length > 0 ? slots[slots.length - 1].k : 1

    halo: true
    preferredSize: Math.ceil(2 * Hex.extent(items.length, tileR, cfg.gap) + 80)

    readonly property int growMs: 300
    readonly property int slideMs: 320
    readonly property int foldMs: 220
    // New tiles wait for the hub to settle.
    readonly property int levelDelay: nav.kind === "open" ? 100 : slideMs
    totalAnimMs: levelDelay + rings * cfg.ringDelay + growMs
    centerAnimDuration: 160
    closeWaitMs: closing ? rings * 60 + foldMs + centerAnimDuration : totalAnimMs
    center: Qt.point(cx, cy)

    function slotOf(key) {
        const i = root.items.findIndex(it => it.key === key);
        return i >= 0 ? root.slots[i] : null;
    }

    function nodeCenter(key) {
        const i = root.items.findIndex(it => it.key === key);
        const t = i >= 0 ? tiles.itemAt(i) : null;
        return t ? t.mapToItem(null, t.width / 2, t.height / 2) : null;
    }

    function nodeFinalCenter(index) {
        const s = root.slots[index];
        return s ? Qt.point(root.cx + s.x, root.cy + s.y) : null;
    }

    function menuContains(x, y) {
        return Math.hypot(x - root.cx, y - root.cy) <= Hex.extent(root.items.length, root.tileR, root.cfg.gap) + 20;
    }

    // ── Level changes ─────────────────────────────────────────────────────
    // `nav` changes just before `items`, while the old level is still laid
    // out: snapshot it into folding ghosts, and start the hub's move.
    property var ghosts: []

    onNavChanged: {
        const old = root.items.map((it, i) => ({ item: it, slot: root.slots[i] }));
        if (nav.kind === "enter") {
            const s = root.slotOf(nav.key);
            root.ghosts = old.filter(g => g.item.key !== nav.key);
            hub.slideFrom(s ? Qt.point(s.x, s.y) : Qt.point(0, 0));
        } else if (nav.kind === "back") {
            root.ghosts = old;
            hub.pop(root.foldMs);
        } else {
            root.ghosts = [];
            hub.pop(0);
        }
    }

    // ── Hub ───────────────────────────────────────────────────────────────
    HexTile {
        id: hub
        z: 2

        property point from: Qt.point(0, 0)
        property real slide: 1
        property real popIn: 0
        // Leaves first on close, like RingView's center.
        property real closeScale: root.closing ? 0 : 1

        x: root.cx + root.from_(from.x, slide) - width / 2
        y: root.cy + root.from_(from.y, slide) - height / 2
        r: root.tileR
        scale: popIn * closeScale
        opacity: popIn
        fill: root.atRoot ? "transparent" : Theme.groupBg
        edge: Theme.centerDot
        edgeWidth: 1.5

        Behavior on closeScale {
            NumberAnimation {
                duration: root.centerAnimDuration
                easing.type: Easing.InCubic
            }
        }

        function slideFrom(p) {
            from = p;
            popIn = 1;
            slideAnim.restart();
        }

        function pop(delay) {
            from = Qt.point(0, 0);
            slide = 1;
            popAnim.delay = delay;
            popAnim.restart();
        }

        NumberAnimation {
            id: slideAnim
            target: hub
            property: "slide"
            from: 0
            to: 1
            duration: root.slideMs
            easing.type: Easing.InOutCubic
        }

        SequentialAnimation {
            id: popAnim
            property int delay: 0
            PropertyAction { target: hub; property: "popIn"; value: 0 }
            PauseAnimation { duration: popAnim.delay }
            NumberAnimation { target: hub; property: "popIn"; to: 1; duration: 260; easing.type: Easing.OutBack }
        }

        Component.onCompleted: pop(0)

        NodeCard {
            anchors.centerIn: parent
            width: root.tileR * 1.5
            height: width
            plain: true
            hub: true
            visible: !root.atRoot
            hubLabel: root.centerLabel
            fontScale: root.fontScale
        }
    }

    // from_(p, u): a coordinate easing from p to 0 (the hub) as u goes 0..1.
    function from_(p, u) {
        return p * (1 - u);
    }

    // ── Tiles ─────────────────────────────────────────────────────────────
    Repeater {
        id: tiles
        model: root.items

        HexTile {
            id: tile
            required property var modelData
            required property int index

            readonly property var slot: root.slots[index] ?? ({ x: 0, y: 0, px: 0, py: 0, k: 1, j: 0, m: 1 })
            // The folder just left slides back out of the hub instead of
            // growing.
            readonly property bool returning: root.nav.kind === "back" && modelData.key === root.nav.key
            readonly property real startX: returning ? 0 : slot.px
            readonly property real startY: returning ? 0 : slot.py

            property real grow: 0

            x: root.cx + startX + (slot.x - startX) * grow - width / 2
            y: root.cy + startY + (slot.y - startY) * grow - height / 2
            r: root.tileR
            // (Returning only shapes the way in; on close it folds like the rest.)
            scale: returning && !root.closing ? 1 : Math.max(0, grow)
            opacity: returning && !root.closing ? 1 : Math.min(1, grow * 2)
            fill: modelData.isLeaf ? Theme.leafBg : Theme.groupBg
            edge: modelData.isLeaf ? Theme.leafBorder : Theme.groupBorder
            edgeWidth: modelData.isLeaf ? 2 : 1

            Behavior on grow {
                SequentialAnimation {
                    PauseAnimation {
                        duration: root.closing
                            ? (root.rings - tile.slot.k) * 60
                            : tile.returning ? 120 : root.levelDelay + (tile.slot.k - 1) * root.cfg.ringDelay + tile.slot.j / tile.slot.m * root.cfg.ringDelay * 0.85
                    }
                    NumberAnimation {
                        duration: root.closing ? root.foldMs : tile.returning ? root.slideMs : root.growMs
                        easing.type: root.closing ? Easing.InCubic : tile.returning ? Easing.InOutCubic : Easing.OutBack
                    }
                }
            }

            Component.onCompleted: tile.grow = 1

            Connections {
                target: root
                function onClosingChanged() {
                    tile.grow = root.closing ? 0 : 1;
                }
            }

            NodeCard {
                anchors.centerIn: parent
                width: root.tileR * 1.6
                height: width
                plain: true
                item: tile.modelData
                fontScale: root.fontScale
                nodeScale: root.nodeScale
            }
        }
    }

    // The previous level folding back into the tiles it grew from.
    Repeater {
        model: root.ghosts

        HexTile {
            id: ghost
            required property var modelData

            property real grow: 1
            readonly property var slot: modelData.slot

            x: root.cx + slot.px + (slot.x - slot.px) * grow - width / 2
            y: root.cy + slot.py + (slot.y - slot.py) * grow - height / 2
            r: root.tileR
            scale: grow
            opacity: grow
            fill: modelData.item.isLeaf ? Theme.leafBg : Theme.groupBg
            edge: modelData.item.isLeaf ? Theme.leafBorder : Theme.groupBorder
            edgeWidth: modelData.item.isLeaf ? 2 : 1

            NumberAnimation on grow {
                to: 0
                duration: root.foldMs
                easing.type: Easing.InCubic
            }

            NodeCard {
                anchors.centerIn: parent
                width: root.tileR * 1.6
                height: width
                plain: true
                item: ghost.modelData.item
                fontScale: root.fontScale
                nodeScale: root.nodeScale
            }
        }
    }

    // Pointy-top hexagon with softly rounded corners, circumradius r.
    component HexTile: Item {
        id: hex

        property real r: 60
        property color fill: "transparent"
        property color edge: "white"
        property real edgeWidth: 1

        width: r * Math.sqrt(3)
        height: r * 2

        onFillChanged: shape.requestPaint()
        onEdgeChanged: shape.requestPaint()

        Canvas {
            id: shape
            anchors.fill: parent
            onWidthChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                const R = hex.r - hex.edgeWidth, cx = width / 2, cy = height / 2;
                const pts = [];
                for (let i = 0; i < 6; i++) {
                    const a = -Math.PI / 2 + i * Math.PI / 3;
                    pts.push([cx + R * Math.cos(a), cy + R * Math.sin(a)]);
                }
                ctx.beginPath();
                ctx.moveTo((pts[5][0] + pts[0][0]) / 2, (pts[5][1] + pts[0][1]) / 2);
                for (let i = 0; i < 6; i++)
                    ctx.arcTo(pts[i][0], pts[i][1], pts[(i + 1) % 6][0], pts[(i + 1) % 6][1], R * 0.14);
                ctx.closePath();
                ctx.fillStyle = hex.fill;
                ctx.fill();
                ctx.lineWidth = hex.edgeWidth;
                ctx.strokeStyle = hex.edge;
                ctx.stroke();
            }
        }
    }
}
