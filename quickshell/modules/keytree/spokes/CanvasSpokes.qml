import QtQuick
import qs.modules.keytree.spokes

// A static spoke style drawn with Context2D. `painter(ctx, S)` only
// strokes the spokes; this clears first and cuts them back around the hub
// and every node afterwards, so painters can aim at node centers.
//
// The frame S (helpers for it live in common.js):
//   cx, cy      view center, or the node's own origin for anchored layouts
//   h, nr       hub radius (spokes start on it) and node radius
//   nodes       layout nodes: { i, x, y, a, d, step, ring, isLeaf }
//   layout      the whole layout result (kind + layout extras)
//   t           reveal 0..1 - grow outward with it, e.g. C.stroke(.., S.t)
//   color, lw   spoke color and base line width
SpokeStyle {
    id: root

    property var painter: null

    onLayoutChanged: canvas.requestPaint()
    onRevealChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()
    onHubRChanged: canvas.requestPaint()
    onNodeRChanged: canvas.requestPaint()
    onPainterChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function cut(ctx, x, y, r) {
            ctx.beginPath();
            ctx.arc(x, y, r + root.cutGap, 0, Math.PI * 2);
            ctx.fill();
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            const nodes = root.layout.nodes ?? [];
            if (!root.painter || nodes.length === 0 || root.reveal <= 0)
                return;

            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            const S = {
                cx: width / 2,
                cy: height / 2,
                h: root.hubR,
                nr: root.nodeR,
                nodes: nodes,
                layout: root.layout,
                t: Math.min(1, root.reveal),
                color: root.color,
                lw: root.lineWidth
            };
            // Anchored layouts: one spoke per node, drawn around its own
            // origin, as if it were the only node on a hub there.
            if (root.anchored) {
                for (const n of nodes)
                    root.painter(ctx, Object.assign({}, S, { cx: n.ox, cy: n.oy, nodes: [n] }));
            } else {
                root.painter(ctx, S);
            }

            ctx.globalAlpha = 1;
            ctx.globalCompositeOperation = "destination-out";
            ctx.fillStyle = "black";
            if (root.hubR > 0 && !root.anchored)
                cut(ctx, width / 2, height / 2, root.hubR);
            for (const n of nodes)
                cut(ctx, n.x, n.y, root.nodeR);
            ctx.globalCompositeOperation = "source-over";
        }
    }
}
