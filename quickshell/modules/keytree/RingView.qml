import QtQuick
import qs.modules.theme
import "layouts/ring.js" as Layouts

// Layout "ring": nodes on one ring (two at ringThreshold+ items) around a
// hub, joined by spokes in the configured style (SpokeLayer + spokes/).
// Placement comes from layouts/ring.js; this file composes it with the
// cards and their open/close animations.
KeytreeView {
    id: root

    halo: true
    preferredSize: Layouts.windowSize(items.length, layoutConfig)

    // Nodes bloom in index order, then rewind on close.
    readonly property int nodeAnimDuration: 190
    readonly property int nodeStaggerMs:    18
    totalAnimMs: nodeAnimDuration + Math.max(0, items.length - 1) * nodeStaggerMs

    // Center dot/label closes first, as its own lead-in phase - everything
    // else (nodes, connector lines, halo) waits this long before starting
    // to retreat, so closing reads as two clean phases instead of one big
    // overlapping collapse. Open is unaffected - the center still just
    // appears instantly there, as before; only closing got this new phase.
    centerAnimDuration: 140
    closeWaitMs: closing ? (centerAnimDuration + totalAnimMs) : totalAnimMs

    // Connector-line reveal (spokes, drawn by SpokeLayer below). One
    // shared progress rather than per-node stagger. Unlike per-node
    // entryProgress, the view itself isn't recreated when navigating
    // into a submenu (only the Repeater's node delegates are), so this
    // needs its own explicit replay on every items change, not just the
    // very first open - see _replayReveal.
    property real revealProgress: 0

    Behavior on revealProgress {
        id: revealBehavior
        SequentialAnimation {
            // Waits out the center's own close phase first, same as the
            // node stagger above - see centerAnimDuration.
            PauseAnimation {
                duration: root.closing ? root.centerAnimDuration : 0
            }
            NumberAnimation {
                duration: root.totalAnimMs
                easing.type: root.closing ? Easing.InCubic : Easing.OutCubic
            }
        }
    }

    function _replayReveal() {
        // Behavior intercepts every assignment, including this reset one -
        // toggling it off/on is the standard way to jump a value instantly
        // without also animating the reset itself.
        revealBehavior.enabled = false;
        root.revealProgress = 0;
        revealBehavior.enabled = true;
        root.revealProgress = 1;
    }

    Component.onCompleted: root._replayReveal()
    onItemsChanged: if (!root.closing)
        root._replayReveal()
    // Reopened mid-close (KeytreePanel.reopen) - play the reveal again.
    onClosingChanged: {
        if (closing)
            revealProgress = 0;
        else
            root._replayReveal();
    }

    readonly property real cx:      width  / 2
    readonly property real cy:      height / 2
    // Node cards and the folder hub are circles of this diameter.
    readonly property real nodeD:   Layouts.nodeDiameter(nodeScale)

    // Where every node sits (see layouts/ring.js), with isLeaf merged in for
    // the spoke styles.
    readonly property var layout: {
        const l = Layouts.compute(items.length, width, height, layoutConfig);
        for (const n of l.nodes)
            n.isLeaf = items[n.i].isLeaf;
        return l;
    }

    // At the root the hub is either an empty node-sized ring (spokes.hub
    // "ring") or the small dot; inside a folder it's the labeled card.
    readonly property bool hubRing: (spokes.hub ?? "ring") === "ring"
    readonly property real hubD: atRoot && !hubRing ? 10 : nodeD

    // ── Connectors ────────────────────────────────────────────────────────────

    SpokeLayer {
        anchors.fill: parent
        style:     root.spokes.style ?? "radial"
        layout:    root.layout
        reveal:    root.revealProgress
        color:     Theme[root.spokes.tone ?? "connector"] ?? Theme.connector
        opacity:   root.spokes.opacity ?? 0.8
        lineWidth: root.spokes.lineWidth ?? 1.5
        gap:       root.spokes.gap ?? 4
        nodeD:     root.nodeD
        hubD:      root.hubD
    }

    // ── Center element ────────────────────────────────────────────────────────

    Item {
        id: centerItem
        x: root.cx - width  / 2
        y: root.cy - height / 2
        width:  root.hubD
        height: root.hubD

        // Plain live binding (not the Component.onCompleted-flip trick the
        // nodes use) is fine here since only the 1→0 close transition needs
        // to animate - a Behavior always animates a *later* change to a
        // bound property, it only misses the very first evaluation, which
        // this correctly starts at 1 (visible) regardless.
        property real centerProgress: root.closing ? 0 : 1
        opacity: centerProgress
        scale:   centerProgress

        Behavior on centerProgress {
            NumberAnimation {
                duration: root.centerAnimDuration
                easing.type: Easing.InCubic
            }
        }

        Rectangle {
            visible: atRoot
            anchors.fill: parent
            radius: width / 2
            color:        root.hubRing ? "transparent" : Theme.centerDot
            border.color: Theme.centerDot
            border.width: root.hubRing ? 1 : 0
            opacity: 0.85
        }

        NodeCard {
            visible: !atRoot
            anchors.fill: parent
            hub: true
            hubLabel: root.centerLabel
            fontScale: root.fontScale
        }
    }

    // ── Node cards ────────────────────────────────────────────────────────────

    // Window-local center of the node for `key`, or null - where a launch
    // bolt leaves from (see KeytreePanel.pressKey).
    function nodeCenter(key) {
        const i = root.items.findIndex(it => it.key === key);
        const node = i >= 0 ? nodeRepeater.itemAt(i) : null;
        return node ? node.mapToItem(null, node.width / 2, node.height / 2) : null;
    }

    // Final (post-animation) center of node `index` in this view's
    // coordinates, or null - where bolts aim, whatever the node is doing
    // mid-entrance.
    function nodeFinalCenter(index) {
        const node = nodeRepeater.itemAt(index);
        return node ? Qt.point(node.px, node.py) : null;
    }

    center: Qt.point(root.cx, root.cy)

    Repeater {
        id: nodeRepeater
        model: root.items

        delegate: Item {
            id: node

            required property var modelData
            required property int index

            readonly property var  place: index < root.layout.nodes.length ? root.layout.nodes[index] : ({ x: root.cx, y: root.cy })
            readonly property real px: place.x
            readonly property real py: place.y

            // ── Entrance/exit ──────────────────────────────────────────
            // 0 = hidden/at-start, 1 = fully shown/at-final-position. Plain
            // property (not a binding to root.closing) so the very first
            // open transition actually animates - a Behavior only fires on
            // a real value *change*, not on the initial binding evaluation.
            // Component.onCompleted flips it to 1 on open; the Connections
            // below flips it back to 0 when the whole popup starts closing.
            property real entryProgress: 0

            x: px - root.nodeD / 2
            y: py - root.nodeD / 2
            width:  root.nodeD
            height: root.nodeD
            opacity: entryProgress
            scale:   entryProgress

            Behavior on entryProgress {
                SequentialAnimation {
                    PauseAnimation {
                        // Reversed order on close - the last node to arrive
                        // is the first to retreat, like rewinding the open -
                        // plus centerAnimDuration so nothing here starts
                        // retreating until the center has fully vanished.
                        duration: root.closing ? (root.centerAnimDuration + (root.items.length - 1 - node.index) * root.nodeStaggerMs) : node.index * root.nodeStaggerMs
                    }
                    NumberAnimation {
                        duration: root.nodeAnimDuration
                        easing.type: root.closing ? Easing.InCubic : Easing.OutBack
                    }
                }
            }

            Component.onCompleted: node.entryProgress = 1

            Connections {
                target: root
                function onClosingChanged() {
                    node.entryProgress = root.closing ? 0 : 1;
                }
            }

            NodeCard {
                anchors.fill: parent
                item: node.modelData
                fontScale: root.fontScale
                nodeScale: root.nodeScale
            }
        }
    }
}
