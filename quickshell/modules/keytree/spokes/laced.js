.pragma library
.import "common.js" as C

// Bicycle wheel, 3-cross lacing: each node is held by a leading and a
// trailing spoke that leave the hub 1.5 pitches off-axis and cross their
// neighbours. The trailing side is dimmer, like the far flange.
function draw(ctx, S) {
    for (const n of S.nodes) {
        const off = Math.min(n.step * 1.5, 1.05);
        C.stroke(ctx, S, [C.polar(S, S.h, n.a + off), [n.x, n.y]], S.t, { w: S.lw, a: 0.85 });
        C.stroke(ctx, S, [C.polar(S, S.h, n.a - off), [n.x, n.y]], S.t, { w: S.lw * 0.8, a: 0.38 });
    }
}
