.pragma library
.import "common.js" as C

// Straight line from the hub rim to each node. The original look.
function draw(ctx, S) {
    for (const n of S.nodes)
        C.stroke(ctx, S, [C.polar(S, S.h, n.a), [n.x, n.y]], S.t, { w: S.lw, a: 0.6 });
}
