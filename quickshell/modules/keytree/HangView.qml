import QtQuick
import qs.modules.theme
import "layouts/ring.js" as Ring
import "layouts/hang.js" as Hang

// Layout "hang": nodes drop from above the top edge on strings from a rail,
// catch with a bounce and swing to rest. Strings are drawn by SpokeLayer in
// the configured spoke style, each anchored on the rail. A level change
// reels the current nodes up and drops the next ones; the folder's name
// sits on a plaque on the rail. Motion: layouts/hang.js.
KeytreeView {
    id: root

    readonly property var cfg: Object.assign({ length: 190, centerDrop: 150, swing: 0.16, bounce: 0.55 }, layoutConfig.hang ?? {})
    readonly property real nodeD: Ring.nodeDiameter(nodeScale)
    readonly property real nodeR: nodeD / 2
    readonly property real railY: 16
    readonly property real railW: width * 0.86
    readonly property real pinR: 6

    fullscreen: true
    halo: false
    totalAnimMs: 600
    centerAnimDuration: 200
    closeWaitMs: closing ? 700 : totalAnimMs
    center: Qt.point(width / 2, railY + 18)

    // Every string on screen, this level's and those still reeling off:
    // [{ item, ax, L, order, swing, t0, rise }]. Times are on `now`, a
    // clock that only runs while something moves.
    property var strings: []
    property real now: 0
    property bool moving: false

    function nodeCenter(key) {
        for (let i = 0; i < root.strings.length; i++) {
            const s = root.strings[i];
            if (s.rise < 0 && s.item.key === key) {
                const d = cards.itemAt(i);
                return d ? d.mapToItem(null, d.width / 2, d.height / 2) : null;
            }
        }
        return null;
    }

    function nodeFinalCenter(index) {
        const key = root.items[index]?.key;
        const s = root.strings.find(s => s.rise < 0 && s.item.key === key);
        return s ? Qt.point(s.ax, root.railY + s.L) : null;
    }

    function menuContains(x, y) {
        let bottom = root.railY + 40;
        for (const s of root.strings)
            if (s.rise < 0)
                bottom = Math.max(bottom, root.railY + s.L + root.nodeD);
        return y <= bottom && Math.abs(x - root.width / 2) <= root.railW / 2 + root.nodeD;
    }

    // Reel up whatever hangs now, then drop `root.items` after `delay` ms.
    function swap(delay) {
        if (root.width <= 0)
            return;
        const t = root.now;
        const next = root.strings.filter(s => Hang.state(s, t, root.nodeR, root.cfg.bounce) !== null || s.t0 > t);
        for (const s of next)
            if (s.rise < 0)
                s.rise = t + s.order * 25;
        if (delay >= 0) {
            const placed = Hang.strings(root.items.map(it => it.key), root.width / 2, root.railW, root.nodeD, root.cfg);
            root.items.forEach((it, i) => next.push(Object.assign(placed[i], { item: it, t0: t + delay + placed[i].order * 45, rise: -1 })));
        }
        root.strings = next;
        root.moving = true;
    }

    // Re-place the strings still hanging (not their timing) when the
    // geometry they were laid out for changes.
    function relayout() {
        const placed = Hang.strings(root.items.map(it => it.key), root.width / 2, root.railW, root.nodeD, root.cfg);
        for (const s of root.strings) {
            const i = root.items.findIndex(it => it.key === s.item.key);
            if (s.rise < 0 && i >= 0)
                Object.assign(s, { ax: placed[i].ax, L: placed[i].L, order: placed[i].order, swing: placed[i].swing });
        }
        root.strings = root.strings.slice();
    }

    onItemsChanged: swap(nav.kind === "open" && strings.length === 0 ? 60 : 380)
    onWidthChanged: strings.length === 0 ? swap(60) : relayout()
    onNodeDChanged: relayout()
    onCfgChanged: relayout()
    onClosingChanged: swap(closing ? -1 : 200)

    FrameAnimation {
        running: root.moving
        onTriggered: {
            root.now += frameTime * 1000;
            const live = root.strings.filter(s => s.rise < 0 || Hang.state(s, root.now, root.nodeR, root.cfg.bounce) !== null);
            if (live.length !== root.strings.length)
                root.strings = live;
            root.moving = live.some(s => Hang.moving(s, root.now));
        }
    }

    // Per string at `now`: where its node is, or null while off-screen.
    readonly property var positions: strings.map(s => {
        const st = Hang.state(s, root.now, root.nodeR, root.cfg.bounce);
        return st ? { x: s.ax + st.x, y: root.railY + st.y } : null;
    })

    // ── Rail ──────────────────────────────────────────────────────────────
    Rectangle {
        x: (root.width - root.railW) / 2 - root.nodeD * 0.4
        y: root.railY - 1
        width: root.railW + root.nodeD * 0.8
        height: 2
        color: Theme.centerDot
        opacity: root.closing ? 0 : 0.6
        Behavior on opacity { NumberAnimation { duration: root.centerAnimDuration } }
    }

    // ── Strings ───────────────────────────────────────────────────────────
    SpokeLayer {
        width: root.width
        height: Math.min(root.height, root.railY + root.cfg.length + root.cfg.centerDrop + root.nodeD * 2.6)
        style: root.spokes.style ?? "radial"
        layout: ({
            kind: "hang",
            anchored: true,
            nodes: root.strings.map((s, i) => {
                const p = root.positions[i];
                if (!p)
                    return null;
                const d = Math.hypot(p.x - s.ax, p.y - root.railY);
                return d < root.pinR * 2 ? null : {
                    i: i, x: p.x, y: p.y, ox: s.ax, oy: root.railY,
                    a: Math.atan2(p.y - root.railY, p.x - s.ax), d: d,
                    step: 0.5, ring: 0, isLeaf: s.item.isLeaf, key: s.item.key
                };
            }).filter(n => n !== null)
        })
        reveal: 1
        color: Theme[root.spokes.tone ?? "connector"] ?? Theme.connector
        opacity: root.spokes.opacity ?? 0.8
        lineWidth: root.spokes.lineWidth ?? 1.5
        gap: root.spokes.gap ?? 4
        nodeD: root.nodeD
        hubD: root.pinR * 2
    }

    // ── Pins and nodes ────────────────────────────────────────────────────
    Repeater {
        model: root.strings.length

        Rectangle {
            required property int index
            readonly property var s: root.strings[index]
            visible: root.positions[index] !== null
            x: s.ax - width / 2
            y: root.railY - height / 2
            width: root.pinR * 1.4
            height: width
            radius: width / 2
            color: Theme.centerDot
            opacity: 0.85
        }
    }

    Repeater {
        id: cards
        model: root.strings.length

        NodeCard {
            required property int index
            readonly property var p: root.positions[index]
            visible: p !== null
            x: (p?.x ?? 0) - width / 2
            y: (p?.y ?? 0) - height / 2
            width: root.nodeD
            height: root.nodeD
            item: root.strings[index].item
            fontScale: root.fontScale
            nodeScale: root.nodeScale
        }
    }

    // ── Plaque ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.railY - 2
        width: plaqueText.implicitWidth + 40
        height: plaqueText.implicitHeight + 14
        radius: 8
        color: Theme.groupBg
        border.color: Theme.centerDot
        border.width: 1
        opacity: root.closing ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: root.centerAnimDuration } }

        Text {
            id: plaqueText
            anchors.centerIn: parent
            text: root.atRoot ? "keytree" : root.centerLabel
            color: Theme.labelText
            font.pixelSize: Math.round(15 * root.fontScale)
            font.bold: true
        }
    }
}
